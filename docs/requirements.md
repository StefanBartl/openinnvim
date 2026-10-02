# Requirements

## Needed

- **Windows 10 or 11.** Developed and tested on Windows 11; the registry keys and
  the pipe names are Windows-only.
- **Windows PowerShell 5.1** — the one that ships with Windows
  (`C:\Windows\System32\WindowsPowerShell\v1.0\powershell.exe`). PowerShell 7 is not
  involved; the launchers are written for 5.1 and parsed against it.
- **Neovim 0.10 or newer.** Verified with 0.12.2. The launcher relies on the default
  server pipe every instance opens (`\\.\pipe\nvim.<pid>.<n>`) and on the RPC calls
  `nvim_list_uis` and `nvim_exec_lua`.
- **A terminal to start a new instance in**, tried in this order: WezTerm, Windows
  Terminal (`wt`), plain `cmd.exe`. Only the "new instance" entry and the
  "no running instance" case need one.

That is the whole list. In particular there is **no dependency on `nvr`
(neovim-remote)**, Python, or any Neovim plugin: Neovim's own RPC is spoken
directly from PowerShell.

## Optional

- [filetree.nvim](https://github.com/StefanBartl/filetree.nvim) — when the running
  session has the `:Filetree` command, a folder is opened *in the tree*. Without
  it, a folder becomes the working directory with a directory view. See
  [FEATURES/FOLDERS.md](FEATURES/FOLDERS.md).
- A fixed server name in your `init.lua` (`vim.fn.serverstart([[\\.\pipe\nvim-<USER>]])`)
  to pin one session as "the" current instance — see
  [configuration.md](configuration.md#prefer_stable_pipe).
- The [.NET 8 SDK](https://dotnet.microsoft.com/download), only if you want the two
  exe launchers for the default-app registration —
  [building-launchers.md](building-launchers.md).
- Python with `pyfiglet`, only if you regenerate the README art.
