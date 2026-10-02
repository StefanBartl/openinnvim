# What it does and what not

## Does

- Adds two Explorer context-menu entries (file, folder, folder background): open in a
  **new** Neovim, or in the **current** one.
- For "current": finds a running instance with a UI, opens the file (`:drop`) or the
  folder (the tree, or a directory view), and starts a new instance only when none is
  reachable.
- Starts new instances in WezTerm, Windows Terminal or `cmd.exe`, whichever exists
  first.
- Optionally registers Neovim as the default application for many file types, through
  two small exe launchers ([FEATURES/DEFAULT-APPS.md](FEATURES/DEFAULT-APPS.md)).

## Does not

- **It is not a Neovim plugin.** It adds nothing to your editor; it talks to it.
- **No Linux or macOS.** The context-menu variants for Linux file managers are a
  separate piece of the author's dotfiles, not part of this repository.
- **No Windows 11 top-level menu entry.** Registry-based entries live in the classic
  menu (**Show more options**). A top-level entry would need a shell extension.
- **No other editors**, and no remote machines: pipes are local, and instances of
  other Windows users are ignored on purpose.
- **No file association by default.** The context menu does not change what a
  double-click does; that is the optional default-app registration.
- **No `nvr`.** Not needed, not used.
