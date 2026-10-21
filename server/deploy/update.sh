#!/bin/bash
# Pulls the latest code and restarts the server when its code changed.
# Runs as bp-deploy: started by GitHub Actions over SSH (forced command), or by hand:
#   sudo -u bp-deploy /opt/bot-party/server/deploy/update.sh
set -euo pipefail
DIR=/opt/bot-party
SERVICE=bot-party-lobby
BRANCH=main

cd "$DIR"
before=$(git rev-parse HEAD)
git fetch --quiet --depth 1 origin "$BRANCH"
git reset --quiet --hard FETCH_HEAD
after=$(git rev-parse HEAD)
echo "code: ${before:0:7} -> ${after:0:7}"

if [ "$before" = "$after" ]; then
	echo "already up to date"
elif git diff --quiet "$before" "$after" -- server/lobby_server.py; then
	echo "server script unchanged, no restart"
else
	sudo /usr/bin/systemctl restart "$SERVICE"
	sleep 1
	echo "service: $(sudo /usr/bin/systemctl is-active "$SERVICE")"
fi
if ! git diff --quiet "$before" "$after" -- server/deploy/bot-party-lobby.service; then
	echo "NOTE: the systemd unit changed; as root run:"
	echo "  install -m 644 $DIR/server/deploy/bot-party-lobby.service /etc/systemd/system/ && systemctl daemon-reload && systemctl restart $SERVICE"
fi
