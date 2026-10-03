# Bindings

openinnvim registers no Neovim keymaps, user commands or autocmds. What it adds are
Explorer context-menu entries.

## Context-menu entries

| Label | Where | Runs |
| --- | --- | --- |
| Open with Neovim (new instance) | file, folder, folder background | `OpenInNvim.exe new <path>` |
| Open with Neovim (current instance) | file, folder, folder background | `OpenInNvim.exe current <path>` |

Both carry the Neovim icon (the launcher's own when `nvim.exe` was not found at install
time) and sit in the classic menu (**Show more options** on Windows 11).

## Registry keys

Written by `install.ps1`; all under `HKCU`, so no administrator rights. `<dir>` below is
the install folder (default `%LOCALAPPDATA%\OpenInNvim`; `<repo>\bin` for an in-place
install).

| Key | `command` default value |
| --- | --- |
| `Software\Classes\*\shell\Open_in_Neovim_new` | `"<dir>\OpenInNvim.exe" new "%1"` |
| `Software\Classes\*\shell\Open_in_Neovim_current` | `"<dir>\OpenInNvim.exe" current "%1"` |
| `Software\Classes\Directory\shell\Open_in_Neovim_new` | `"<dir>\OpenInNvim.exe" new "%1"` |
| `Software\Classes\Directory\shell\Open_in_Neovim_current` | `"<dir>\OpenInNvim.exe" current "%1"` |
| `Software\Classes\Directory\Background\shell\Open_in_Neovim_new` | `"<dir>\OpenInNvim.exe" new "%V"` |
| `Software\Classes\Directory\Background\shell\Open_in_Neovim_current` | `"<dir>\OpenInNvim.exe" current "%V"` |

`%1` is the clicked item; `%V` is the folder whose background was clicked. The program is
named by its full, quoted path, so nothing is looked up at click time.

## The command line

```
OpenInNvim.exe current [path]   open the path in a running Neovim; start one when none is usable
OpenInNvim.exe new [path]       always start a new Neovim
```

- Without a path the working directory of the process is the target.
- Everything after the mode is the path. One pair of surrounding quotes is removed and a
  backslash is never an escape, so `"C:\"` (what Explorer writes for a drive root) is
  `C:\`.
- The path is used literally: no `%VAR%` expansion, no wildcards. A path that does not
  exist is a new file.
- `OpenInNvim.exe` is a windowed program: it never opens a console and prints only to a
  redirected stdout or stderr. Exit codes: [configuration.md](configuration.md#exit-codes).

## Diagnostic switches

Environment variables, listed with their effect in
[configuration.md](configuration.md#environment-switches).

## Checking the live state

```powershell
Get-ItemProperty -LiteralPath 'HKCU:\Software\Classes\*\shell\Open_in_Neovim_current\command'
```

shows the command a click runs. If the folder it names is gone, this command is
what points at it — [troubleshooting.md](troubleshooting.md#click-does-nothing).
