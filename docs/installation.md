# Installation

One script. It copies the launcher files to a folder of your own, finds `nvim.exe`, and
registers the six context-menu entries. Nothing is installed system-wide and no
administrator rights are needed — everything lives under `HKCU` and `%LOCALAPPDATA%`.

```powershell
git clone https://github.com/StefanBartl/openinnvim.git
cd openinnvim
powershell -NoProfile -ExecutionPolicy Bypass -File .\install.ps1
```

That is all. On Windows 11 the entries appear under **Show more options** (the classic
menu); try them with [quickstart.md](quickstart.md).

## What `install.ps1` does

1. **Finds Neovim**: `nvim.exe` on `PATH`, then the official installer, winget and scoop
   locations. The result is written into the new config as `NVIM_BIN` and used as the
   menu icon. `-NvimExe <path>` overrides it.
2. **Copies** `open-in-nvim.vbs`, `open-in-nvim-current.vbs`, `open-in-nvim.ps1`,
   `open-in-nvim-current.ps1` and `open-in-nvim.lib.ps1` to
   `%LOCALAPPDATA%\OpenInNvim` (`-InstallDir <folder>` for another place). The VBS
   wrappers find the `.ps1` files next to themselves, so the folder can be anywhere.
3. **Writes the config** `open-in-nvim.config.ps1` there. An existing one is kept — it
   is yours — unless you pass `-Force`.
4. **Registers the entries** `Open_in_Neovim_new` and `Open_in_Neovim_current` for
   files, folders and the folder background — six keys, listed in
   [BINDINGS.md](BINDINGS.md) — after removing the entries of earlier versions of this
   tool, so a menu never shows duplicates.
5. **Leaves file associations alone.**

Run it again any time (after a `git pull`, say): it is safe to repeat and refreshes the
copied files.

`-DryRun` prints every step and changes nothing:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\install.ps1 -DryRun
```

## In place (development)

To run the menu straight from your clone, so that what you edit is what a click runs:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\install.ps1 -InstallDir $PWD.Path
```

Nothing is copied and the repository's own config is not touched; set `NVIM_BIN` there
yourself if `nvim.exe` is not at the default path.

## Removing it

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\uninstall.ps1 -RemoveFiles
```

- Without `-RemoveFiles` only the six registry entries go.
- With it, the files listed in the install folder's `install.manifest.txt` are deleted —
  exactly those, never a recursive delete — and the folder itself if it ends up empty.
- Your config is kept unless you add `-RemoveConfig`.
- A folder that is a repository (`-InstallDir` pointing at your clone) is never touched.

Both scripts take `-DryRun`. If you also used the default-app registration
([FEATURES/DEFAULT-APPS.md](FEATURES/DEFAULT-APPS.md)) in the same folder, its exe
launchers need the VBS files there: leave out `-RemoveFiles`.

## Coming from the old setup

Earlier versions pointed the entries at a junction `C:\tools\OpenInNvim` and registered
them with `install-context.ps1` or the `.reg` files. Run `install.ps1` once; it replaces
those entries. The junction is no longer needed — remove **the link only, never its
contents** (`Remove-Item -Recurse` on a junction can empty the target folder in Windows
PowerShell 5.1):

```powershell
[IO.Directory]::Delete('C:\tools\OpenInNvim', $false)
```

## Default-app registration (optional)

Registering Neovim as the *default application* for many file types is a separate,
heavier path with two exe launchers. It is not needed for the context menu — see
[FEATURES/DEFAULT-APPS.md](FEATURES/DEFAULT-APPS.md).
