# Putting the server list + relay on your VPS (auto-updated from GitHub)

When you push changes to `server/` on GitHub, GitHub Actions logs into the VPS and
runs `server/deploy/update.sh`. That script pulls the code and restarts the service.

The server runs as a system user, `bot-party`. It has no login, no home folder
and no rights: it can only read the code and open its two ports.

The update logs in as a separate user, `bp-deploy`. Its SSH key can only run
`update.sh`, and `sudo` lets it restart this one service and nothing else.

Everything below runs on Debian or Ubuntu. Replace `YOU/REPO` with your repository.

## 1. Put the project on GitHub (on your computer)

The folder already has a git history. Create an **empty** repository on
github.com: no README, no .gitignore. Then, in `~/bot-party`:

```sh
git add -A
git commit -m "Bot Party v0.20"
git branch -M main
git remote add origin git@github.com:YOU/REPO.git
git push -u origin main
```

`.godot/` and test leftovers are ignored (see `.gitignore`), so only the real
project goes up. The repository can be private: the VPS uses its own read-only key.

## 2. One-time setup on the VPS

Copy the setup script to the VPS and run it as root:

```sh
scp server/deploy/setup.sh you@your-vps:/tmp/
ssh you@your-vps
sudo bash /tmp/setup.sh git@github.com:YOU/REPO.git
```

The script does the following:

1. Installs `git` and `python3`.
2. Creates the users `bot-party` (runs the server) and `bp-deploy` (updates it).
3. Makes a **read-only pull key** for the VPS, prints the public part, and waits.
   Add the key on GitHub: **repository → Settings → Deploy keys → Add deploy key**.
   Paste it, leave "Allow write access" **off**, save, then press Enter in the
   terminal.
4. Clones the repository to `/opt/bot-party` (owned by `bp-deploy`).
5. Installs and starts the `bot-party-lobby` service, running as `bot-party`.
6. Opens TCP 8910 and UDP 8911 if `ufw` is active.
7. Prints three values for GitHub Actions: `VPS_HOST`, `VPS_USER` and `VPS_KEY`.

If your firewall isn't `ufw` (for example your provider's web panel), open
**TCP 8910** and **UDP 8911** there yourself.

## 3. Let GitHub Actions update the VPS

On GitHub: **repository → Settings → Secrets and variables → Actions →
New repository secret**. Add three secrets:

| Name       | Value                                                     |
|------------|-----------------------------------------------------------|
| `VPS_HOST` | your VPS address (printed by the script)                  |
| `VPS_USER` | `bp-deploy`                                               |
| `VPS_KEY`  | the private key printed by the script, BEGIN/END included |

Then delete the private key from the VPS: `sudo rm /root/bp-actions-key*`.

From now on, every push to `main` that touches `server/` runs
`.github/workflows/deploy-server.yml`. It checks that the script compiles, then
updates the VPS. You can also start it by hand from the **Actions** tab ("Run
workflow"). Pushes that only change the game don't restart anything.

## 4. Check it works

```sh
systemctl status bot-party-lobby          # should be "active (running)", User=bot-party
journalctl -u bot-party-lobby -f          # live log: games listed / unlisted
curl http://localhost:8910/api/servers       # {"you": ..., "servers": [...]}
```

From your computer: `curl http://your-vps:8910/api/servers`.

In the game: **Online → List: …**, type your VPS address (`your-vps` or its IP;
port 8910 is added automatically). Then **Host public game** on one computer and
**Server list** on another.

## Updating by hand / troubleshooting

* Update now without pushing: `sudo -u bp-deploy /opt/bot-party/server/deploy/update.sh`
* If the `.service` file changed, `update.sh` prints the root command that installs it.
  Unit files need root, and `bp-deploy` doesn't have it on purpose.
* **The Action fails at "Update the VPS".** Check the three secrets. `VPS_KEY` must
  be the full private key. Port 22 must be reachable from GitHub.
* **The Action works but the VPS can't pull.** Check the deploy key on GitHub:
  `sudo -u bp-deploy ssh -T git@github.com` should greet you.
* **Players can't see the list.** Check that TCP 8910 is open (`curl` from outside).
* **Relay doesn't work.** Check that **UDP** 8911 is open. Many panels only open TCP
  by default.
* The server keeps no files, so restarting it is always safe. Games that are
  hosting re-register within 10 seconds.

## What runs where

| Path / user                     | What                                                  |
|---------------------------------|-------------------------------------------------------|
| `/opt/bot-party`             | git checkout of your repo (owner `bp-deploy`)         |
| `bot-party` (system user)    | runs `server/lobby_server.py`, no login, no rights    |
| `bp-deploy` (login user)        | SSH key limited to `update.sh`; may only restart the service |
| `/etc/systemd/system/bot-party-lobby.service` | the service (hardened: read-only system, no home access) |
