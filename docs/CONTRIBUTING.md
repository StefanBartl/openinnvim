# Contributing

Thanks for your interest in contributing to `openinnvim`.

## Development setup

1. Clone the repository:
   ```sh
   git clone https://github.com/StefanBartl/openinnvim.git
   ```
2. Register the menu *in place* while you work on it —
   `install.ps1 -InstallDir $PWD.Path`, see [installation.md](installation.md#in-place-development).
   The entries then run the scripts in your clone, so what you edit is what a click runs.
3. Run the tests (below) after every change.

## Guidelines

- **Windows PowerShell 5.1 first.** No `?:`, no `?.`, no `$args` as a parameter name,
  no empty element in `-ArgumentList` — [architecture.md](architecture.md#windows-powershell-51-traps).
  Parse every script under `powershell.exe`, not `pwsh`:

  ```powershell
  $e = $null; $t = $null
  [void][System.Management.Automation.Language.Parser]::ParseFile((Resolve-Path .\open-in-nvim-current.ps1).Path, [ref]$t, [ref]$e)
  $e.Count   # 0
  ```
- `open-in-nvim.lib.ps1` is ASCII only.
- Code comments in English; user-facing docs follow [docs/README.md](README.md) —
  one page owns one question.
- Paths never go into command text: use the RPC parameters in
  `Invoke-NvimOpen`, not string-built commands.
- Prefer descriptive commit messages that say *why*.

## Tests

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File tests\run-tests.ps1
```

Run it under Windows PowerShell 5.1. The suite starts its **own** throw-away Neovim
instances (`tests\fixture.lua`: `nvim --embed` cores with a UI attached, plus two
headless helpers that must be ignored) and drives the real launchers against them. It
cannot reach your running session: discovery is restricted to the fixture's process ids
(`OPEN_IN_NVIM_ONLY_PIDS`), the per-user pipe name is switched off, the `USERNAME` the
launcher sees is a fake, no window is ever started (`OPEN_IN_NVIM_NO_SPAWN`,
`OPEN_IN_NVIM_SPAWN_DRYRUN`), and cleanup stops only processes that started during the
run.

What it covers: the msgpack encoder and decoder (including a depth limit),
command-line quoting checked against `CommandLineToArgvW`, folder-path normalisation,
instance discovery and ordering, opening files and folders over RPC (special characters,
`:Filetree` present and absent), the new-instance command, both launcher scripts, the
process-tree walk behind `FOCUS_TERMINAL`, and `install.ps1` / `uninstall.ps1` against a
throw-away folder and registry key — including the installed VBS driving a throw-away
instance end to end. The real context-menu entries are never touched.

`tests\fixture.lua` is linted with `stylua --check` and `luacheck`.

## Reporting issues

Please provide:

- Windows version and `nvim --version`
- The terminal you use (WezTerm, Windows Terminal, other)
- The output of the launcher run directly (see [troubleshooting.md](troubleshooting.md#click-does-nothing))
  and of `OPEN_IN_NVIM_DRYRUN=1`
- Clear steps to reproduce
