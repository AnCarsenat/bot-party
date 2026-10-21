#!/bin/bash
# One-time setup of the Bot Party server list + relay on a VPS (Debian/Ubuntu).
# Run as root:   sudo bash setup.sh git@github.com:YOU/REPO.git
#
# It creates two users:
#   bot-party   system user that RUNS the server (no login, no home, no rights)
#   bp-deploy      login user that GitHub Actions uses to update the code; it can
#                  only run update.sh (forced command) and restart the service.
set -euo pipefail

REPO="${1:?usage: setup.sh <git url of your repository>}"
DIR=/opt/bot-party
SERVICE=bot-party-lobby

[ "$(id -u)" = 0 ] || { echo "run me as root (sudo)"; exit 1; }
apt-get update -qq
apt-get install -y -qq git python3 >/dev/null

# 1. Users.
id bot-party >/dev/null 2>&1 || useradd --system --no-create-home --shell /usr/sbin/nologin bot-party
id bp-deploy >/dev/null 2>&1 || useradd --create-home --home-dir /var/lib/bp-deploy --shell /bin/bash bp-deploy
install -d -m 700 -o bp-deploy -g bp-deploy /var/lib/bp-deploy/.ssh

# 2. Read-only key so the VPS can pull from GitHub (also works for private repos).
if [ ! -f /var/lib/bp-deploy/.ssh/github_pull ]; then
	sudo -u bp-deploy ssh-keygen -q -t ed25519 -N "" -C "bot-party VPS pull" -f /var/lib/bp-deploy/.ssh/github_pull
fi
cat > /var/lib/bp-deploy/.ssh/config <<CFG
Host github.com
	IdentityFile /var/lib/bp-deploy/.ssh/github_pull
	StrictHostKeyChecking accept-new
CFG
chown bp-deploy:bp-deploy /var/lib/bp-deploy/.ssh/config

# 3. Key that GitHub Actions uses to log in here. It can ONLY run update.sh.
if [ ! -f /root/bp-actions-key ]; then
	ssh-keygen -q -t ed25519 -N "" -C "github actions -> bot-party" -f /root/bp-actions-key
fi
echo "command=\"$DIR/server/deploy/update.sh\",no-port-forwarding,no-agent-forwarding,no-X11-forwarding,no-pty $(cat /root/bp-actions-key.pub)" \
	> /var/lib/bp-deploy/.ssh/authorized_keys
chown bp-deploy:bp-deploy /var/lib/bp-deploy/.ssh/authorized_keys
chmod 600 /var/lib/bp-deploy/.ssh/authorized_keys

# 4. bp-deploy may restart the service, nothing else.
cat > /etc/sudoers.d/bp-deploy <<SUDO
bp-deploy ALL=(root) NOPASSWD: /usr/bin/systemctl restart $SERVICE, /usr/bin/systemctl is-active $SERVICE
SUDO
chmod 440 /etc/sudoers.d/bp-deploy
visudo -cf /etc/sudoers.d/bp-deploy >/dev/null

# 5. The code (owned by bp-deploy, readable by everyone, so bot-party can run it).
install -d -o bp-deploy -g bp-deploy -m 755 "$DIR"

echo
echo "=== Add this key to GitHub: repository > Settings > Deploy keys > Add (read-only) ==="
cat /var/lib/bp-deploy/.ssh/github_pull.pub
echo
read -r -p "Press Enter once the deploy key is added on GitHub... "

if [ ! -d "$DIR/.git" ]; then
	sudo -u bp-deploy git clone --depth 1 "$REPO" "$DIR"
fi

# 6. The service, running as bot-party.
install -m 644 "$DIR/server/deploy/$SERVICE.service" /etc/systemd/system/$SERVICE.service
systemctl daemon-reload
systemctl enable --now $SERVICE

# 7. Firewall (if ufw is used).
if command -v ufw >/dev/null && ufw status | grep -q active; then
	ufw allow 8910/tcp && ufw allow 8911/udp
fi

echo
echo "=== Done. The server runs as 'bot-party':  systemctl status $SERVICE ==="
echo "=== For GitHub Actions, add these repository secrets (Settings > Secrets > Actions): ==="
echo "VPS_HOST = $(curl -s -4 ifconfig.me || hostname -I | cut -d' ' -f1)"
echo "VPS_USER = bp-deploy"
echo "VPS_KEY  = (the whole private key below, including the BEGIN/END lines)"
cat /root/bp-actions-key
echo
echo "Then delete it from the VPS:  sudo rm /root/bp-actions-key /root/bp-actions-key.pub"
