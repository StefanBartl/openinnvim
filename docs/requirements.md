# Requirements

## Needed

- **Windows 10 or 11.** The registry keys and the pipe names are Windows-only. On
  Windows 11 the entries are in the classic menu (**Show more options**).
- **.NET Framework 4.x** — part of Windows 10 and 11, nothing to install. It runs
  `OpenInNvim.exe` and brings the C# compiler (`csc.exe`) that `install.ps1` builds it
  with. No .NET SDK.
- **Neovim 0.10 or newer.** The launcher relies on the default server pipe every
  instance opens (`\\.\pipe\nvim.<pid>.<n>`) and on the RPC calls `nvim_get_mode`,
  `nvim_eval` and `nvim_exec_lua`. The binary must be named `nvim.exe`.

Windows PowerShell 5.1, which also ships with Windows, runs `install.ps1`,
`uninstall.ps1` and the tests. It is not involved in a click.

That is the whole list. In particular there is **no dependency on `nvr`
(neovim-remote)**, Python, or any Neovim plugin: Neovim's own RPC is spoken
directly by the launcher.

## Optional

- **WezTerm or Windows Terminal** for new instances. Without either, Neovim starts in a
  plain console window — [configuration.md](configuration.md#terminal).
- [filetree.nvim](https://github.com/StefanBartl/filetree.nvim) — when the running
  session has the `:Filetree` command, a folder is opened *in the tree*. Without
  it, a folder becomes the working directory with a directory view. See
  [FEATURES/FOLDERS.md](FEATURES/FOLDERS.md).
- A fixed server name in your `init.lua` (`vim.fn.serverstart([[\\.\pipe\nvim-<USER>]])`)
  to pin one session as "the" current instance — see
  [configuration.md](configuration.md#prefer_stable_pipe).
- Python with `pyfiglet`, only if you regenerate the README art.
