# Default apps

Optional, and separate from the context menu. It registers Neovim in Windows'
**Default apps** list, so a double-click on `.md`, `.lua`, `.py` and many other
file types can open it — as "Neovim (new instance)" or "Neovim (current instance)".

Two paths exist; they overlap, and neither is required for the context-menu entries.

## One ProgID, chosen at run time

`register-nvim-default-app.ps1` asks (in German prompts) whether to register the *new*
or the *current* behaviour, then writes one ProgID `Neovim.TextFile` under `HKCU`
whose open command is `wscript.exe //nologo "<install>\open-in-nvim[-current].vbs" "%1"`,
with the Neovim icon and a long list of file extensions (text, web, scripting,
compiled languages, shells, configuration, databases, ...; the list is `$extensions`
in the script).

## Two ProgIDs with their own icons and names

The two exe launchers ([../building-launchers.md](../building-launchers.md)) give the
two behaviours separate names and icons, so both can be listed:

1. `register-nvim-default-app.ps1` — base registration (as above).
2. `install-icons-for-progids.ps1` — `DefaultIcon` for `Neovim.TextFile.New` and
   `Neovim.TextFile.Current` from `Logos\`.
3. `deploy-open-in-nvim.ps1` — copies the exes, the VBS files and the icons to
   `%LOCALAPPDATA%\OpenInNvim`, writes both ProgIDs with their `Capabilities`,
   and registers them under `RegisteredApplications`.

`deploy-open-in-nvim.ps1` also writes the default value of the class key for `.txt`,
`.md`, `.lua`, `.py` and `.js` to the *current* ProgID. That is the one thing here that
changes what a double-click does without going through Settings; the per-extension
`UserChoice` keys are never written (Windows protects them), so **Settings → Apps →
Default apps** has the last word.

The VBS files that the exes call run the `.ps1` files next to them, and
`deploy-open-in-nvim.ps1` copies those along (the config only when absent). Running
`install.ps1` first, into the same default folder, gives the exes a ready config with the
detected `nvim.exe`.

## Checking the registration

All read-only.

```powershell
# Registered applications that mention the Neovim ProgIDs
$reg = Get-ItemProperty -Path 'HKCU:\Software\RegisteredApplications' -ErrorAction SilentlyContinue
$reg.PSObject.Properties | Where-Object { $_.Value -match 'Neovim.TextFile' -or $_.Name -match 'Neovim.TextFile' } | Select-Object Name, Value

# Capabilities, icon and open command of both ProgIDs
Get-ItemProperty -Path 'HKCU:\Software\Neovim.TextFile.New\Capabilities' -ErrorAction SilentlyContinue
Get-ItemProperty -Path 'HKCU:\Software\Neovim.TextFile.Current\Capabilities' -ErrorAction SilentlyContinue
Get-ItemProperty -Path 'HKCU:\Software\Classes\Neovim.TextFile.New\DefaultIcon' -ErrorAction SilentlyContinue
Get-ItemProperty -Path 'HKCU:\Software\Classes\Neovim.TextFile.Current\DefaultIcon' -ErrorAction SilentlyContinue
Get-ItemProperty -Path 'HKCU:\Software\Classes\Neovim.TextFile.New\shell\open\command' -ErrorAction SilentlyContinue
Get-ItemProperty -Path 'HKCU:\Software\Classes\Neovim.TextFile.Current\shell\open\command' -ErrorAction SilentlyContinue

# File types recorded for each ProgID (may be many)
Get-ItemProperty -Path 'HKCU:\Software\Neovim.TextFile.New\Capabilities\FileAssociations' -ErrorAction SilentlyContinue
Get-ItemProperty -Path 'HKCU:\Software\Neovim.TextFile.Current\Capabilities\FileAssociations' -ErrorAction SilentlyContinue

# What Windows itself chose for two representative types (UserChoice overrides everything above)
Get-ItemProperty -Path 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\FileExts\.txt\UserChoice' -ErrorAction SilentlyContinue
Get-ItemProperty -Path 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\FileExts\.md\UserChoice' -ErrorAction SilentlyContinue
```

If Settings still shows "Microsoft Windows Based Script Host", open **Settings → Apps
→ Default apps**, search for "Neovim (new instance)" or "Neovim (current instance)"
and assign the file types there. Restarting Explorer refreshes icons.
