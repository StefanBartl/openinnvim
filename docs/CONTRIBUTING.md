# Contributing

Thanks for your interest in contributing to `openinnvim`.

## Development setup

1. Clone the repository:
   ```sh
   git clone https://github.com/StefanBartl/openinnvim.git
   ```
2. Register the menu *in place* while you work on it —
   `install.ps1 -InstallDir $PWD.Path`, see [installation.md](installation.md#in-place-development).
   The entries then run `<repo>\bin\OpenInNvim.exe`.
3. Build after every change, then run the tests (below):
   ```powershell
   powershell.exe -NoProfile -ExecutionPolicy Bypass -File build.ps1
   ```
   `build.ps1 [-OutDir <dir>]` compiles `src\*.cs` into `<repo>\bin\OpenInNvim.exe`
   (git-ignored) and prints the path; warnings are errors.

## Guidelines

- **C# 5, .NET Framework 4.x.** The compiler is the `csc.exe` that ships with Windows:
  no string interpolation, no `?.`, no `nameof`, no expression-bodied members, no
  `out var`. No NuGet packages; the references are fixed in `build.ps1`.
- **Keep the click path light.** WinForms is touched only by the chooser and the error
  box; nothing heavy belongs on the way from start to the RPC call.
- **Paths never go into command text.** A path is a parameter of the Lua in
  `Opener.cs`; there is no Ex file argument — [architecture.md](architecture.md#paths-are-parameters-not-text).
- **Nothing is written to a pipe before its server passed the trust check** in
  `Pipes.cs`.
- The scripts (`build.ps1`, `install.ps1`, `uninstall.ps1`, the tests) are written for
  **Windows PowerShell 5.1**: no `?:`, no `?.`, no parameter named `$args`. Run them
  under `powershell.exe`, not `pwsh`.
- Code comments in English; user-facing docs follow [docs/README.md](README.md) —
  one page owns one question.
- Prefer descriptive commit messages that say *why*.

## Tests

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File tests\run-tests.ps1
```

Run it under Windows PowerShell 5.1. It needs `nvim.exe` at
`C:\Program Files\Neovim\bin\nvim.exe` or in `$env:NVIM_EXE`. The suite (about 290 checks at
the time of writing) builds the exe into a temporary folder, calls its public static
methods through reflection (unit tests), and then runs it against its **own** throw-away
Neovim instances (`tests\fixture.lua`: `nvim --embed` cores with a UI attached, plus two
headless helpers that must be ignored).

It cannot reach your running session: the launcher is only ever started with
`OPEN_IN_NVIM_ONLY_PIDS` set to the fixture's process ids, with a fake `USERNAME` (so
your per-user pipe is never touched), and with `OPEN_IN_NVIM_NO_SPAWN` or
`OPEN_IN_NVIM_SPAWN_DRYRUN` (so no window ever opens). Cleanup stops only processes the
run started, by their own process id.

What it covers:

- the msgpack encoder and decoder (every type family, incomplete versus malformed input,
  the depth limit, huge length prefixes) and the RPC stream parser;
- the raw command line, command-line quoting checked against `CommandLineToArgvW`, the
  `PATH` lookup, the ini parser, pipe names and addresses, target kinds;
- discovery and order, `INSTANCE_PICK`, the stable pipe, `NVIM_SERVER` as a pipe and
  over TCP;
- the trust check, against a fake pipe server that is not Neovim and owns
  Neovim-looking names;
- opening files (hostile names open as the same file) and folders (`:Filetree` present
  and absent);
- instances that must not get the file (headless, blocked at a prompt, busy, refusing),
  and the slow open that must not reach a second instance;
- editor modes and window situations;
- exit codes and switches, the terminals for a new instance, the chooser, the focus
  lookup;
- `install.ps1` and `uninstall.ps1` against a throw-away folder and registry key.

The real context-menu entries are never touched. `tests\fixture.lua` is linted with
`stylua --check` and `luacheck`.

## Reporting issues

Please provide:

- Windows version and `nvim --version`
- The terminal you use (WezTerm, Windows Terminal, other)
- The decision log of the click (`OPEN_IN_NVIM_LOG`, see
  [troubleshooting.md](troubleshooting.md#click-does-nothing)) and the output of
  `OPEN_IN_NVIM_DRYRUN=1`
- Clear steps to reproduce
