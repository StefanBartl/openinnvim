# Installation

Two ways: the **setup program** (nothing else to download) or the **script** (builds from a clone).

## Setup program (recommended)

`OpenInNvim-Setup.exe` carries everything: the launcher, `uninstall.exe`, the config template and the two
icons. Double-click it, pick a folder, optionally tick *Also offer Neovim in Windows' "Default apps" and
"Open with" lists*, click *Install*. Per user, no administrator rights, nothing is written outside `HKCU` and
the install folder.

The checkbox only adds two choices, "Neovim (new instance)" and "Neovim (current instance)", to Windows'
lists: Windows does not let a program make itself the default, so you still pick one per file type yourself
(Settings > Apps > Default apps). Nothing is switched for you, and the context menu works without it.

| Command line | Effect |
| --- | --- |
| `OpenInNvim-Setup.exe /S` | Silent. The folder of an earlier install, otherwise `%LOCALAPPDATA%\OpenInNvim`. |
| `/D=<folder>` | Install folder (absolute; a git repository is refused). |
| `/DEFAULT=yes` | The checkbox: also offer both entries in the default-app lists. (`new` or `current` additionally name the mode of the generic `Neovim.TextFile` entry; `current` is the default.) |
| `/NVIM=<nvim.exe>` | Use this Neovim instead of searching (`PATH`, official installer, winget, scoop). |
| `/LOG=<file>` | Write what happened to a file. |

An existing `open-in-nvim.ini` is kept (it is yours). Running the setup again updates the program, also
while a launcher is running. The program is listed under *Settings > Apps* and as `uninstall.exe` in the
install folder: it asks, removes the menu entries, the default-app entries, the *Apps* entry and the files,
keeps your ini (unless you tick the box, or pass `/REMOVECONFIG`) and removes the folder when it is empty.
`uninstall.exe /S` is the silent form. Both programs are built by `build-setup.ps1` (see the README); the
setup is **not code-signed**, so Windows SmartScreen may warn on first run, and the release notes list the
SHA-256 checksum to compare.

## Script (from a clone)

One script. It builds `OpenInNvim.exe` into a folder of your own, finds `nvim.exe`,
writes the config and registers the six context-menu entries. Nothing is installed
system-wide and no administrator rights are needed — everything lives under `HKCU` and
`%LOCALAPPDATA%`.

```powershell
git clone https://github.com/StefanBartl/openinnvim.git
cd openinnvim
powershell -NoProfile -ExecutionPolicy Bypass -File .\install.ps1
```

That is all. On Windows 11 the entries appear under **Show more options** (the classic
menu); try them with [quickstart.md](quickstart.md).

## What `install.ps1` does

1. **Finds Neovim**: `nvim.exe` on `PATH`, then the official installer, winget and scoop
   locations. The result is written into a new config as `NVIM_BIN` and used as the
   menu icon. `-NvimExe <path>` overrides it.
2. **Builds** `OpenInNvim.exe` from `src\*.cs` into `%LOCALAPPDATA%\OpenInNvim`
   (`-InstallDir <folder>` for another place). The build is `build.ps1`: one call of the
   C# compiler that ships with Windows (`%SystemRoot%\Microsoft.NET\Framework64\v4.0.30319\csc.exe`).
   No SDK and no download.
3. **Writes the config** `open-in-nvim.ini` there, from the template in the repository
   root. An existing one is kept — it is yours — unless you pass `-Force`.
4. **Registers the entries** `Open_in_Neovim_new` and `Open_in_Neovim_current` for
   files, folders and the folder background — six keys, listed in
   [BINDINGS.md](BINDINGS.md) — after removing the entries of earlier versions of this
   tool, so a menu never shows duplicates.
5. **Writes a manifest** `install.manifest.txt` naming the exe and the ini, for the
   uninstaller.
6. **Leaves file associations alone.**

Run it again any time (after a `git pull`, say): it is safe to repeat and rebuilds the
exe.

`-DryRun` prints every step and changes nothing:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\install.ps1 -DryRun
```

## In place (development)

To run the menu from your clone:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\install.ps1 -InstallDir $PWD.Path
```

The exe and its `open-in-nvim.ini` go to `<repo>\bin` (git-ignored) and the entries
point there. After editing the sources run `build.ps1` (or `install.ps1` again); the
next click runs the new build.

## Removing it

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\uninstall.ps1 -RemoveFiles
```

- Without `-RemoveFiles` only registry entries go: the six context-menu entries and, if you
  ran `register-nvim-default-app.ps1` / `install-icons-for-progids.ps1`, the `Neovim.TextFile`
  (`.New`, `.Current`) default-app registrations. Nothing else in the registry is touched.
- With it, the files listed in the install folder's `install.manifest.txt` are deleted —
  exactly those, never a recursive delete — and the folder itself if it ends up empty.
- Your config is kept unless you add `-RemoveConfig`.
- A folder that is a repository is never touched. An in-place install writes no
  manifest; delete `<repo>\bin` yourself.

Both scripts take `-DryRun` and `-InstallDir`. If you registered Neovim as a default
application ([FEATURES/DEFAULT-APPS.md](FEATURES/DEFAULT-APPS.md)), that registration
points at the same exe: leave out `-RemoveFiles`, or the double-click stops working.

## Coming from the VBS and PowerShell version

Earlier versions installed two `.vbs` wrappers and three PowerShell scripts, and the
entries ran `wscript.exe`. Run `install.ps1` once:

- the six entries are rewritten to run `OpenInNvim.exe`;
- an `open-in-nvim.config.ps1` in the install folder is converted to `open-in-nvim.ini`
  (its values carry over; not with `-Force`, which writes a fresh ini);
- the old files in the install folder are deleted.

Older still: entries that pointed at a junction `C:\tools\OpenInNvim`. `install.ps1`
replaces those too. The junction is no longer needed — remove **the link only, never
its contents** (`Remove-Item -Recurse` on a junction can empty the target folder in
Windows PowerShell 5.1):

```powershell
[IO.Directory]::Delete('C:\tools\OpenInNvim', $false)
```

## Default-app registration (optional)

Registering Neovim as the *default application* for many file types is a separate
script. It is not needed for the context menu — see
[FEATURES/DEFAULT-APPS.md](FEATURES/DEFAULT-APPS.md).
