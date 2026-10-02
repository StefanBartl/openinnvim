# Installation

Two steps: make the repository reachable at the path the context-menu entries use,
then register the entries. Nothing is installed system-wide and no administrator
rights are needed — everything lives under `HKCU`.

## 1. Put the files at `C:\tools\OpenInNvim`

The small VBS wrappers call `C:\tools\OpenInNvim\open-in-nvim[-current].ps1`. Clone
the repository anywhere you like and point a junction at it:

```powershell
git clone https://github.com/StefanBartl/openinnvim.git E:\repos\openinnvim
New-Item -ItemType Directory -Force C:\tools | Out-Null
New-Item -ItemType Junction -Path C:\tools\OpenInNvim -Target E:\repos\openinnvim
```

A junction needs neither administrator rights nor developer mode (a symbolic link
does). The `.ps1` files find each other relative to themselves, so the repository
can sit on any drive.

Check that it resolves:

```powershell
Test-Path C:\tools\OpenInNvim\open-in-nvim-current.ps1   # True
```

## 2. Register the six entries

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File C:\tools\OpenInNvim\install-context.ps1
```

It first removes older entries of this tool (several earlier names, under `HKCU` and
`HKLM`; failing to touch `HKLM` without administrator rights is only a warning), then
writes `Open_in_Neovim_new` and `Open_in_Neovim_current` for files, folders and the
folder background — six keys, listed in [BINDINGS.md](BINDINGS.md).

On Windows 11 the entries appear under **Show more options** (the classic menu).

Set the path of `nvim.exe` and, if you use one, of WezTerm in
`open-in-nvim.config.ps1` — see [configuration.md](configuration.md).

## 3. Try it

[quickstart.md](quickstart.md). `verify.ps1` runs both chains end to end, but it
opens real windows and sends files to a running session, so it is not part of the
automated tests.

## Removing it

Delete the six keys (note `-LiteralPath`: `*` is a real key name here, not a wildcard):

```powershell
foreach ($kind in 'new', 'current') {
  foreach ($base in '*', 'Directory', 'Directory\Background') {
    Remove-Item -LiteralPath "HKCU:\Software\Classes\$base\shell\Open_in_Neovim_$kind" -Recurse -ErrorAction SilentlyContinue
  }
}
```

Then remove the junction — **the link only, never its contents**. `Remove-Item -Recurse`
on a junction can empty the target folder in Windows PowerShell 5.1:

```powershell
[IO.Directory]::Delete('C:\tools\OpenInNvim', $false)
```

## Default-app registration (optional)

Registering Neovim as the *default application* for many file types is a separate,
heavier path with two exe launchers. It is not needed for the context menu — see
[FEATURES/DEFAULT-APPS.md](FEATURES/DEFAULT-APPS.md).
