# Current instance

`OpenInNvim.exe current <path>`. Hands the clicked file or folder to a Neovim that is
already running; only when none is usable does it start a new one.

## Finding the instance

Every Neovim opens a default pipe `\\.\pipe\nvim.<pid>.<n>`. The launcher lists the
pipes, keeps the ones of that form, and checks each process behind them.

**Trusted** — checked on the process that serves the pipe, before anything is written:
its image is `nvim.exe`, it runs in your logon session, it runs as your user, and it is
the process the pipe name claims. A pipe that merely has the right name gets nothing.

**Usable** — asked over the pipe: `nvim_get_mode` says the instance is not blocking
(not waiting at a hit-enter prompt or the like), and at least one UI is attached, which
separates an editor from `--headless` jobs, `-l` scripts and plugin helpers. An instance
that does not answer within 300 ms is skipped.

**Order:**

1. `NVIM_SERVER`, if set: a pipe name, or `host:port` over TCP.
2. The instance that serves the stable pipe `\\.\pipe\nvim-%USERNAME%`
   (`PREFER_STABLE_PIPE`, on by default).
3. The other instances by start time: `INSTANCE_PICK = newest` (default) or `oldest`.

The first usable instance in that order gets the target; the others are not contacted.
A named pipe (stable or `NVIM_SERVER`) is trusted like a default pipe and only moves its
owner to the front. A TCP address cannot be verified — see
[../configuration.md](../configuration.md#nvim_server).

`INSTANCE_PICK = ask` shows a list ("Open in Neovim - choose instance") with each usable
instance's working directory, current file and process id. Enter or a double-click
picks; Escape closes it without opening anything. It is only shown when more than one
instance is usable, and the pick wins over `NVIM_SERVER` and the stable pipe.

## Opening a file

One `nvim_exec_lua` call with the path as a parameter. Inside the instance the path goes
through `bufadd()`, which takes the name verbatim; there is no Ex file argument, so
nothing expands `$NAME`, `%` or `#` and nothing reads `[...]` as a wildcard. Names with
`%`, `$`, `[ ]`, `#`, quotes, spaces or Unicode open as the same file that was clicked.

- A window that already shows the file, in any tabpage, becomes current. No second
  buffer is created.
- Otherwise the file replaces the buffer of the current window, or of the first ordinary
  window of the tabpage when the current one is floating, a special buffer or has
  `winfixbuf`.
- A new split is used when there is no such window, or when the window's buffer has
  unsaved changes that would have to be abandoned.
- An instance in Insert, Visual, Command-line or Terminal mode is returned to Normal
  mode first.
- A path that does not exist yet becomes an empty buffer of that name; nothing is
  created on disk.

A folder: [FOLDERS.md](FOLDERS.md).

## Slow, refused, gone

- **Slow.** Once the request is written the launcher waits, hidden, up to 15 seconds for
  the answer. The target is never sent to a second instance meanwhile; without an
  answer the launcher exits with code 0, because the instance has the request and will
  open the file.
- **Refused.** The instance answers with an error before it took the target (an open
  command-line window, for one): the next instance in the order is tried.
- **Gone.** The connection closed without an answer: the next instance is tried.

## Raising the window

`FOCUS_TERMINAL = true` brings the window that hosts the instance to the front —
[../configuration.md](../configuration.md#focus_terminal). Off by default; several
windows of one terminal process cannot be told apart, so it can pick the wrong one.

## When nothing is usable

A new Neovim starts exactly as "new instance" would — [NEW-INSTANCE.md](NEW-INSTANCE.md).
It gets no `--listen`: its default pipe is what the next click finds. Only when
`NVIM_SERVER` is a pipe name nobody serves yet is the new instance started with
`--listen <that name>`.

## Limits

- A Neovim binary that is not named `nvim.exe` is not found.
- An instance waiting at a prompt is skipped.
- An instance started with `--listen` has no default pipe; it is found only under
  `NVIM_SERVER` or the stable pipe name.
- A TCP server cannot be verified.

## Switches

[../configuration.md](../configuration.md): `NVIM_SERVER`, `PREFER_STABLE_PIPE`,
`INSTANCE_PICK`, `FOLDER_OPENS_IN`, `FOCUS_TERMINAL`, and the diagnostic variables.
