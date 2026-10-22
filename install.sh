#!/usr/bin/env bash
# Installs (or updates) Bot Party on Linux or macOS from the GitHub releases.
#
#   curl -fsSL https://raw.githubusercontent.com/AnCarsenat/bot-party/main/install.sh | bash
#   curl -fsSL https://raw.githubusercontent.com/AnCarsenat/bot-party/main/install.sh | bash -s -- --nightly
#   curl -fsSL https://raw.githubusercontent.com/AnCarsenat/bot-party/main/install.sh | bash -s -- --uninstall
#
# Linux: the game goes to ~/.local/share/bot-party, with a "bot-party" command in
#        ~/.local/bin and an entry in your applications menu.
# macOS: "Bot Party.app" goes to ~/Applications.
# Run it again to update. Needs curl and unzip.
set -euo pipefail

REPO="${BOT_PARTY_REPO:-AnCarsenat/bot-party}"
API_BASE="${BOT_PARTY_API:-https://api.github.com}"  # (for testing)
CHANNEL=latest
ACTION=install
for arg in "$@"; do
	case "$arg" in
		--nightly) CHANNEL=nightly ;;
		--stable) CHANNEL=latest ;;
		--uninstall) ACTION=uninstall ;;
		-h|--help)
			sed -n '2,12p' "$0" 2>/dev/null || echo "Options: --nightly  --uninstall"
			exit 0 ;;
		*) echo "Unknown option: $arg (try --help)"; exit 1 ;;
	esac
done

say() { printf '\033[1m%s\033[0m\n' "$*"; }
die() { printf '\033[31m%s\033[0m\n' "$*" >&2; exit 1; }

case "$(uname -s)" in
	Linux) OS=linux ;;
	Darwin) OS=macos ;;
	*) die "This script is for Linux and macOS. On Windows, use install.ps1 (see the README)." ;;
esac

LINUX_DIR="$HOME/.local/share/bot-party"
LINUX_BIN="$HOME/.local/bin/bot-party"
LINUX_DESKTOP="$HOME/.local/share/applications/bot-party.desktop"
MAC_APP="$HOME/Applications/Bot Party.app"

if [ "$ACTION" = uninstall ]; then
	if [ "$OS" = linux ]; then
		rm -rf "$LINUX_DIR" "$LINUX_BIN" "$LINUX_DESKTOP"
	else
		rm -rf "$MAC_APP"
	fi
	say "Bot Party removed. (Your saves and settings stay in Godot's user data folder.)"
	exit 0
fi

command -v curl >/dev/null || die "curl is needed"
command -v unzip >/dev/null || die "unzip is needed (sudo apt install unzip, sudo pacman -S unzip...)"

# Which release: the latest stable one, or the nightly build.
if [ "$CHANNEL" = nightly ]; then
	API="$API_BASE/repos/$REPO/releases/tags/nightly"
else
	API="$API_BASE/repos/$REPO/releases/latest"
fi
JSON="$(curl -fsSL "$API")" || die "Couldn't find a $CHANNEL release of $REPO. (No release yet? Try --nightly.)"
URL="$(printf '%s' "$JSON" | grep -o "\"browser_download_url\": *\"[^\"]*-$OS\.zip\"" | head -n1 | sed 's/.*: *"\(.*\)"/\1/')"
NAME="$(printf '%s' "$JSON" | grep -o '"name": *"[^"]*"' | head -n1 | sed 's/.*: *"\(.*\)"/\1/')"
[ -n "$URL" ] || die "That release has no $OS build."

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
say "Downloading $NAME ($OS)..."
curl -fL --progress-bar -o "$TMP/game.zip" "$URL"

if [ "$OS" = linux ]; then
	rm -rf "$LINUX_DIR"
	mkdir -p "$LINUX_DIR" "$(dirname "$LINUX_BIN")" "$(dirname "$LINUX_DESKTOP")"
	unzip -q "$TMP/game.zip" -d "$LINUX_DIR"
	chmod +x "$LINUX_DIR/BotParty.x86_64"
	cat > "$LINUX_BIN" <<EOF
#!/bin/sh
exec "$LINUX_DIR/BotParty.x86_64" "\$@"
EOF
	chmod +x "$LINUX_BIN"
	cat > "$LINUX_DESKTOP" <<EOF
[Desktop Entry]
Type=Application
Name=Bot Party
Comment=Co-op platformer and party game for 1 to 8 robots
Exec="$LINUX_DIR/BotParty.x86_64"
Icon=$LINUX_DIR/BotParty.png
Terminal=false
Categories=Game;ArcadeGame;
EOF
	command -v update-desktop-database >/dev/null && update-desktop-database "$(dirname "$LINUX_DESKTOP")" 2>/dev/null || true
	say "Installed $NAME."
	echo "Start it from your applications menu, or type: bot-party"
	case ":$PATH:" in *":$HOME/.local/bin:"*) ;; *) echo "(Add ~/.local/bin to your PATH to use the bot-party command.)" ;; esac
else
	unzip -q "$TMP/game.zip" -d "$TMP/app"
	APP="$(find "$TMP/app" -maxdepth 2 -name '*.app' | head -n1)"
	[ -n "$APP" ] || die "No .app in the download"
	mkdir -p "$HOME/Applications"
	rm -rf "$MAC_APP"
	mv "$APP" "$MAC_APP"
	# Downloaded by this script, not a browser: no "unidentified developer" block.
	xattr -dr com.apple.quarantine "$MAC_APP" 2>/dev/null || true
	say "Installed $NAME in ~/Applications."
	echo "Start it from Launchpad or Finder, or: open \"$MAC_APP\""
fi
