# Configuration

One file: `open-in-nvim.ini`, next to `OpenInNvim.exe`, shared by both entries. Every
key is optional and a missing file means defaults. The template in the repository root
lists every key:

```ini
NVIM_BIN = C:\Program Files\Neovim\bin\nvim.exe
TERMINAL = auto
# WEZTERM_BIN = C:\Program Files\WezTerm\wezterm-gui.exe
# NVIM_SERVER =
PREFER_STABLE_PIPE = true
INSTANCE_PICK = newest
FOLDER_OPENS_IN = filetree
FOCUS_TERMINAL = false
```

## Format

- `KEY = value`, one per line. Keys and the fixed choices are not case sensitive.
- A line starting with `#` or `;` is a comment. There are no trailing comments: the
  value runs to the end of the line, because `#` and `;` are legal in paths.
- One pair of surrounding quotes is removed; `%VAR%` in a value is expanded.
- Booleans: `true`, `false`, `1`, `0`, `yes`, `no`, `on`, `off`.
- Save the file as UTF-8. A file in the ANSI code page is read as such.
- A value that is not valid falls back to the default and an unknown key is ignored;
  neither stops a click. Both are noted in the [log](#environment-switches).

## Keys

| Key | Default | Used by | Meaning |
| --- | --- | --- | --- |
| `NVIM_BIN` | `nvim` (looked up on `PATH`) | both | Path of `nvim.exe`. If the file does not exist, `nvim` from `PATH` is used. `install.ps1` writes the path it found. |
| `TERMINAL` | `auto` | both | Where a new instance is shown: `auto`, `wezterm`, `wt` or `console`. |
| `WEZTERM_BIN` | empty | both | Full path of `wezterm-gui.exe` when it is not on `PATH`. A bare name is looked up on `PATH`; a relative path is ignored (the clicked folder is never searched). |
| `NVIM_SERVER` | empty | current | A fixed server tried first: a pipe name or `host:port`. Empty: running instances are found automatically. |
| `PREFER_STABLE_PIPE` | `true` | current | The instance that serves `\\.\pipe\nvim-%USERNAME%` goes first. |
| `INSTANCE_PICK` | `newest` | current | Which running instance goes first: `newest`, `oldest` or `ask`. |
| `FOLDER_OPENS_IN` | `filetree` | current | What a folder does: `filetree` or `edit`. |
| `FOCUS_TERMINAL` | `false` | current | Bring the window that hosts the instance to the front. |

## `TERMINAL`

Neovim is a console program, so a new instance needs a terminal.

- `auto` — WezTerm, then Windows Terminal, then a plain console.
- `wezterm` — `WEZTERM_BIN` if that file exists, otherwise `wezterm-gui.exe`, then
  `wezterm.exe`, from `PATH`.
- `wt` — `wt.exe` from `PATH`.
- `console` — `nvim.exe` started directly; it gets a console window of its own.

A named terminal that is not installed, or cannot be started, falls back to the console,
so a click never does nothing. `cmd.exe` is never involved. The exact commands:
[FEATURES/NEW-INSTANCE.md](FEATURES/NEW-INSTANCE.md).

## `NVIM_SERVER`

- A pipe: the full name (`\\.\pipe\mynvim`) or the bare name (`mynvim`). The process
  that serves it is checked like any other ([architecture.md](architecture.md#trust-who-serves-a-pipe))
  and that instance goes first. If nobody serves the name and a new instance has to be
  started, it is started with `--listen <that name>`.
- A TCP address: `127.0.0.1:6666`, `[::1]:6666`, `host:6666`. It is tried first, over
  the same RPC client. Nobody can tell which process listens on a port, so a TCP server
  **cannot be verified**; it is used only because you wrote it here.

An address nobody answers costs at most the connect limit (300 ms) before the launcher
goes on to the running instances.

## `PREFER_STABLE_PIPE`

If your `init.lua` calls `vim.fn.serverstart([[\\.\pipe\nvim-<USER>]])`, that session
owns a predictable name. With several sessions open, only the first can claim it —
that one is "the main instance", and with this key on, clicks go there regardless of
which session started last. The name alone proves nothing: the process serving it must
pass the same check as every other instance. Set `false` to ignore the name and treat
all running instances alike.

## `INSTANCE_PICK`

When more than one instance is running (after `NVIM_SERVER` and the stable pipe, if any):

- `newest` — the one started last.
- `oldest` — the one running longest.
- `ask` — a small list showing each instance's working directory, current file and
  process id; Enter or double-click picks, Escape cancels without opening anything. With
  only one usable instance there is nothing to ask. The pick wins over `NVIM_SERVER` and
  the stable pipe.

Which instances count: [FEATURES/CURRENT-INSTANCE.md](FEATURES/CURRENT-INSTANCE.md#finding-the-instance).

## `FOLDER_OPENS_IN`

- `filetree` — `:Filetree open <folder>` when the instance has that command,
  otherwise the same as `edit`.
- `edit` — always make the folder the working directory and open a directory view.

Details: [FEATURES/FOLDERS.md](FEATURES/FOLDERS.md).

## `FOCUS_TERMINAL`

Off by default. After a click the editor may open its file behind whatever you were
looking at. With `true` the launcher looks up which window hosts the instance — it walks
up the process tree from the editor to the first process that owns a visible window
(WezTerm, Windows Terminal, a GUI such as Neovide) — and asks Windows to raise it,
restoring it first if it is minimized.

Best effort: one WezTerm or Windows Terminal process can host several windows and they
cannot be told apart, so with several terminal windows open the raised one may not be
the instance's own. Any failure is silent and the file is opened regardless. An instance
reached over TCP has no known process, so its window is never raised.

## Config location

Next to the exe: `%LOCALAPPDATA%\OpenInNvim\open-in-nvim.ini` for an installed copy,
`<repo>\bin\open-in-nvim.ini` for an in-place install
([installation.md](installation.md)). `install.ps1` never overwrites an existing ini
unless you pass `-Force`.

## Environment switches

Set in the environment of the launcher. They exist for tests and diagnosis and change
nothing for normal clicks. A switch is on when its value is not empty and not `0`.

| Variable | Effect |
| --- | --- |
| `OPEN_IN_NVIM_DRYRUN=1` | print the mode, the target, the working directory and (for `current`) one `candidate: <address> pid=<n>` line per usable instance, in order; open nothing |
| `OPEN_IN_NVIM_SPAWN_DRYRUN=1` | print the command that would start a new instance (`spawn:`, `spawn-cwd:`, one `spawn-via:` per terminal that would be tried); start nothing |
| `OPEN_IN_NVIM_NO_SPAWN=1` | never start anything; when nothing is usable print `no reachable instance` and exit with code 3 |
| `OPEN_IN_NVIM_ONLY_PIDS=<pid,pid>` | contact only these processes, also through the stable pipe or a pipe `NVIM_SERVER`. Set but without a valid PID means "nothing" |
| `OPEN_IN_NVIM_ALLOW_TCP=1` | allow a TCP `NVIM_SERVER` although `OPEN_IN_NVIM_ONLY_PIDS` is set (a port has no PID) |
| `OPEN_IN_NVIM_NO_UI=1` | no windows: no error box, and `INSTANCE_PICK = ask` takes the first entry |
| `OPEN_IN_NVIM_PICK=<n>` | the chooser returns entry `n` (from 0) without showing a window; an index that does not exist cancels |
| `OPEN_IN_NVIM_LOG=<file>` | append the decision log to this file: one line per step, `<elapsed ms> <text>`, ending with the exit code |

The launcher has no console. To read its output in PowerShell, pipe it:

```powershell
$env:OPEN_IN_NVIM_DRYRUN = '1'
& "$env:LOCALAPPDATA\OpenInNvim\OpenInNvim.exe" current "$env:USERPROFILE\Desktop\test.txt" | Out-String
```

## Exit codes

| Code | Meaning |
| --- | --- |
| `0` | opened, handed over to an instance, new instance started, dry run printed, or the chooser was cancelled |
| `1` | usage error (the mode is not `current` or `new`), `open-in-nvim.ini` cannot be read, Neovim not found or not startable, or an unexpected error |
| `3` | nothing usable and `OPEN_IN_NVIM_NO_SPAWN` is set |
