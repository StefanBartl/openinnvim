# New instance

`OpenInNvim.exe new <path>`. Always starts a Neovim of its own; it never looks at
running ones. The same code starts the instance for "current instance" when none is
usable.

## What it starts

| Clicked | Working directory | Neovim receives |
| --- | --- | --- |
| a file | the file's folder | `-- <file>` |
| a folder | that folder | nothing |
| a folder background | that folder | nothing |
| a path that does not exist | its parent, if that exists | `-- <path>`, so a new buffer of that name opens |

The `--` before the file makes Neovim treat the path as a file even if it looks like an
option. The path is used literally; `%NAME%` in it is not expanded.

## The terminal

Neovim is a console program and needs a terminal. `TERMINAL` in `open-in-nvim.ini`
chooses it:

| `TERMINAL` | Tried, in this order |
| --- | --- |
| `auto` (default) | WezTerm, Windows Terminal, console |
| `wezterm` | WezTerm, console |
| `wt` | Windows Terminal, console |
| `console` | console |

1. **WezTerm** — `WEZTERM_BIN`, else `wezterm-gui.exe` or `wezterm.exe` from `PATH`:
   `wezterm-gui start --cwd <dir> -- <nvim> [-- <file>]`
2. **Windows Terminal** — `wt.exe` from `PATH`:
   `wt -w 0 nt -d <dir> -- <nvim> [-- <file>]`, a new tab in the current window
3. **Console** — `nvim.exe` started directly with `<dir>` as working directory; it gets
   a console window of its own

A terminal that is not installed is left out, and one that fails to start falls through
to the next, so the console is always the last resort. `cmd.exe` is not used anywhere:
it expands `%VAR%` inside quoted arguments and refuses a UNC working directory.

Every argument is quoted for the Windows command line, so folders with spaces and a
drive root (`C:\`) survive; for Windows Terminal a `;` in a name is written `\;`. The
launcher exits as soon as the terminal has been started.

If `nvim.exe` is found neither at `NVIM_BIN` nor on `PATH`, a box says so and the exit
code is 1.

## See the command without running it

```powershell
$env:OPEN_IN_NVIM_SPAWN_DRYRUN = '1'
& "$env:LOCALAPPDATA\OpenInNvim\OpenInNvim.exe" new "$env:USERPROFILE\Desktop\test.txt" | Out-String
```

prints the Neovim command, the working directory, and one line per terminal that would
be tried:

```
spawn: C:\Program Files\Neovim\bin\nvim.exe "--" "C:\Users\<USER>\Desktop\test.txt"
spawn-cwd: C:\Users\<USER>\Desktop
spawn-via: wezterm C:\Program Files\WezTerm\wezterm-gui.exe "start" "--cwd" ...
spawn-via: console C:\Program Files\Neovim\bin\nvim.exe "--" ...
```
