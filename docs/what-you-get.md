# What you get with the defaults

Without configuring anything beyond the path to `nvim.exe`:

- **Two entries, one meaning each.** *New instance* always starts a Neovim of its
  own. *Current instance* hands the file or folder to the Neovim you are already
  using, and only starts a new one when none is running.
- **The right instance, found without setup.** Every Neovim session opens a pipe
  named after its process id; the launcher lists them, skips plugin jobs and other
  headless helpers, and picks the one started last. You do not have to start Neovim
  with `--listen` or add anything to `init.lua`.
- **No second `nvim.exe`.** The file is sent over that pipe (`:drop`, what
  `nvim --remote` does), so a click costs roughly half a second including the
  PowerShell start, not a second and a half.
- **Names with `#`, `%`, `[`, `(`, quotes or `&` just work.** The path travels as a
  parameter of a small Lua call, never as command text.
- **Folders open in your tree** when the session has
  [filetree.nvim](https://github.com/StefanBartl/filetree.nvim), as the working
  directory with a directory view otherwise.
- **A fallback that does what you asked.** With no running instance, a new terminal
  (WezTerm, Windows Terminal or `cmd`) starts Neovim with the file.
- **Hidden, safe, local.** No console flash; the launchers talk only to Neovim
  instances of your own Windows session.
- **A test suite that cannot touch your session.** Its checks run against throw-away
  instances — [CONTRIBUTING.md](CONTRIBUTING.md#tests).
