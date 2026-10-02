# Quickstart

With Neovim running, right-click a file in Explorer, choose **Show more options**
(Windows 11), then **Open with Neovim (current instance)**. The file appears in the
session you were working in — no new window.

Right-click a folder instead and, if that session has
[filetree.nvim](https://github.com/StefanBartl/filetree.nvim), its tree opens on the
folder; otherwise the folder becomes the working directory with a directory view.

**Open with Neovim (new instance)** always starts a fresh Neovim in a new terminal.

## See what the launcher would do, without opening anything

```powershell
$env:OPEN_IN_NVIM_DRYRUN = '1'
powershell -NoProfile -ExecutionPolicy Bypass -File $env:LOCALAPPDATA\OpenInNvim\open-in-nvim-current.ps1 "$env:USERPROFILE\Desktop\test.txt"
```

It prints the instances it would try, in order:

```
candidate: \\.\pipe\nvim-<USER>
candidate: \\.\pipe\nvim.52328.0
```

No candidate and no running Neovim means the next click starts a new instance; to
see that command instead of running it:

```powershell
$env:OPEN_IN_NVIM_SPAWN_DRYRUN = '1'
```

Every switch is listed in [BINDINGS.md](BINDINGS.md#diagnostic-switches). If a click
does nothing, start with [troubleshooting.md](troubleshooting.md).
