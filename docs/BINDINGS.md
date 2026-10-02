# Bindings

openinnvim registers no Neovim keymaps, user commands or autocmds. What it adds are
Explorer context-menu entries.

## Context-menu entries

| Label | Where | Runs |
| --- | --- | --- |
| Open with Neovim (new instance) | file, folder, folder background | `open-in-nvim.vbs` → `open-in-nvim.ps1` |
| Open with Neovim (current instance) | file, folder, folder background | `open-in-nvim-current.vbs` → `open-in-nvim-current.ps1` |

Both carry the Neovim icon and sit in the classic menu (**Show more options** on
Windows 11).

## Registry keys

Written by `install-context.ps1`; all under `HKCU`, so no administrator rights.

| Key | `command` default value |
| --- | --- |
| `Software\Classes\*\shell\Open_in_Neovim_new` | `wscript.exe //nologo "C:\tools\OpenInNvim\open-in-nvim.vbs" "%1"` |
| `Software\Classes\*\shell\Open_in_Neovim_current` | `wscript.exe //nologo "C:\tools\OpenInNvim\open-in-nvim-current.vbs" "%1"` |
| `Software\Classes\Directory\shell\Open_in_Neovim_new` | same as the first, with `"%1"` |
| `Software\Classes\Directory\shell\Open_in_Neovim_current` | same as the second, with `"%1"` |
| `Software\Classes\Directory\Background\shell\Open_in_Neovim_new` | same as the first, with `"%V"` |
| `Software\Classes\Directory\Background\shell\Open_in_Neovim_current` | same as the second, with `"%V"` |

`%1` is the clicked item; `%V` is the folder whose background was clicked.

The VBS file only exists to start PowerShell **without a console window**
(`WScript.Shell.Run` with window style 0); it forwards its arguments and does nothing
else.

## Diagnostic switches

Environment variables, listed with their effect in
[configuration.md](configuration.md#environment-switches).

## Checking the live state

```powershell
Get-ItemProperty -LiteralPath 'HKCU:\Software\Classes\*\shell\Open_in_Neovim_current\command'
```

shows the command a click runs. If the junction target is wrong, this command is
what points at it — [troubleshooting.md](troubleshooting.md#click-does-nothing).
