# What you get with the defaults

Without configuring anything beyond the path to `nvim.exe`, which the installer fills in:

- **Two entries, one meaning each.** *New instance* always starts a Neovim of its
  own. *Current instance* hands the file or folder to the Neovim you are already
  using, and only starts a new one when none is usable.
- **The right instance, found without setup.** Every Neovim session opens a pipe
  named after its process id; the launcher lists them, skips plugin jobs and other
  headless helpers, and picks the one started last. You do not have to start Neovim
  with `--listen` or add anything to `init.lua`.
- **One small program, no script host.** A click runs `OpenInNvim.exe` and nothing
  else: about 53 ms per click, against about 540 ms for the PowerShell script it
  replaced (642 ms through `wscript`) — measured on one machine with `--clean`
  instances.
- **Only your own Neovim gets the path.** Before anything is sent, the process behind
  the pipe is checked: `nvim.exe`, same logon session, same user.
- **Names with `%`, `$`, `[ ]`, `#`, quotes, spaces or Unicode open as the same file.**
  The path travels as a parameter of a small Lua call and reaches the buffer list
  through `bufadd`, never as command text.
- **A slow open stays where it is.** Once an instance has the request, the file is
  never sent to a second one.
- **Folders open in your tree** when the session has
  [filetree.nvim](https://github.com/StefanBartl/filetree.nvim), as the working
  directory with a directory view otherwise.
- **A fallback that does what you asked.** With no usable instance, Neovim starts with
  the file in WezTerm, Windows Terminal or a plain console, whichever exists first.
- **One-script install and uninstall.** `install.ps1` finds Neovim, builds the exe with
  the compiler that ships with Windows and registers the six entries; `uninstall.ps1`
  removes them again, and only the files the installer put there.
- **Hidden and local.** No console flash; nothing but the registry entries under
  `HKCU` and one folder under `%LOCALAPPDATA%`.
- **A test suite that cannot touch your session.** Its checks run against throw-away
  instances — [CONTRIBUTING.md](CONTRIBUTING.md#tests).
