# Default apps

Optional, and separate from the context menu. It registers Neovim in Windows'
**Default apps** list, so a double-click on `.md`, `.lua`, `.py` and many other
file types can open it — as "Neovim (new instance)" or "Neovim (current instance)".

Run `install.ps1` first: the registration points at the `OpenInNvim.exe` it builds.

## `register-nvim-default-app.ps1`

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\register-nvim-default-app.ps1
```

It asks whether to register the *new* or the *current* behaviour, then writes one ProgID
`Neovim.TextFile` under `HKCU`:

- the open command `"<dir>\OpenInNvim.exe" new "%1"` or `"<dir>\OpenInNvim.exe" current "%1"`;
- the display name "Neovim (new instance)" or "Neovim (current instance)", and the
  exe as `DefaultIcon`;
- `Capabilities` with a long list of file extensions (text, web, scripting, compiled
  languages, shells, configuration, databases, ...; the list is `$extensions` in
  `file-extensions.ps1`), and an entry under `RegisteredApplications`.

`<dir>` is `-InstallPath` (default `%LOCALAPPDATA%\OpenInNvim`); the exe is looked for
there and in its `bin` subfolder, so `-InstallPath <repo>` works for an in-place
install. The script stops when it finds no `OpenInNvim.exe`.

It does not change what a double-click does. The per-extension `UserChoice` keys are
never written (Windows protects them): pick the app in **Settings → Apps → Default
apps**, or through **Open with → Choose another app**.

A double-click then behaves exactly like the context-menu entry of the same mode —
[CURRENT-INSTANCE.md](CURRENT-INSTANCE.md), [NEW-INSTANCE.md](NEW-INSTANCE.md).

## `install-icons-for-progids.ps1`

Writes `DefaultIcon` (from `Logos\`), a display name, minimal `Capabilities` and a
`RegisteredApplications` entry for two further ProgIDs, `Neovim.TextFile.New` and
`Neovim.TextFile.Current`. It writes no open command for them, and no other script in
the repository does; on its own it registers names and icons only.

## Checking the registration

All read-only.

```powershell
# Registered applications that mention the Neovim ProgID
$reg = Get-ItemProperty -Path 'HKCU:\Software\RegisteredApplications' -ErrorAction SilentlyContinue
$reg.PSObject.Properties | Where-Object { $_.Value -match 'Neovim.TextFile' -or $_.Name -match 'Neovim.TextFile' } | Select-Object Name, Value

# Display name, icon and open command
Get-ItemProperty -Path 'HKCU:\Software\Classes\Neovim.TextFile' -ErrorAction SilentlyContinue
Get-ItemProperty -Path 'HKCU:\Software\Classes\Neovim.TextFile\DefaultIcon' -ErrorAction SilentlyContinue
Get-ItemProperty -Path 'HKCU:\Software\Classes\Neovim.TextFile\shell\open\command' -ErrorAction SilentlyContinue

# File types recorded for the ProgID (many)
Get-ItemProperty -Path 'HKCU:\Software\Neovim.TextFile\Capabilities\FileAssociations' -ErrorAction SilentlyContinue

# What Windows itself chose for two representative types (UserChoice overrides everything above)
Get-ItemProperty -Path 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\FileExts\.txt\UserChoice' -ErrorAction SilentlyContinue
Get-ItemProperty -Path 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\FileExts\.md\UserChoice' -ErrorAction SilentlyContinue
```

## Removing it

`uninstall.ps1` does not remove this registration. If you delete the exe
(`uninstall.ps1 -RemoveFiles`), choose another default app for the file types in
Settings.
