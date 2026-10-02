# open-in-nvim.config.ps1
# Central configuration for both entries:
# - "Open with Neovim (new instance)"
# - "Open with Neovim (current instance)"
# Every key is optional; see docs/configuration.md.

$Cfg = [ordered]@{
  # Absolute path to Neovim (recommended). If it does not exist, the scripts fall back to "nvim" on PATH.
  NVIM_BIN    = 'C:\Program Files\Neovim\bin\nvim.exe'

  # Optional terminal. Order in the launch script: WezTerm -> Windows Terminal ("wt") -> cmd.exe ("start")
  WEZTERM_BIN = "$env:LOCALAPPDATA\wezterm\wezterm-gui.exe"

  # Fixed server address tried first by "current instance" (a pipe name or host:port).
  # Leave empty to find the running instances automatically (default pipes, see docs/configuration.md).
  NVIM_SERVER = ''

  # A fixed pipe name \\.\pipe\nvim-%USERNAME% (if your init.lua creates it with serverstart()) goes first.
  # $false: skip the fixed name and treat all running instances alike.
  PREFER_STABLE_PIPE = $true

  # Which running instance is tried first when there are several. Every Neovim session has a pipe
  # \\.\pipe\nvim.<pid>.<n> without any configuration; instances without an attached UI (--headless
  # helpers) are ignored:
  #   'newest' = the most recently started (default), 'oldest' = the longest running,
  #   'ask'    = a chooser window showing each instance's working directory and file.
  INSTANCE_PICK = 'newest'

  # What a folder does in "current instance":
  #   'filetree' = point filetree.nvim at the folder (:Filetree open <dir>) if the instance has it,
  #   'edit'     = always cd + directory view (:edit .).
  FOLDER_OPENS_IN = 'filetree'
}
