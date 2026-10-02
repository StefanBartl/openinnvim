# Folders

A folder click on "Open with Neovim (current instance)" means "go here". What that
does depends on the target session and on `FOLDER_OPENS_IN`.

## `filetree` (default)

If the instance has the `:Filetree` command
([filetree.nvim](https://github.com/StefanBartl/filetree.nvim)), the launcher runs

```lua
vim.cmd.Filetree({ args = { "open", dir } })
```

inside it. The tree opens focused on the folder — also from a session that had no tree
open — and the working directory follows.

The folder is passed as an argument table, not as command text. An `:Filetree open
<escaped dir>` string fails silently for folder names containing `#`, `%`, `[` or `(`,
because Vim's escaping and the command's argument splitting disagree; a table gives
the command the path in one piece.

## Without filetree.nvim, or `edit`

The folder becomes the working directory (`nvim_set_current_dir`, which fires
`DirChanged` like `:cd`) and a directory view opens (`:silent edit .`).

## Folder background

Right-clicking the empty area of an Explorer window sends that window's folder, so
"current instance" there points your editor at the folder you are looking at.

## Over TCP

A TCP `NVIM_SERVER` is reached through the command line, which supports only the
directory view (`:cd` + `:edit .`).
