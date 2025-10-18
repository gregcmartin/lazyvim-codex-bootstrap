# LazyVim Codex Bootstrap

This project provides an automated bootstrap script that installs and configures a ready-to-use environment for running Codex-enhanced LazyVim inside a tmux session launched via Ghostty.

## What the bootstrap does
- Installs core dependencies on macOS and Linux: git, Neovim, Node.js/npm, tmux, and Ghostty (when available).
- Clones the LazyVim starter configuration and switches it to a dark Tokyonight theme.
- Adds the Codex Neovim plugin with command- and key-based activation.
- Installs the Codex CLI and, when provided, persists the `OPENAI_API_KEY` to the user shell profile.
- Creates a dedicated workspace (`~/lazyvim-codex-workspace` by default) with an `AGENTS.md` file instructing Codex how to use tmux panes and windows.
- Sets Ghostty as the default terminal (when installed) and applies a dark theme.
- Writes tmux configuration snippets that add Alt+c / Alt+s shortcuts to open Codex windows or splits.
- Generates a launcher script (`~/.local/bin/lazyvim-codex`) that opens Ghostty → tmux → LazyVim with Codex automatically running alongside Neovim.

## Usage
1. Run the bootstrap script and supply your OpenAI key if you want it persisted:
   ```bash
   ./bootstrap.sh --openai-key "sk-..."
   ```
2. Launch the integrated environment via the generated wrapper:
   ```bash
   lazyvim-codex
   ```
   This opens Ghostty (if installed), attaches to the `lazyvim-codex` tmux session, starts Neovim in the main pane, and runs the Codex CLI in a split.
3. Use Alt+c to create a new tmux window running Codex, or Alt+s for a split, keeping Neovim focused in the primary pane.

## Customisation
- Override defaults by setting environment variables before running the script, for example:
  ```bash
  export LAZYVIM_CODEX_WORKDIR="$HOME/projects/codex-playground"
  export NVIM_CONFIG_DIR="$HOME/.config/nvim-codex"
  ./bootstrap.sh
  ```
- To skip tmux wrapping, pass `--no-tmux`.
- To skip headless plugin synchronization, pass `--skip-headless-sync`.

## Requirements
- macOS or Linux environment with sudo privileges for installing packages.
- `curl` and `git` available in the PATH.
- OpenAI key (optional but recommended) if you want Codex to authenticate automatically.

## License
Licensed under the MIT License.
