#!/usr/bin/env python3
"""Bot Party server list + relay. Standard library only (Python 3.8+).

  HTTP  (TCP, default 8910): the server list
     POST /api/host       {name, port, max, players, mode, lan_ip}  -> {id, token, ip, relay_port}
     POST /api/heartbeat  {id, token, players, mode}                -> {ok}
     POST /api/close      {id, token}                               -> {ok}
     GET  /api/servers                                              -> {you, relay_port, servers: [...]}
  Relay (UDP, default 8911): forwards game traffic for players who can't reach
  the host directly (see net/relay.gd in the game for the packet format).

Run:   python3 lobby_server.py [--http-port 8910] [--relay-port 8911]
Open TCP 8910 and UDP 8911 on the VPS firewall.
"""
import argparse
import asyncio
import json
import logging
import secrets
import struct
import time

HELLO_HOST, HELLO_CLIENT, JOIN, LEFT, ACK = 0x01, 0x02, 0x03, 0x04, 0x05
TO_CLIENT, TO_HOST = 0x10, 0x11

HOST_TIMEOUT = 30.0      # unlisted if no heartbeat for this long
CLIENT_TIMEOUT = 15.0    # relay clients forgotten after this long without packets
MAX_SERVERS = 500
MAX_BODY = 4096
MAX_CLIENTS_PER_SERVER = 16

log = logging.getLogger("lobby")


def clean_names(names):
    """Who is in a game (shown in the list): up to 8 short names."""
    if not isinstance(names, list):
        return []
    return [str(n)[:20] for n in names[:8]]


class Server:
    def __init__(self, sid, token, ip, info):
        self.id, self.token, self.ip = sid, token, ip
        self.info = info
        self.seen = time.monotonic()
        self.relay_addr = None          # host's UDP address on the relay
        self.clients = {}               # cid -> client addr
        self.next_cid = 1


class Lobby:
    def __init__(self):
        self.servers = {}               # id -> Server
        self.client_of = {}             # client addr -> (server id, cid, last seen)
        self.relay = None               # the UDP transport

    # --- HTTP API -------------------------------------------------------------
    def api(self, method, path, body, ip):
        self.expire()
        if method == "GET" and path == "/api/servers":
            return {"you": ip, "relay_port": ARGS.relay_port, "servers": [
                {"id": s.id, "name": s.info["name"], "ip": s.ip, "port": s.info["port"],
                 "lan_ip": s.info.get("lan_ip", ""), "players": s.info["players"], "max": s.info["max"],
                 "mode": s.info.get("mode", ""), "names": s.info.get("names", []),
                 "relay": s.relay_addr is not None}
                for s in self.servers.values()]}
        if method != "POST":
            return None
        if path == "/api/host":
            if len(self.servers) >= MAX_SERVERS:
                raise ValueError("server list full")
            info = {
                "name": str(body.get("name", "Game"))[:40],
                "port": int(body.get("port", 7777)),
                "max": max(1, min(8, int(body.get("max", 8)))),
                "players": max(0, min(8, int(body.get("players", 1)))),
                "mode": str(body.get("mode", ""))[:12],
                "lan_ip": str(body.get("lan_ip", ""))[:40],
                "names": clean_names(body.get("names")),
            }
            sid = secrets.token_hex(4)          # 8 characters
            token = secrets.token_hex(8)        # 16 characters
            self.servers[sid] = Server(sid, token, ip, info)
            log.info("listed %s %r from %s", sid, info["name"], ip)
            return {"id": sid, "token": token, "ip": ip, "relay_port": ARGS.relay_port}
        s = self.servers.get(str(body.get("id", "")))
        if s is None or s.token != body.get("token"):
            raise ValueError("unknown server")
        if path == "/api/heartbeat":
            s.seen = time.monotonic()
            s.info["players"] = max(0, min(8, int(body.get("players", s.info["players"]))))
            s.info["mode"] = str(body.get("mode", s.info["mode"]))[:12]
            if "names" in body:
                s.info["names"] = clean_names(body.get("names"))
            if "name" in body:
                s.info["name"] = str(body.get("name"))[:40] or s.info["name"]
            return {"ok": True}
        if path == "/api/close":
            self.remove(s.id)
            return {"ok": True}
        return None

    def remove(self, sid):
        s = self.servers.pop(sid, None)
        if s:
            for addr in list(s.clients.values()):
                self.client_of.pop(addr, None)
            log.info("unlisted %s", sid)

    def expire(self):
        now = time.monotonic()
        for sid in [k for k, s in self.servers.items() if now - s.seen > HOST_TIMEOUT]:
            self.remove(sid)
        for addr, (sid, cid, seen) in list(self.client_of.items()):
            if now - seen > CLIENT_TIMEOUT:
                self.drop_client(addr)

    def drop_client(self, addr):
        sid, cid, _ = self.client_of.pop(addr, (None, None, None))
        s = self.servers.get(sid)
        if s:
            s.clients.pop(cid, None)
            if s.relay_addr:
                self.relay.sendto(bytes([LEFT]) + struct.pack(">H", cid), s.relay_addr)

    # --- Relay ------------------------------------------------------------------
    def datagram(self, data, addr):
        if not data:
            return
        kind = data[0]
        if kind == HELLO_HOST and len(data) >= 25:
            s = self.servers.get(data[1:9].decode("ascii", "replace"))
            if s and s.token == data[9:25].decode("ascii", "replace"):
                s.relay_addr = addr
                s.seen = time.monotonic()
                self.relay.sendto(bytes([ACK]), addr)
        elif kind == HELLO_CLIENT and len(data) >= 9:
            s = self.servers.get(data[1:9].decode("ascii", "replace"))
            if not s or not s.relay_addr:
                return
            known = self.client_of.get(addr)
            if known:
                self.client_of[addr] = (known[0], known[1], time.monotonic())
            elif len(s.clients) < MAX_CLIENTS_PER_SERVER:
                cid = s.next_cid
                s.next_cid = s.next_cid % 65535 + 1
                s.clients[cid] = addr
                self.client_of[addr] = (s.id, cid, time.monotonic())
                self.relay.sendto(bytes([JOIN]) + struct.pack(">H", cid), s.relay_addr)
            self.relay.sendto(bytes([ACK]), addr)
        elif kind == TO_CLIENT:
            # From a client: forward to its host.
            known = self.client_of.get(addr)
            if not known:
                return
            sid, cid, _ = known
            self.client_of[addr] = (sid, cid, time.monotonic())
            s = self.servers.get(sid)
            if s and s.relay_addr:
                self.relay.sendto(bytes([TO_HOST]) + struct.pack(">H", cid) + data[1:], s.relay_addr)
        elif kind == TO_HOST and len(data) >= 3:
            # From a host: forward to one of its clients.
            cid = struct.unpack(">H", data[1:3])[0]
            for s in self.servers.values():
                if s.relay_addr == addr:
                    target = s.clients.get(cid)
                    if target:
                        self.relay.sendto(bytes([TO_CLIENT]) + data[3:], target)
                    break


LOBBY = Lobby()


class RelayProtocol(asyncio.DatagramProtocol):
    def connection_made(self, transport):
        LOBBY.relay = transport

    def datagram_received(self, data, addr):
        try:
            LOBBY.datagram(data, addr)
        except Exception:  # never let one bad packet stop the relay
            log.exception("relay packet from %s", addr)


async def http_client(reader, writer):
    ip = writer.get_extra_info("peername")[0]
    status, out = 400, {"error": "bad request"}
    try:
        head = await asyncio.wait_for(reader.readuntil(b"\r\n\r\n"), 5)
        lines = head.decode("latin-1").split("\r\n")
        method, path, _ = lines[0].split(" ", 2)
        headers = {k.strip().lower(): v.strip() for k, v in (l.split(":", 1) for l in lines[1:] if ":" in l)}
        length = min(int(headers.get("content-length", "0") or 0), MAX_BODY)
        raw = await asyncio.wait_for(reader.readexactly(length), 5) if length else b""
        body = json.loads(raw.decode("utf-8")) if raw else {}
        if not isinstance(body, dict):
            body = {}
        result = LOBBY.api(method, path.split("?")[0], body, ip)
        if result is None:
            status, out = 404, {"error": "not found"}
        else:
            status, out = 200, result
    except ValueError as e:
        status, out = 403, {"error": str(e)}
    except Exception as e:  # malformed request, timeout...
        status, out = 400, {"error": type(e).__name__}
    payload = json.dumps(out).encode("utf-8")
    reason = {200: "OK", 400: "Bad Request", 403: "Forbidden", 404: "Not Found"}[status]
    writer.write(f"HTTP/1.1 {status} {reason}\r\nContent-Type: application/json\r\n"
                 f"Content-Length: {len(payload)}\r\nConnection: close\r\n\r\n".encode() + payload)
    try:
        await writer.drain()
    finally:
        writer.close()


async def housekeeping():
    while True:
        await asyncio.sleep(5)
        LOBBY.expire()


async def main():
    loop = asyncio.get_running_loop()
    await loop.create_datagram_endpoint(RelayProtocol, local_addr=(ARGS.bind, ARGS.relay_port))
    server = await asyncio.start_server(http_client, ARGS.bind, ARGS.http_port)
    log.info("server list on tcp %d, relay on udp %d", ARGS.http_port, ARGS.relay_port)
    asyncio.create_task(housekeeping())
    async with server:
        await server.serve_forever()


if __name__ == "__main__":
    p = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    p.add_argument("--bind", default="0.0.0.0")
    p.add_argument("--http-port", type=int, default=8910)
    p.add_argument("--relay-port", type=int, default=8911)
    ARGS = p.parse_args()
    logging.basicConfig(level=logging.INFO, format="%(asctime)s %(message)s")
    asyncio.run(main())
