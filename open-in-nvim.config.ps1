# open-in-nvim.config.ps1
# Zentrale Konfiguration für beide Einträge:
# - "Open with Neovim (new instance)"
# - "Open with Neovim (current instance)"

$Cfg = [ordered]@{
  # Absoluter Pfad zu Neovim (empfohlen). Falls nicht vorhanden, fällt das Skript auf "nvim" im PATH zurück.
  NVIM_BIN    = 'C:\Program Files\Neovim\bin\nvim.exe'

  # Optionales Terminal. Reihenfolge im Startskript: WezTerm -> Windows Terminal ("wt") -> cmd.exe ("start")
  WEZTERM_BIN = "$env:LOCALAPPDATA\wezterm\wezterm-gui.exe"

  # Stabile Serveradresse für "current instance".
  # Leer lassen, wenn die Auto-Discovery (nvr --serverlist) oder die Heuristik \\.\pipe\nvim-%USERNAME% verwendet werden soll.
  NVIM_SERVER = ''
}
