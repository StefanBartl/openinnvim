# Current instance

`open-in-nvim-current.ps1`, started by `open-in-nvim-current.vbs`. Hands the clicked
file or folder to a Neovim that is already running; only when none is reachable does
it start a new one.

## Finding the instance

The candidates, in order, are `NVIM_SERVER`, the stable pipe name
(`\\.\pipe\nvim-%USERNAME%`, when a session owns it), and every other running instance
with a UI attached, ordered by `INSTANCE_PICK`. Why a UI, and why only your own
Windows session: [../architecture.md](../architecture.md#which-instances-count).

`INSTANCE_PICK = 'ask'` shows a list ("Open in Neovim - choose instance") with each
instance's working directory, current file, process id and start time. Enter or a
double-click picks; Escape closes it without opening anything. It is only shown when
more than one instance is left.

## Opening

For a pipe address the file goes over RPC as `:silent drop <file>` — the same command
`nvim --remote` runs. `:drop` reuses a window that already shows the file and
otherwise opens it. A file that does not exist yet is opened as a new buffer.

The call has a time limit. If the instance connects but answers with an error or not
in time, the launcher goes on to the next candidate instead of retrying the same one;
if every candidate refuses, it starts a new instance.

A TCP `NVIM_SERVER` has no RPC path here and goes through `nvim --server <addr>
--remote`.

## Raising the window

`FOCUS_TERMINAL = $true` brings the instance's terminal window to the front after the
file has been opened — [../configuration.md](../configuration.md#focus_terminal). Off by
default; with several windows in one terminal process it can pick the wrong one.

## When nothing is reachable

A new Neovim starts in a terminal — WezTerm, then Windows Terminal, then `cmd.exe` —
with the folder as working directory, `--listen \\.\pipe\nvim-%USERNAME%` so that the
next click finds it, and the file after `--`. If that pipe name is already taken
(an instance that answered with an error), `--listen` is left out. The command is
described in [NEW-INSTANCE.md](NEW-INSTANCE.md).

## Switches

[../configuration.md](../configuration.md): `NVIM_SERVER`, `PREFER_STABLE_PIPE`,
`INSTANCE_PICK`, `FOLDER_OPENS_IN`, and the diagnostic variables.
