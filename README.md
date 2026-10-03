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
[![.NET Framework](https://img.shields.io/badge/.NET%20Framework-4.x-512BD4?logo=dotnet&logoColor=white)](https://learn.microsoft.com/dotnet/framework/)
![Status](https://img.shields.io/badge/status-beta-orange)
![Platform](https://img.shields.io/badge/platform-Windows-lightgrey)

> Folders open in the tree of [filetree.nvim](https://github.com/StefanBartl/filetree.nvim) when
> the running session has it — see [Around it](docs/around-it.md).

Two Windows Explorer context-menu entries for Neovim: open a file or folder in a **new** instance,
or hand it to the instance you are **already working in**. Both entries run one small compiled
program, `OpenInNvim.exe`, which talks to Neovim over its own RPC pipe. No Neovim plugin and no
external tool are required; the program is built at install time with the C# compiler that ships
with Windows.

## Install

Download `OpenInNvim-Setup.exe` from the [releases](https://github.com/StefanBartl/openinnvim/releases)
and run it: per user, no administrator rights, and it brings its own `uninstall.exe` (also listed under
*Settings > Apps*). Not code-signed, so SmartScreen may warn; compare the SHA-256 from the release.
No clone needed. From a clone instead: `install.ps1`, see [docs/installation.md](docs/installation.md).

`build-setup.ps1` builds the setup (`dist\OpenInNvim-Setup.exe` + `SHA256SUMS.txt`) with the same C#
compiler as the launcher: no Inno Setup, no NuGet. The version is the one line in `VERSION`; the source is
in `setup\`.

---

## Documentation

Start at [docs/README.md](docs/README.md) — what's where, and which question
each page answers.

**The Basics**

- [Requirements](docs/requirements.md) — Windows, .NET Framework and Neovim, and the terminal that starts a new instance.
- [Installation](docs/installation.md) — the setup program (with its own uninstaller), or one script: build, config and the six registry entries.
- [Quickstart](docs/quickstart.md) — the first click, and how to see what the launcher would do without opening anything.

**Configuration**

- [What you get with the defaults](docs/what-you-get.md) — the things that matter on day one.
- [All options](docs/configuration.md) — every key in `open-in-nvim.ini`, every environment switch, the exit codes.
- [Bindings](docs/BINDINGS.md) — the context-menu entries, what each registry key runs, and the command line.

**The Rest**

- [Features](docs/FEATURES/README.md) — one page per part: current instance, new instance, folders, the default-app registration.
- [Workflow](docs/WORKFLOW.md) — which entry to click when, and how several running instances are told apart.
- [Around it](docs/around-it.md) — how this fits next to Neovim's own `--remote`, filetree.nvim and your `init.lua`.
- [What it does and what not](docs/scope.md)
- [Why it does it that way](docs/architecture.md) — one compiled program, RPC over the default pipe, the trust check, and why a path is never command text.
- [Troubleshooting](docs/troubleshooting.md) — "nothing happens", wrong instance, folder does not open in the tree.
- [Contributing](docs/CONTRIBUTING.md) — development setup, the build and the test suite.
- [Feedback](https://github.com/StefanBartl/openinnvim/issues)

---

## License

openinnvim is released under the [MIT License](https://opensource.org/licenses/MIT) — see [LICENSE](LICENSE).
