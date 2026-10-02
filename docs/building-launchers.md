# Building the exe launchers

Optional. The two exe launchers exist for the default-application registration
([FEATURES/DEFAULT-APPS.md](FEATURES/DEFAULT-APPS.md)); the context menu does not
need them.

`Program.cs` is one tiny program built twice. It forwards the file path it is given to
the VBS next to it — `open-in-nvim.vbs` when its own file name contains `new`
(case-insensitive), `open-in-nvim-current.vbs` otherwise. Two assembly names and two
icons therefore give two apps Windows can list separately.

## Requirements

[.NET 8 SDK](https://dotnet.microsoft.com/download), Windows x64 (`TinyLauncher.csproj`
targets `net8.0`, `win-x64`, single-file, with an apphost so the icon is embedded).

## Build

```powershell
dotnet publish -c Release -r win-x64 `
  /p:AssemblyName=tiny-launcher-new `
  /p:ApplicationIcon="Logos\new-session.ico" `
  /p:AssemblyTitle="Neovim Launcher (new instance)" `
  -o publish\new

dotnet publish -c Release -r win-x64 `
  /p:AssemblyName=tiny-launcher-current `
  /p:ApplicationIcon="Logos\current-session.ico" `
  /p:AssemblyTitle="Neovim Launcher (current instance)" `
  -o publish\current
```

Check that both exist:

```powershell
Get-Item .\publish\new\*.exe, .\publish\current\*.exe
```

`publish\`, `bin\` and `obj\` are git-ignored.

Then `deploy-open-in-nvim.ps1` copies the exes, the VBS files and the icons to
`%LOCALAPPDATA%\OpenInNvim` and registers the ProgIDs.
