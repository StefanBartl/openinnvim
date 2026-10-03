# Around it

**[filetree.nvim](https://github.com/StefanBartl/filetree.nvim)** — the tree a folder
click opens in, when the running session has it. openinnvim only runs
`:Filetree open <folder>`; everything about how the tree looks and behaves is
filetree.nvim's.

**Neovim's own `--remote`** — `nvim --server <addr> --remote <file>` reaches an instance
over the same RPC channel, but you have to know the address, it starts a second
`nvim.exe` to do it, and the file name becomes an Ex argument. openinnvim finds the
address, checks who is behind it, skips helper processes and instances waiting at a
prompt, opens the file under its exact name, and falls back to starting a new instance.
It never calls `nvim --remote` itself.

**Your `init.lua`** — nothing has to be added there. A fixed
`vim.fn.serverstart([[\\.\pipe\nvim-<USER>]])` is useful if you want to pin one session
as "the main instance" ([configuration.md](configuration.md#prefer_stable_pipe)), and
it is the only coupling.

filetree.nvim and a pinned name are both soft: without them everything else works
unchanged. There are no hard dependencies beyond Neovim itself —
[requirements.md](requirements.md).
