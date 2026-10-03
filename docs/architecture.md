# Why it does it that way

## One program

```
Explorer click
  -> "<dir>\OpenInNvim.exe" current|new "<path>"
  -> Neovim (RPC over a named pipe)  or  a terminal running nvim.exe
```

`OpenInNvim.exe` is a windowed program (no console, so nothing flashes), written in C# 5
against .NET Framework 4.x and compiled from `src\*.cs` by `build.ps1` with the `csc.exe`
that ships with Windows. No SDK, no packages.

Earlier versions went Explorer → `wscript.exe` → a VBS wrapper → Windows PowerShell 5.1.
Starting PowerShell was most of the cost of a click: about 540 ms for the script alone
and 642 ms through `wscript`, against about 53 ms for the compiled program (one machine,
`--clean` instances, file opened in the newest of two). The number depends on the machine;
the ratio is the point.

The sources are split by concern:

| File | Holds |
| --- | --- |
| `Program.cs` | entry point, the two modes, exit codes, the environment switches |
| `CommandLine.cs` | reading the raw command line, quoting arguments, the `PATH` lookup |
| `Config.cs` | `open-in-nvim.ini` |
| `Target.cs` | what was clicked: file, folder, or a path that does not exist yet |
| `Pipes.cs` | listing pipes, connecting, the trust check |
| `Discovery.cs` | the candidates, their order, the usability probe |
| `MsgPack.cs`, `Rpc.cs` | the MessagePack-RPC client, over a pipe or TCP |
| `Opener.cs` | the Lua that opens the file or folder, and what the answer means |
| `Spawner.cs` | starting a new instance in a terminal |
| `Chooser.cs` | the instance list for `INSTANCE_PICK = ask`, and the error box |
| `Focus.cs` | `FOCUS_TERMINAL` |
| `Log.cs`, `Native.cs` | the decision log; the Win32 calls |

## The path comes from the raw command line

Explorer writes `"C:\"` for a drive root, and the usual argument rules read that
backslash as an escape for the closing quote. A file name cannot contain a double quote,
so the launcher takes everything after the mode from the raw command line and removes
the quotes. The path is then used literally — no `%VAR%` expansion (`%TEMP%x` is a legal
folder name), no wildcards.

## Neovim is its own server

Every Neovim instance listens on an RPC pipe without any configuration. On Windows its
name is `\\.\pipe\nvim.<pid>.<n>`, where `<pid>` is the process id of the editor
core. A TUI session is two processes — the visible `nvim.exe` (the UI client, which
owns **no** pipe) and its child `nvim.exe --embed` (the editor core, which does) — so
the launcher looks for pipes, not for the window's process id. GUIs such as Neovide
start `--embed` as well.

Neovim's own `--remote` uses the same channel. openinnvim speaks the protocol directly
instead of starting a second `nvim.exe` to do it; `nvim --server ... --remote` is never
used.

## Trust: who serves a pipe

The pipe namespace is global on the machine and any local process can create any free
name, so a name proves nothing. After connecting, and before a single byte is written,
the launcher asks Windows which process serves the pipe and accepts it only if

- its image is `nvim.exe`,
- it runs in the launcher's logon session,
- it runs as the launcher's user (a token that cannot be read is not trusted), and
- for a `nvim.<pid>.<n>` name, it is the process the name claims.

The same check applies to the stable pipe and to a pipe `NVIM_SERVER`. A squatted name
never receives a path. Two consequences: a Neovim binary under another name is not
found, and a TCP `NVIM_SERVER` cannot be checked at all — nobody can tell who listens on
a port — so TCP is used only for an address written into the config.

## Which instances count

Plugin jobs and helpers have pipes too — a `--headless` job, a `-l` script, a
plugin's `--embed --headless` child. An instance is usable when, on one connection:

1. `nvim_get_mode` reports that it is not blocking. This call is answered even at a
   hit-enter prompt, so an instance waiting for a key is recognised at once and skipped
   instead of running into a timeout.
2. `len(nvim_list_uis())` is at least 1: a TUI core or a GUI, not a helper.

An instance that does not answer within 300 ms is skipped.

## Order

1. `NVIM_SERVER`, if set.
2. The instance that serves `\\.\pipe\nvim-%USERNAME%` (`PREFER_STABLE_PIPE`).
3. Every other instance with a default pipe, by process start time (`INSTANCE_PICK`).

A named pipe only moves its verified owner to the front; if that process has no default
pipe (started with `--listen`), the named pipe is its address. Probing is lazy: the first
usable instance gets the target and the others are never contacted. `ask` probes all of
them, because the list must be complete.

## Paths are parameters, not text

The target goes into one `nvim_exec_lua` call as an argument of a fixed Lua snippet. For
a file that snippet uses `bufadd(path)`, which takes the name verbatim; the only Ex
commands it runs carry a buffer *number*. There is no Ex file argument anywhere.

That matters because `:edit` and `:drop` expand `$NAME` and treat `[...]` as a wildcard
even after `fnameescape()`, which opens a different file than the one clicked. With
`bufadd`, names containing `%`, `$`, `[ ]`, `#`, quotes, spaces or Unicode open as the
same file. `:Filetree open` gets the folder as an argument table for the same reason.

Where the file goes: a window that already shows it (any tabpage) wins. Otherwise the
current window, if its buffer may be replaced there — not floating, an ordinary buffer,
no `winfixbuf` — else the first such window of the tabpage, else a new split. A window
whose unsaved buffer would have to be abandoned gets a split as well. If the instance is
in Insert, Visual, Command-line or Terminal mode, it is returned to Normal mode first.

## A slow open is not a refusal

Once the request has been written to an instance, the target is never sent to another
one unless that instance answers with an error or closes the connection. The launcher
waits, hidden, up to 15 seconds for the answer; without one it exits with code 0,
because the instance has the request (a large file, an LSP start, a swap-file dialog).
Giving up early and trying the next instance opened the file twice; closing the
connection early dropped the queued request.

For the same reason only a failure *before* the instance has taken the target counts as
an error: an autocommand that fails after the buffer is on screen does not send the file
to a second instance.

## Starting a new instance

Neovim is a console program, so it needs a terminal: WezTerm, Windows Terminal, or a
console of its own (`nvim.exe` started directly by the window-less launcher gets one).
`cmd.exe` is never involved: it expands `%VAR%` inside quoted arguments and refuses a
UNC working directory. Every argument is quoted by the rules `CommandLineToArgvW` uses,
the file follows `--` so a name starting with `-` is not read as an option, and for
Windows Terminal a `;` is written `\;` (its command separator).

A new instance gets no `--listen`: it has its default pipe and the next click finds it.
The one exception is a pipe `NVIM_SERVER` nobody serves yet. Programs are looked up on
`PATH` only, never in the working directory, which is whatever folder was clicked.

## Installation

`install.ps1` runs `build.ps1`, writes the ini with the detected `nvim.exe`, and writes
six registry keys through the .NET registry API (`*` is a real key name, so there is no
PowerShell path wildcarding to trip over). The commands name the exe by its absolute,
quoted path. A manifest in the install folder lists what was put there, so
`uninstall.ps1 -RemoveFiles` deletes exactly that and never recurses. The registry root
is a parameter (`-ClassesKey`), which is how the test suite exercises install and
uninstall against a throw-away key.

## Raising the window

`FOCUS_TERMINAL` (off by default) walks the process tree upward from the editor core —
core, UI client, shell, terminal host — to the first process that owns a visible, titled
top-level window, and raises it. Windows keeps a parent id after the parent exits and
reuses ids, so a "parent" younger than its child ends the walk. The launcher was started
by the user's click, which is what allows it to hand the foreground on. Several windows
of one terminal process cannot be told apart.

## Safety nets for tests

`OPEN_IN_NVIM_ONLY_PIDS` restricts every contact to a PID list, including through the
stable pipe and a pipe `NVIM_SERVER`; a TCP address is refused in that mode unless
`OPEN_IN_NVIM_ALLOW_TCP` is set. `OPEN_IN_NVIM_NO_SPAWN` makes a missing instance an
exit code instead of a window, `OPEN_IN_NVIM_NO_UI` suppresses the two windows the
program can show. The tests start their own `nvim --embed` instances, fake the
`USERNAME`, and only ever stop processes they started.
