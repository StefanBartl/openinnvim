# Troubleshooting

## Click does nothing

The chain is short: Explorer → `OpenInNvim.exe` → Neovim. The program has no console, so
ask it for its log:

1. **Run it directly with a log file:**

   ```powershell
   $env:OPEN_IN_NVIM_LOG = "$env:TEMP\oin.log"
   & "$env:LOCALAPPDATA\OpenInNvim\OpenInNvim.exe" current "$env:USERPROFILE\Desktop\test.txt" | Out-String
   $LASTEXITCODE
   Get-Content $env:OPEN_IN_NVIM_LOG
   ```

   The log has one line per decision — every pipe that was skipped and why, the instance
   that was used, the command of a new instance — and ends with the exit code
   ([configuration.md](configuration.md#exit-codes)).

2. **Is the exe in the entry still there?** The command (see
   [BINDINGS.md](BINDINGS.md#checking-the-live-state)) names the install folder; if that
   folder was moved or deleted, the entry is fine and its target is gone. Run
   `install.ps1` again — [installation.md](installation.md).
3. **Is Neovim found?** When it is not, a box says "Neovim not found". Set `NVIM_BIN` in
   `open-in-nvim.ini`, or put `nvim` on `PATH`.
4. **Does the build fail?** `install.ps1` only reports that it failed; run `build.ps1`
   to see the compiler output.

## It opened in the wrong instance

Print the order the launcher would use:

```powershell
$env:OPEN_IN_NVIM_DRYRUN = '1'
& "$env:LOCALAPPDATA\OpenInNvim\OpenInNvim.exe" current "$env:USERPROFILE\Desktop\test.txt" | Out-String
```

The first candidate wins. Then:

- `NVIM_SERVER` is first when it is set and reachable.
- The owner of the fixed name `\\.\pipe\nvim-<USER>` is next — set
  `PREFER_STABLE_PIPE = false` to ignore it.
- `INSTANCE_PICK` decides the rest: `newest`, `oldest` or `ask`.
- An instance without a UI (a `--headless` server) never appears. In Neovim,
  `:echo len(nvim_list_uis())` is 1 or more for a session the launcher can use.
- Instances of another Windows user or another logon session are never offered.

## A new instance was started although Neovim is running

The launcher found no instance it could use. The log (above) names the reason for each
one. The usual ones:

- **The instance was waiting at a prompt** — a hit-enter prompt, for one. Such an
  instance is skipped on purpose; a file sent there would not open until the prompt is
  answered.
- **It was busy** and did not answer within 300 ms.
- **The binary is not named `nvim.exe`.** A renamed or wrapped Neovim does not pass the
  check on who serves the pipe.
- **It runs as another user** or in another logon session, or its process cannot be
  inspected by the launcher.
- **It has no default pipe and no name the launcher knows.** In the running Neovim:

  ```vim
  :echo v:servername
  ```

  A path like `\\.\pipe\nvim.12345.0` is the default pipe and is found. An instance
  started with `--listen <name>` is found only when that name is `NVIM_SERVER` or
  `\\.\pipe\nvim-<USER>`.

## The file opened twice, or not at all, on a slow open

It should do neither. Once the request is with an instance the launcher waits up to 15
seconds and never sends the target to a second one. If the editor shows a swap-file
dialog, the file opens when you answer it.

## The file opened, but behind another window

Turn on `FOCUS_TERMINAL` in the config
([configuration.md](configuration.md#focus_terminal)). With several windows in one
WezTerm or Windows Terminal process it can raise a different window of that process than
the instance's own; that is a limit of how the window is found, not a setting.

## A folder does not open in the tree

`:echo exists(':Filetree')` must be `2` in the target session. If it is `0`, the
plugin is not loaded or not installed there, and the launcher falls back to a plain
directory view on purpose. `FOLDER_OPENS_IN = edit` makes that the permanent choice.

## Special characters in the path

Spaces, `#`, `%`, `$`, `[ ]`, `(`, `'`, `&`, `;` and Unicode are handled: the path
travels as a parameter, not as command text, and is opened under exactly that name. A
folder literally named like an environment variable (`%TEMP%`) is used as typed.

## A config change has no effect

The ini that counts is the one next to the exe the entry runs
(`%LOCALAPPDATA%\OpenInNvim\open-in-nvim.ini`, or `<repo>\bin\open-in-nvim.ini` in
place), not the template in the repository root. A value that is not valid and a key
that is not known are ignored; the log names both.

## A TCP `NVIM_SERVER`

The launcher cannot verify who listens on a port. It connects only to the address you
wrote into the config, waits at most 300 ms for the connection, and then goes on to the
running instances.
