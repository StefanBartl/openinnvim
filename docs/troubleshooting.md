# Troubleshooting

## Click does nothing

The chain is Explorer → `wscript.exe` → the VBS → `powershell.exe` → the `.ps1`. Check
the links from the end:

1. **Run the script directly**, with a console, to see errors the hidden chain
   swallows:

   ```powershell
   powershell -NoProfile -ExecutionPolicy Bypass -File $env:LOCALAPPDATA\OpenInNvim\open-in-nvim-current.ps1 "$env:USERPROFILE\Desktop\test.txt"
   ```

2. **Is the folder in the entry still there?** The command (see
   [BINDINGS.md](BINDINGS.md#checking-the-live-state)) names the install folder; if that folder
   was moved or deleted, the entry is fine and its target is gone. Run `install.ps1` again —
   [installation.md](installation.md). An old setup that still points at a junction
   `C:\tools\OpenInNvim` fails the same way when the repository moves.
3. **Is Neovim found?** Set `NVIM_BIN` in `open-in-nvim.config.ps1`, or put `nvim` on
   `PATH`. The new-instance entry shows a popup with `OPEN_IN_NVIM_DEBUG=1`; the current-instance one
   prints an error when run directly (step 1).
4. **Does a new window need a terminal?** WezTerm, Windows Terminal and `cmd.exe` are
   tried in that order; see [requirements.md](requirements.md).

## It opened in the wrong instance

Print the order the launcher would use:

```powershell
$env:OPEN_IN_NVIM_DRYRUN = '1'
powershell -NoProfile -ExecutionPolicy Bypass -File $env:LOCALAPPDATA\OpenInNvim\open-in-nvim-current.ps1 "$env:USERPROFILE\Desktop\test.txt"
```

The first candidate wins. Then:

- A fixed name (`\\.\pipe\nvim-<USER>`) is first while one session owns it — set
  `PREFER_STABLE_PIPE = $false` to ignore it.
- `INSTANCE_PICK` decides the rest: `newest`, `oldest` or `ask`.
- An instance without a UI (a `--headless` server) never appears. In Neovim,
  `:echo len(nvim_list_uis())` is 1 or more for a session the launcher can use.
- Instances of another Windows user are never offered.

## The file opened, but behind another window

Windows only lets the foreground process raise a window. Turn on `FOCUS_TERMINAL` in the
config ([configuration.md](configuration.md#focus_terminal)). With several windows in one
WezTerm or Windows Terminal process it can raise a different window of that process than
the instance's own; that is a limit of how the window is found, not a setting.

## A new instance was started although Neovim is running

The launcher found no instance it could talk to. Check, in the running Neovim:

```vim
:echo v:servername
```

A path like `\\.\pipe\nvim.12345.0` is the default pipe and is what the launcher
looks for. If it is empty, that Neovim has no server (started with an unusual
`--listen`, or the server was stopped). If the instance answers but refuses (for
example a blocking prompt), the launcher moves on and finally starts a new one.

## A folder does not open in the tree

`:echo exists(':Filetree')` must be `2` in the target session. If it is `0`, the
plugin is not loaded or not installed there, and the launcher falls back to a plain
directory view on purpose. `FOLDER_OPENS_IN = 'edit'` makes that the permanent choice.

## Special characters in the path

Spaces, `#`, `%`, `[`, `(`, `'` and `&` are handled (they travel as a parameter, not as
command text). A folder literally named like an environment variable (`%TEMP%`) is
used as typed.

## `verify.ps1` opens windows

By design: it clicks all four chains end to end. Run it when you want to see the real
thing; the automated tests are in `tests\` —
[CONTRIBUTING.md](CONTRIBUTING.md#tests).
