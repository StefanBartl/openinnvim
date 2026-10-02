# Workflow — which entry, when

Both entries are documented on their own elsewhere ([FEATURES/](FEATURES/README.md)).
This is the different question: with the two of them in the menu, how do you actually
choose.

## Default to *current instance*

If a Neovim is already open, "current instance" is almost always what you mean: the
file lands next to the buffers you already have, your marks and registers are right
there, and no second window competes for the screen. It costs the same as "new
instance" when nothing is running — it simply starts one.

Reach for **new instance** when you want isolation on purpose: a file you do not want
mixed into the session you are in, a comparison side by side in two windows, or an
editor you can close without losing the other one.

## Several instances: let the order work for you

With more than one session open, the default (`newest`) sends the click to the one you
started last, which is usually the one you are looking at. Three habits make it
predictable:

- **Pin a main session.** Start one Neovim with a fixed name in `init.lua`
  (`vim.fn.serverstart([[\\.\pipe\nvim-<USER>]])`). With `PREFER_STABLE_PIPE` on, every
  click goes to it, however many others you open later.
- **Ask when it matters.** `INSTANCE_PICK = 'ask'` shows each instance's working
  directory and current file before it opens anything. It only asks when there is a
  real choice.
- **Look at the order first.** `OPEN_IN_NVIM_DRYRUN=1` prints the instances in the
  order they would be tried — see [quickstart.md](quickstart.md).

## Folders

A folder click is a "go here" gesture, not "edit this". With filetree.nvim in the
session the tree jumps to the folder and your working directory follows; set
`FOLDER_OPENS_IN = 'edit'` if you would rather have a plain directory view.
[FEATURES/FOLDERS.md](FEATURES/FOLDERS.md).

## Clicking on the background

Right-clicking the empty area of an Explorer window passes that window's folder, so
"current instance" there means "point my editor at this folder".
