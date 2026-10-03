# What it does and what not

## Does

- Adds two Explorer context-menu entries (file, folder, folder background): open in a
  **new** Neovim, or in the **current** one. Both run one program, `OpenInNvim.exe`.
- For "current": finds a running instance of your own that has a UI and is not waiting
  at a prompt, opens the file or the folder (the tree, or a directory view) there, and
  starts a new instance only when none is usable.
- Starts new instances in WezTerm, Windows Terminal or a plain console
  (`TERMINAL = auto | wezterm | wt | console`).
- Installs and removes itself: `install.ps1` builds the exe, writes the config and
  registers the entries, `uninstall.ps1` takes them out again.
- Optionally brings the instance's window to the front (`FOCUS_TERMINAL`).
- Optionally registers Neovim as the default application for many file types
  ([FEATURES/DEFAULT-APPS.md](FEATURES/DEFAULT-APPS.md)).

## Does not

- **It is not a Neovim plugin.** It adds nothing to your editor; it talks to it.
- **No Linux or macOS.** The context-menu variants for Linux file managers are a
  separate piece of the author's dotfiles, not part of this repository.
- **No Windows 11 top-level menu entry.** Registry-based entries live in the classic
  menu (**Show more options**). A top-level entry would need a shell extension.
- **No other editors.** Instances of other Windows users and other logon sessions are
  ignored on purpose.
- **No file association by default.** The context menu does not change what a
  double-click does; that is the optional default-app registration.
- **No `nvr`**, and no `nvim --remote`. Not needed, not used.

## Limits

- **A renamed Neovim binary is not found.** The process behind a pipe must be
  `nvim.exe`.
- **A TCP server cannot be verified.** Nobody can tell which process listens on a port;
  `NVIM_SERVER = host:port` is used on your word alone.
- **An instance waiting at a prompt is skipped.** With a hit-enter prompt open in your
  only session, the click goes to the next instance or starts a new one.
- **Several windows of one terminal process cannot be told apart** for
  `FOCUS_TERMINAL`: the raised window may be another one of the same WezTerm or Windows
  Terminal process.
- **An instance started with `--listen`** has no default pipe and is found only under
  the name in `NVIM_SERVER` or under `\\.\pipe\nvim-%USERNAME%`.
