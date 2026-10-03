# Folders

A folder click on "Open with Neovim (current instance)" means "go here". What that
does depends on the target session and on `FOLDER_OPENS_IN`.

## `filetree` (default)

If the instance has the `:Filetree` command
([filetree.nvim](https://github.com/StefanBartl/filetree.nvim)), the launcher runs

```lua
vim.cmd({ cmd = 'Filetree', args = { 'open', dir } })
```

inside it. What happens next — the tree, the focus, the working directory — is
filetree.nvim's; the launcher changes nothing else.

The folder is passed as an argument table, not as command text, so a folder name
containing a space, `#`, `%`, `[` or `(` arrives in one piece.

## Without filetree.nvim, or `edit`

The folder becomes the working directory (`nvim_set_current_dir`, which fires
`DirChanged` like `:cd`) and a directory view opens (`:silent edit .`, in a split when
the current window's buffer cannot be replaced).

Neovim expands `$NAME` in a directory name before changing to it. So that a folder such
as `a$USERNAME b` is the folder that was clicked, the environment variables the name
mentions are hidden for the moment of the change and restored afterwards.

If the directory view fails after the working directory was changed, that is not an
error for the launcher: the folder is not sent to a second instance.

## Folder background

Right-clicking the empty area of an Explorer window sends that window's folder, so
"current instance" there points your editor at the folder you are looking at.

## New instance

"Open with Neovim (new instance)" on a folder starts Neovim with that folder as working
directory and no file argument — [NEW-INSTANCE.md](NEW-INSTANCE.md).

## Over TCP

A TCP `NVIM_SERVER` gets the same request as a pipe; nothing is different for folders.
