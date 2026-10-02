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

  # Fester Pipe-Name \\.\pipe\nvim-%USERNAME% (falls die eigene init.lua ihn mit serverstart() anlegt) hat Vorrang.
  # $false: den festen Namen überspringen und nur die laufenden Instanzen betrachten.
  PREFER_STABLE_PIPE = $true

  # Welche laufende Instanz zuerst probiert wird, wenn mehrere da sind (jede Neovim-Sitzung hat ohne
  # Konfiguration eine Pipe \\.\pipe\nvim.<pid>.<n>; Instanzen ohne angedocktes UI, also --headless-Hilfsprozesse, werden ignoriert):
  #   'newest' = zuletzt gestartete (Standard), 'oldest' = am längsten laufende,
  #   'ask'    = Auswahlfenster mit Arbeitsverzeichnis und Datei jeder Instanz.
  INSTANCE_PICK = 'newest'

  # Was bei einem Ordner in "current instance" passiert:
  #   'filetree' = filetree.nvim auf den Ordner richten (:Filetree open <dir>), wenn die Instanz es hat,
  #   'edit'     = immer cd + Verzeichnisansicht (:edit .).
  FOLDER_OPENS_IN = 'filetree'
}
