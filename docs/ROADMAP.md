# Roadmap

What is planned, roughly in order, with an effort estimate. Estimates are working days for one
person and are guesses, not commitments; nothing here is scheduled.

---

## Table of content

  - [1. Downloadable setup files (GitHub Releases)](#1-downloadable-setup-files-github-releases)
  - [2. Linux and macOS](#2-linux-and-macos)
  - [3. Windows 11 top-level menu](#3-windows-11-top-level-menu)
  - [4. Smaller items](#4-smaller-items)
  - [Effort at a glance](#effort-at-a-glance)

---

## 1. Downloadable setup files (GitHub Releases)

Goal: nobody has to clone the repository. Every tagged version (`v*`) gets a GitHub Release with
ready-made setup files for each supported system, built by GitHub Actions, with checksums.

**Windows (first, the program exists):**

| Step | Effort |
| --- | --- |
| Release workflow: on a tag, build `OpenInNvim.exe` on `windows-latest` (same `csc` call as `build.ps1`), run the test suite, attach the exe and a zip (exe, ini template, install/uninstall scripts) with SHA-256 sums | 0.5 |
| Setup program (Inno Setup): per-user install without administrator rights, writes the six menu entries and the ini, registers an uninstaller under "Apps", offers the default-app registration as an option | 1 |
| Version number in the exe and `OpenInNvim.exe --version`; a changelog file the release notes are taken from | 0.5 |

Open question: the setup is not code-signed, so Windows SmartScreen warns on first run. A
certificate costs money every year; until there is one the release notes say so and list the
checksums.

## 2. Linux and macOS

The Windows program talks to Neovim over named pipes and uses Windows APIs for the trust check, so
it does not run elsewhere as it is. Two ways:

- **A. Port the core to one portable language** (a single static binary per system, for example Go
  or Rust): pipe discovery becomes socket discovery (`$XDG_RUNTIME_DIR/nvim.<pid>.0`, on macOS
  `$TMPDIR/nvim.<user>/...`), the trust check becomes "socket owner is me", the msgpack-RPC client,
  the open logic and the tests carry over. Windows would then use the same code and the C#
  version is retired. One code base for three systems.
- **B. Keep C# for Windows and write a small shell launcher for Linux/macOS** around
  `nvim --server <socket> --remote`. Faster to have, but two implementations, and the shell
  version would lack the checks (blocked instance, file names with special characters).

Recommended: A, because every later feature is then written once.

| Step | Effort |
| --- | --- |
| A: port of the core with tests on all three systems (CI matrix) | 5 - 7 |
| Linux integration: `.desktop` entry ("Open with"), Nautilus script, Dolphin service menu, Nemo action (drafts exist in the author's `Configs` repository) | 1 |
| Linux packages: `tar.gz` + `install.sh`; then `.deb` / `.rpm`; an AUR recipe | 0.5 + 1 + 0.5 |
| macOS integration: a Finder Quick Action ("Open in Neovim (current / new)"), terminal start through `open -a` (WezTerm, iTerm2, Terminal) | 1 - 2 |
| macOS package: `.pkg` or `.dmg`; signing and notarisation need an Apple Developer ID (yearly fee) and a Mac for testing | 1 - 2 |
| Release workflow for the three systems (build matrix, assets, checksums) | 1 |

If only B is wanted: Linux and macOS shell launchers with their menu integrations, 2 - 3 days in
total, without packages.

## 3. Windows 11 top-level menu

Entries written under `HKCU\...\shell` appear in the classic menu only ("Show more options"). The
short Windows 11 menu needs a shell extension (`IExplorerCommand`) delivered in a signed package
with identity. Effort: 3 - 5 days, plus the signing certificate from item 1.

## 4. Smaller items

| Item | Effort |
| --- | --- |
| Command-line window open (`q:`) in the target instance: close it and open the file instead of going to the next instance | 0.5 |
| A prompt that appears between the probe and the request: after the wait, try the next instance instead of giving up silently | 0.5 |
| Two icons for the two menu entries (`Logos\*.ico`) | 0.25 |
| WezTerm: raise the exact window through `wezterm cli` when several windows are open | 0.5 |
| Test the trust check with a second user account and a second logon session | 0.5 |
| CI: build and test on every push | 0.5 |

## Effort at a glance

| Scope | Days |
| --- | --- |
| Windows setup file on GitHub Releases (item 1) | 2 |
| All three systems with one portable core, packages and release workflow (items 1 and 2, way A) | 11 - 15 |
| All three systems with a shell launcher for Linux/macOS, no packages (way B) | 4 - 5 |
| Windows 11 top-level menu (item 3) | 3 - 5 |
