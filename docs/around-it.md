# Around it

**[filetree.nvim](https://github.com/StefanBartl/filetree.nvim)** — the tree a folder
click opens in, when the running session has it. openinnvim only sends
`:Filetree open <folder>`; everything about how the tree looks and behaves is
filetree.nvim's.

**Neovim's own `--remote`** — `nvim --server <addr> --remote <file>` does the same
`:drop` openinnvim sends. The difference is the work around it: openinnvim finds the
address for you, skips helper processes, handles names the command line would mangle,
and falls back to starting a new instance. It uses the command line itself only for
TCP addresses.

**Your `init.lua`** — nothing has to be added there. A fixed
`vim.fn.serverstart([[\\.\pipe\nvim-<USER>]])` is useful if you want to pin one session
as "the main instance" ([configuration.md](configuration.md#prefer_stable_pipe)), and
it is the only coupling.

filetree.nvim and a pinned name are both soft: without them everything else works
unchanged. There are no hard dependencies beyond Neovim itself —
[requirements.md](requirements.md).
