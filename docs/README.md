# openinnvim documentation

What is here, and which question each page answers. [The README](../README.md)
is the short version of all of it.

## Using it

| Page | Answers |
| --- | --- |
| [requirements.md](requirements.md) | Which Windows, .NET Framework and Neovim, which terminal starts a new instance, and what is optional |
| [installation.md](installation.md) | `install.ps1`: what it builds, writes and registers, installing in place for development, and `uninstall.ps1` |
| [quickstart.md](quickstart.md) | The first click, and how to see what the launcher would do without opening anything |
| [configuration.md](configuration.md) | Every key in `open-in-nvim.ini`, every environment switch and the exit codes |
| [BINDINGS.md](BINDINGS.md) | The context-menu entries, the registry command behind each, and the command line of `OpenInNvim.exe` |
| [WORKFLOW.md](WORKFLOW.md) | Which entry to click when, and how several running instances are told apart |
| [troubleshooting.md](troubleshooting.md) | "Nothing happens", the wrong instance, a folder that does not open in the tree |

## Why it is the way it is

| Page | Answers |
| --- | --- |
| [what-you-get.md](what-you-get.md) | The things that matter on day one |
| [FEATURES/](FEATURES/README.md) | One page per part — current instance, new instance, folders, the default-app registration |
| [scope.md](scope.md) | What it does, what it deliberately does not, and its limits |
| [architecture.md](architecture.md) | One compiled program, RPC over the default pipe, the trust check, and why a path is never command text |
| [around-it.md](around-it.md) | How it fits next to Neovim's own `--remote`, filetree.nvim and your `init.lua` |
| [ROADMAP.md](ROADMAP.md) | Roadmap |
| [HANDOVER.md](HANDOVER.md) | Working notes and open items (German) |
| [REVIEW-2026-10-03.md](REVIEW-2026-10-03.md) | Review findings on the former VBS + PowerShell chain (German frame) |

## Working on it

| Page | Answers |
| --- | --- |
| [CONTRIBUTING.md](CONTRIBUTING.md) | Development setup, `build.ps1`, the test suite, and what is expected of a change |

## Not here

openinnvim is not a Neovim plugin, so there is no `doc/*.txt` help file and no
`:checkhealth`. The nearest equivalents are the dry-run switches and the decision log
(`OPEN_IN_NVIM_LOG`) in [configuration.md](configuration.md#environment-switches).
