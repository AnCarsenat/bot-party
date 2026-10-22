# Builds

GitHub Actions (`.github/workflows/build.yml`) builds the game for Linux,
Windows and macOS with Godot 4.7.2 (set in the workflow), using `export_presets.cfg`.

- **Every push to `main`** replaces the **nightly** pre-release
  (repository → Releases → "Nightly"). Each run also keeps its zips for 14 days
  under Actions → the run → Artifacts.
- **Every tag starting with `v`** makes a release with that name:

  ```sh
  git tag v0.27
  git push origin v0.27
  ```

Players install and update with `install.sh` (Linux, macOS) or `install.ps1`
(Windows): they download the latest release, or the nightly with `--nightly` /
`-Nightly`. See the README.

The menu shows the build name in the bottom-right corner (`v0.27`, or
`nightly-20261022-1a2b3c4`).

Pushes that only change `server/` or `.md` files don't start a build. You can
also start one by hand from the Actions tab ("Run workflow").

The macOS build isn't signed by Apple. The first time, right-click the app →
Open (or allow it in System Settings → Privacy & Security).

To build on your own computer: Godot → Project → Export, or
`godot --headless --export-release "Linux" export/linux/BotParty.x86_64`
(after Editor → Manage Export Templates → Download).
