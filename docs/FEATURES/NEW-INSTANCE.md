# New instance

`open-in-nvim.ps1`, started by `open-in-nvim.vbs`. Always starts a Neovim of its own;
it never looks at running ones.

## What it starts

| Clicked | Working directory | Neovim receives |
| --- | --- | --- |
| a file | the file's folder | `-- <file>` |
| a folder | that folder | nothing |
| a folder background | that folder | nothing |
| a path that does not exist | its parent, if that exists | `-- <path>`, so a new file is created |

The `--` before the file makes Neovim treat the path as a file even if it looks like an
option. A path given as `%NAME%` is expanded as an environment variable only when the
path as typed does not exist.

## The terminal

Tried in this order, the first that exists wins:

1. **WezTerm** — `WEZTERM_BIN`, or `wezterm` from `PATH`: `wezterm start --cwd <dir> -- nvim ...`
2. **Windows Terminal** — `wt -w 0 nt -d <dir> -- nvim ...`, a new tab in the current window
3. **`cmd.exe`** — `cmd /c start "" /D <dir> nvim ...`, a console of its own

The terminal is started detached and the hidden PowerShell exits at once; it does not
wait until the terminal is closed. Every argument is quoted for the Windows command
line, so folders with spaces and a drive root (`C:\`) survive.

## See the command without running it

```powershell
$env:OPEN_IN_NVIM_SPAWN_DRYRUN = '1'
powershell -NoProfile -ExecutionPolicy Bypass -File C:\tools\OpenInNvim\open-in-nvim.ps1 "$env:USERPROFILE\Desktop\test.txt"
```

prints one line starting with `spawn:`.
