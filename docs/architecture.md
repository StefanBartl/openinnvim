# Why it does it that way

## The chain

```
Explorer click
  -> wscript.exe  open-in-nvim[-current].vbs      (hidden: no console window)
  -> powershell.exe -NoProfile ... -File open-in-nvim[-current].ps1   (found next to the VBS)
  -> Neovim (RPC over a named pipe)  or  a new terminal running nvim.exe
```

The VBS exists only because `powershell.exe` started from a context-menu entry
flashes a console window; `WScript.Shell.Run` with window style 0 does not. Both
`.ps1` files dot-source `open-in-nvim.lib.ps1` (instance discovery, the RPC client,
command-line quoting, detached spawn) and read `open-in-nvim.config.ps1`.

The VBS asks `WScript.ScriptFullName` where it lives and starts the `.ps1` from the same
folder, so nothing is hard-coded: an installed copy, a clone used in place and an
earlier junction all work. It quotes every argument itself (an argument with a space, a
quote or a trailing backslash would otherwise swallow its closing quote).

## Installation

`install.ps1` copies the five launcher files, writes the config with the detected
`nvim.exe`, and writes six registry keys through the .NET registry API (`*` is a real key
name, so there is no PowerShell path wildcarding to trip over). A manifest in the install
folder lists what was copied, so `uninstall.ps1 -RemoveFiles` deletes exactly that and
never recurses. The registry root is a parameter (`-ClassesKey`), which is how the test
suite exercises the whole install and uninstall against a throw-away key.

## Neovim is its own server

Every Neovim instance listens on an RPC pipe without any configuration. On Windows its
name is `\\.\pipe\nvim.<pid>.<n>`, where `<pid>` is the process id of the editor
core. A TUI session is two processes — the visible `nvim.exe` (the UI client, which
owns **no** pipe) and its child `nvim.exe --embed` (the editor core, which does) — so
the launcher looks for pipes, not for the window's process id. GUIs such as Neovide
start `--embed` as well.

A client connects to that pipe and sends MessagePack-RPC requests: `nvim_eval`,
`nvim_exec_lua`, `nvim_command`. Neovim's own `--remote` is exactly that: it
translates to `nvim_command("drop <file>")` over the same channel. openinnvim speaks
the protocol directly, with a small client written in PowerShell, instead of starting
a second `nvim.exe` just to do it.

### Which instances count

Plugin jobs and helpers have pipes too — a `--headless` job, a `-l` script, a
plugin's `--embed --headless` child. What separates them from an editor a person sits
in front of is a **UI**: `len(nvim_list_uis())` is at least 1 for a TUI core or a GUI
and 0 for the helpers. Asking the instance is cheaper than reading command lines
through WMI (about 200 ms) and more accurate than pattern-matching them.

Only instances of the launcher's own Windows session are considered, so a click never
sends a file into another logged-in user's editor.

### Order

1. `NVIM_SERVER`, if set.
2. The stable name `\\.\pipe\nvim-%USERNAME%`, if a session owns it
   (`PREFER_STABLE_PIPE`).
3. Every instance with a UI, ordered by `INSTANCE_PICK`.
4. With nothing at all to try, the stable name, so that an instance started with
   `--listen` on it is still found.

## Paths are parameters, not text

A file name goes into a single `nvim_exec_lua` call as an argument of a fixed Lua
snippet:

```lua
local f = ...
vim.cmd("silent drop " .. vim.fn.fnameescape(f))
```

Nothing is spliced into command text, so `#`, `%`, `[`, `(`, quotes and `&` need no
treatment — the same reason `:Filetree open` is called with `vim.cmd.Filetree({ args =
{ "open", dir } })`. An earlier version built `:Filetree open <fnameescape(dir)>` as
text, which silently failed for folders with `#` or `%` in the name.

The snippets run `:silent`. `:cd` echoes the new directory; a path wider than the
window raises a hit-enter prompt and leaves the instance waiting for a key, deaf to
further RPC.

### A pipe that is not there

`NamedPipeClientStream.Connect` waits for its whole timeout for a pipe that does not
exist, so the RPC client first looks the name up in the pipe namespace (milliseconds) and
gives up at once. A configured `NVIM_SERVER` nobody listens on therefore costs nothing
extra before a new instance is started (measured: 3.4 s before, 0.4 s after, including
the PowerShell start).

## Raising the window

`FOCUS_TERMINAL` (off by default) walks the process tree upward from the editor core —
core, UI client, shell, terminal host — to the first process that owns a window, then
raises it. Windows only lets the foreground process hand the foreground over, so the call
attaches this thread's input to the foreground window's thread for a moment. The walk is a
pure function over a parent map, which is what the tests cover; the Win32 call needs a
real window and is checked by hand.

## Command-line fallback

Only for addresses the RPC client cannot use (a TCP `NVIM_SERVER`; for a pipe the command
line could not do better than RPC, only slower): `nvim --server
<addr> --remote <file>` for files, `--remote-send` with a `:cd | :edit .` command for
folders. Every call runs with a time limit and kills only its own process tree, because
the launcher runs hidden and a hang would never be seen. In `--remote-send` text a
literal `<` is sent as `<lt>` so a file name cannot be read as key notation.

## Starting a new instance

When nothing took the target, `open-in-nvim-current.ps1` starts Neovim in a terminal
with `--listen \\.\pipe\nvim-%USERNAME%` (omitted when that name is already taken, or
the new instance would fail to listen) and the file after `--`. The terminal command is
built by `Invoke-Spawn`, which quotes every argument with the rules
`CommandLineToArgvW` uses — `Start-Process -ArgumentList` joins an array with plain
spaces, so `C:\My Dir` would arrive as two arguments.

## Windows PowerShell 5.1 traps

The launchers are written for 5.1, the version every Windows has. Four things there
fail silently or confusingly, and each cost a real bug:

- A function parameter named `$args` **does not bind**; the automatic variable stays
  empty. The first version started a new Neovim without the file for this reason.
  The parameters are called `$launchArgs` / `$nvimArgs`.
- `Start-Process -ArgumentList` rejects an empty-string element, and joins the rest
  with plain spaces.
- Output written with `Write-Output` inside a function used in an `if (...)` becomes
  that function's return value; diagnostics use `[Console]::Out.WriteLine`.
- `"... $key: ..."` is a parse error; write `${key}:`.

Parsing under PowerShell 7 proves nothing about 5.1: the test suite runs under
`powershell.exe`.

## Safety nets for tests

`OPEN_IN_NVIM_ONLY_PIDS` restricts discovery to a PID list *and* switches off the
per-user pipe name, because that name is not PID based and could reach a real
session. `OPEN_IN_NVIM_NO_SPAWN` makes a missing instance an exit code instead of a
window. The tests start their own `nvim --embed` instances and only ever stop
processes that started during the run.

## Why the library is required

Both launchers need the same quoting and spawn helpers, and the current-instance one
the RPC client. An earlier version treated the lib as optional; the "without" path was
never exercised, so there is one path now.
