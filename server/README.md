# Bot Party server list + relay

`lobby_server.py` lists online games and relays traffic for players who can't
connect to the host directly. It only uses Python's standard library.

## Run it on the VPS

See **DEPLOY.md**: a one-time setup script, a system user to run it, and automatic
updates from GitHub on every push.

To just try it anywhere: `python3 lobby_server.py` (TCP 8910 and UDP 8911).

## How players connect

1. The host picks **Host public game**: the game registers on the list.
2. Others open **Server list** and pick it. They first try to connect straight to
   the host (UDP 7777). If that fails within 3 seconds, they go through the relay.
3. **Join by address** skips the list (the host needs UDP 7777 forwarded, or to be
   on the same network).

Relay traffic goes through the VPS: roughly 30-60 KB/s per relayed player.
