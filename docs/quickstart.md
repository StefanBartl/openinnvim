# Quickstart

After [installing](installation.md) (one script), with Neovim running, right-click a file in Explorer, choose **Show more options**
(Windows 11), then **Open with Neovim (current instance)**. The file appears in the
session you were working in — no new window.

Right-click a folder instead and, if that session has
[filetree.nvim](https://github.com/StefanBartl/filetree.nvim), its tree opens on the
folder; otherwise the folder becomes the working directory with a directory view.

**Open with Neovim (new instance)** always starts a fresh Neovim in a new terminal.

## See what the launcher would do, without opening anything

`OpenInNvim.exe` has no console, so pipe its output:

```powershell
$env:OPEN_IN_NVIM_DRYRUN = '1'
& "$env:LOCALAPPDATA\OpenInNvim\OpenInNvim.exe" current "$env:USERPROFILE\Desktop\test.txt" | Out-String
```

It prints the target and the instances it would try, in order:

```
mode: current
target: file C:\Users\<USER>\Desktop\test.txt
cwd: C:\Users\<USER>\Desktop
candidate: \\.\pipe\nvim.52328.0 pid=52328
candidate: \\.\pipe\nvim.41200.0 pid=41200
```

No candidate means the next click starts a new instance; to see that command instead of
running it:

```powershell
$env:OPEN_IN_NVIM_DRYRUN = $null
$env:OPEN_IN_NVIM_SPAWN_DRYRUN = '1'
& "$env:LOCALAPPDATA\OpenInNvim\OpenInNvim.exe" new "$env:USERPROFILE\Desktop\test.txt" | Out-String
```

Remove both variables again afterwards (`$env:OPEN_IN_NVIM_SPAWN_DRYRUN = $null`).

Every switch is listed in [configuration.md](configuration.md#environment-switches). If
a click does nothing, start with [troubleshooting.md](troubleshooting.md).
