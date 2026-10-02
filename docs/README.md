# openinnvim documentation

What is here, and which question each page answers. [The README](../README.md)
is the short version of all of it.

## Using it

| Page | Answers |
| --- | --- |
| [requirements.md](requirements.md) | Which Windows, PowerShell and Neovim versions, which terminal starts a new instance, and what is optional |
| [installation.md](installation.md) | `install.ps1`: what it copies, writes and registers, installing in place for development, and `uninstall.ps1` |
| [quickstart.md](quickstart.md) | The first click, and how to see what the launcher would do without opening anything |
| [configuration.md](configuration.md) | Every key in `open-in-nvim.config.ps1` and every environment switch, with defaults |
| [BINDINGS.md](BINDINGS.md) | The context-menu entries, the registry command behind each, and the diagnostic switches |
| [WORKFLOW.md](WORKFLOW.md) | Which entry to click when, and how several running instances are told apart |
| [troubleshooting.md](troubleshooting.md) | "Nothing happens", the wrong instance, a folder that does not open in the tree |

## Why it is the way it is

| Page | Answers |
| --- | --- |
| [what-you-get.md](what-you-get.md) | The things that matter on day one |
| [FEATURES/](FEATURES/README.md) | One page per part — current-instance launcher, new-instance launcher, folders, the default-app launchers |
| [scope.md](scope.md) | What it does, and what it deliberately does not |
| [architecture.md](architecture.md) | RPC over the default pipe, the UI check, and the PowerShell 5.1 traps behind the code |
| [around-it.md](around-it.md) | How it fits next to Neovim's own `--remote`, filetree.nvim and your `init.lua` |

## Working on it

| Page | Answers |
| --- | --- |
| [CONTRIBUTING.md](CONTRIBUTING.md) | Development setup, the test suite, and what is expected of a change |
| [building-launchers.md](building-launchers.md) | Building the two optional exe launchers with the .NET SDK |

## Not here

openinnvim is not a Neovim plugin, so there is no `doc/*.txt` help file and no
`:checkhealth`. The nearest equivalents are `verify.ps1` (does the click chain
run end to end) and the dry-run switches in [BINDINGS.md](BINDINGS.md).
