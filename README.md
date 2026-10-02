> **Beta stage — active development.** This repository is past its first shape and in
> active use, but the surface is not frozen: breaking changes are still possible. Pin a
> commit or tag if you depend on it.

# openinnvim

```
 ██████╗ ██████╗ ███████╗███╗   ██╗██╗███╗   ██╗███╗   ██╗██╗   ██╗██╗███╗   ███╗
██╔═══██╗██╔══██╗██╔════╝████╗  ██║██║████╗  ██║████╗  ██║██║   ██║██║████╗ ████║
██║   ██║██████╔╝█████╗  ██╔██╗ ██║██║██╔██╗ ██║██╔██╗ ██║██║   ██║██║██╔████╔██║
██║   ██║██╔═══╝ ██╔══╝  ██║╚██╗██║██║██║╚██╗██║██║╚██╗██║╚██╗ ██╔╝██║██║╚██╔╝██║
╚██████╔╝██║     ███████╗██║ ╚████║██║██║ ╚████║██║ ╚████║ ╚████╔╝ ██║██║ ╚═╝ ██║
 ╚═════╝ ╚═╝     ╚══════╝╚═╝  ╚═══╝╚═╝╚═╝  ╚═══╝╚═╝  ╚═══╝  ╚═══╝  ╚═╝╚═╝     ╚═╝
```

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)
[![Neovim](https://img.shields.io/badge/Neovim-0.10%2B-57A143?logo=neovim&logoColor=white)](https://neovim.io)
[![PowerShell](https://img.shields.io/badge/PowerShell-5.1-5391FE?logo=powershell&logoColor=white)](https://learn.microsoft.com/powershell/)
![Status](https://img.shields.io/badge/status-beta-orange)
![Platform](https://img.shields.io/badge/platform-Windows-lightgrey)

> Folders open in the tree of [filetree.nvim](https://github.com/StefanBartl/filetree.nvim) when
> the running session has it — see [Around it](docs/around-it.md).

Two Windows Explorer context-menu entries for Neovim: open a file or folder in a **new** instance,
or hand it to the instance you are **already working in**. No Neovim plugin and no external tool
are required.

---

## Documentation

Start at [docs/README.md](docs/README.md) — what's where, and which question
each page answers.

**The Basics**

- [Requirements](docs/requirements.md) — Windows, PowerShell and Neovim versions, and the terminal that starts a new instance.
- [Installation](docs/installation.md) — one script: files, config and the six registry entries; and the uninstaller.
- [Quickstart](docs/quickstart.md) — the first click, and how to see what the launcher would do without opening anything.

**Configuration**

- [What you get with the defaults](docs/what-you-get.md) — the things that matter on day one.
- [All options](docs/configuration.md) — every key in `open-in-nvim.config.ps1` and every environment switch.
- [Bindings](docs/BINDINGS.md) — the context-menu entries, what each registry key runs, and the switches.

**The Rest**

- [Features](docs/FEATURES/README.md) — one page per part: the current-instance launcher, the new-instance launcher, folders, the default-app launchers.
- [Workflow](docs/WORKFLOW.md) — which entry to click when, and how several running instances are told apart.
- [Around it](docs/around-it.md) — how this fits next to Neovim's own `--remote`, filetree.nvim and your `init.lua`.
- [What it does and what not](docs/scope.md)
- [Why it does it that way](docs/architecture.md) — RPC over the default pipe, the UI check, and the PowerShell 5.1 traps behind the code.
- [Troubleshooting](docs/troubleshooting.md) — "nothing happens", wrong instance, folder does not open in the tree.
- [Building the exe launchers](docs/building-launchers.md) — the optional .NET front end for the default-app registration.
- [Contributing](docs/CONTRIBUTING.md) — development setup and the test suite.
- [Feedback](https://github.com/StefanBartl/openinnvim/issues)

---

## License

openinnvim is released under the [MIT License](https://opensource.org/licenses/MIT) — see [LICENSE](LICENSE).
