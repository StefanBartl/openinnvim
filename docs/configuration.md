# Configuration

One file: `open-in-nvim.config.ps1`, shared by both entries. It assigns an ordered
hashtable to `$Cfg`. A missing key falls back to the default below, so an older
config file keeps working.

```powershell
$Cfg = [ordered]@{
  NVIM_BIN           = 'C:\Program Files\Neovim\bin\nvim.exe'
  WEZTERM_BIN        = "$env:LOCALAPPDATA\wezterm\wezterm-gui.exe"
  NVIM_SERVER        = ''
  PREFER_STABLE_PIPE = $true
  INSTANCE_PICK      = 'newest'
  FOLDER_OPENS_IN    = 'filetree'
  FOCUS_TERMINAL     = $false
}
```

| Key | Default | Used by | Meaning |
| --- | --- | --- | --- |
| `NVIM_BIN` | `C:\Program Files\Neovim\bin\nvim.exe` | both | Absolute path to Neovim. If it does not exist, `nvim` from `PATH` is used. |
| `WEZTERM_BIN` | `%LOCALAPPDATA%\wezterm\wezterm-gui.exe` | both | WezTerm, the first terminal tried for a new instance. Missing: `wezterm` from `PATH`, then Windows Terminal, then `cmd.exe`. |
| `NVIM_SERVER` | `''` | current | A fixed server address to try first. Empty: running instances are found automatically. |
| `PREFER_STABLE_PIPE` | `$true` | current | Try `\\.\pipe\nvim-%USERNAME%` first, when it exists. |
| `INSTANCE_PICK` | `'newest'` | current | Which running instance goes first: `newest`, `oldest` or `ask`. |
| `FOLDER_OPENS_IN` | `'filetree'` | current | What a folder does: `filetree` or `edit`. |
| `FOCUS_TERMINAL` | `$false` | current | Bring the window that hosts the instance to the front after opening. |

## `NVIM_SERVER`

An address as Neovim understands it: a pipe name (`\\.\pipe\mynvim`) or a TCP address
(`127.0.0.1:6666`). It is tried first. A pipe is spoken to directly; a TCP address
goes through `nvim --server <addr> --remote`, which is the only case that starts a
second `nvim.exe`. The same value is passed to `--listen` when a new instance has to
be started because none was reachable.

## `PREFER_STABLE_PIPE`

If your `init.lua` calls `vim.fn.serverstart([[\\.\pipe\nvim-<USER>]])`, that session
owns a predictable name. With several sessions open, only the first can claim it —
that one is "the main instance", and with this key on, clicks go there regardless of
which session started last. Set `$false` to ignore the name and treat all running
instances alike.

## `INSTANCE_PICK`

When more than one instance is running (after the stable pipe, if any):

- `newest` — the one started last.
- `oldest` — the one running longest.
- `ask` — a small list showing each instance's working directory and current file;
  Enter or double-click picks, Escape cancels without opening anything. With only
  one instance there is nothing to ask.

An instance counts only if it has a UI attached and belongs to your own Windows
session — see [architecture.md](architecture.md#which-instances-count).

## `FOLDER_OPENS_IN`

- `filetree` — `:Filetree open <folder>` when the instance has that command,
  otherwise the same as `edit`.
- `edit` — always make the folder the working directory and open a directory view
  (`:edit .`).

Details: [FEATURES/FOLDERS.md](FEATURES/FOLDERS.md).

## `FOCUS_TERMINAL`

Off by default. Windows does not let a background process raise a window, so after a
click the editor may open its file behind whatever you were looking at. With
`$true` the launcher looks up which window hosts the instance — it walks up the process
tree from the editor to the first ancestor that owns a window (WezTerm, Windows
Terminal, Neovide) — and asks Windows to raise it, restoring it first if it is minimized.

Best effort, and honest about its limit: one WezTerm or Windows Terminal process can
host several windows and reports only one of them, so with several terminal windows open
the raised one may not be the instance's own. It costs about 0.3–0.5 s (a process-tree
lookup and a one-off compile), which is why it is opt-in. Any failure is silent and the
file is opened regardless.

## Config location

The config lives next to the scripts: `%LOCALAPPDATA%\OpenInNvim\open-in-nvim.config.ps1`
for an installed copy, the repository's own file for an in-place install
([installation.md](installation.md)). `install.ps1` never overwrites an existing config
unless you pass `-Force`.

## Environment switches

Set in the environment of the launcher (or `$env:` in a test shell). They exist for
tests and diagnosis and change nothing for normal clicks.

| Variable | Effect |
| --- | --- |
| `OPEN_IN_NVIM_DRYRUN=1` | print the ordered candidates, open nothing |
| `OPEN_IN_NVIM_SPAWN_DRYRUN=1` | print the command that would start a new instance, start nothing |
| `OPEN_IN_NVIM_NO_SPAWN=1` | never start a window; when nothing is reachable print `no reachable instance` and exit with code 3 |
| `OPEN_IN_NVIM_ONLY_PIDS=<pid,pid>` | consider only these processes, and never the per-user pipe name |
| `OPEN_IN_NVIM_DEBUG=1` | the new-instance entry shows a popup when Neovim cannot be found |
