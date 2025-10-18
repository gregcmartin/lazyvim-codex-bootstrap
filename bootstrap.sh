#!/usr/bin/env bash

if [ -z "${BASH_VERSION:-}" ]; then
  exec /usr/bin/env bash "$0" "$@"
fi

set -euo pipefail

LAZYVIM_REPO="https://github.com/LazyVim/starter"
NVIM_CONFIG_DIR="${NVIM_CONFIG_DIR:-$HOME/.config/nvim}"
CODEX_PLUGIN_FILE="$NVIM_CONFIG_DIR/lua/plugins/codex.lua"
SCRIPT_NAME="$(basename "$0")"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
SCRIPT_PATH="$SCRIPT_DIR/$SCRIPT_NAME"
LAZYVIM_CODEX_WORKDIR="${LAZYVIM_CODEX_WORKDIR:-$HOME/lazyvim-codex-workspace}"
LOCAL_BIN_DIR="${LOCAL_BIN_DIR:-$HOME/.local/bin}"
LAUNCHER_SCRIPT="$LOCAL_BIN_DIR/lazyvim-codex"
GHOSTTY_CONFIG_FILE="${GHOSTTY_CONFIG_FILE:-$HOME/.config/ghostty/config}"
DETECTED_GHOSTTY_PATH=""

info() { printf '[INFO] %s\n' "$*"; }
warn() { printf '[WARN] %s\n' "$*" >&2; }
error() { printf '[ERROR] %s\n' "$*" >&2; exit 1; }

command_exists() { command -v "$1" >/dev/null 2>&1; }

detect_ghostty_path() {
  if [ -n "${DETECTED_GHOSTTY_PATH:-}" ] && [ -x "$DETECTED_GHOSTTY_PATH" ]; then
    printf '%s\n' "$DETECTED_GHOSTTY_PATH"
    return 0
  fi

  if command_exists ghostty; then
    DETECTED_GHOSTTY_PATH="$(command -v ghostty)"
    printf '%s\n' "$DETECTED_GHOSTTY_PATH"
    return 0
  fi

  local candidates=(
    "/Applications/Ghostty.app/Contents/MacOS/ghostty"
    "$HOME/Applications/Ghostty.app/Contents/MacOS/ghostty"
  )

  if command_exists brew; then
    local brew_prefix
    brew_prefix="$(brew --prefix 2>/dev/null || true)"
    if [ -n "$brew_prefix" ]; then
      candidates+=("$brew_prefix/bin/ghostty" "$brew_prefix/opt/ghostty/bin/ghostty")
      local cask_root="$brew_prefix/Caskroom/ghostty"
      if [ -d "$cask_root" ]; then
        local path
        while IFS= read -r path; do
          if [ -n "$path" ]; then
            candidates+=("$path")
          fi
        done <<EOF
$(find "$cask_root" -type f -path "*/Ghostty.app/Contents/MacOS/ghostty" -print 2>/dev/null || true)
EOF
      fi
    fi
  fi

  local candidate
  for candidate in "${candidates[@]}"; do
    if [ -x "$candidate" ]; then
      DETECTED_GHOSTTY_PATH="$candidate"
      printf '%s\n' "$candidate"
      return 0
    fi
  done

  return 1
}

ghostty_theme_exists() {
  local theme="$1"
  local ghostty_bin
  ghostty_bin="$(detect_ghostty_path)" || return 1

  if "$ghostty_bin" +list-themes 2>/dev/null | awk -F' (' '{print $1}' | grep -Fx "$theme" >/dev/null 2>&1; then
    return 0
  fi

  local user_theme="$HOME/.config/ghostty/themes/$theme"
  if [ -f "$user_theme" ]; then
    return 0
  fi

  local theme_dir
  theme_dir="$(cd "$(dirname "$ghostty_bin")/../Resources/ghostty/themes" 2>/dev/null && pwd || true)"
  if [ -n "$theme_dir" ] && [ -f "$theme_dir/$theme" ]; then
    return 0
  fi

  return 1
}

require_command() {
  local cmd="$1"
  local hint="${2:-Install the appropriate package for your system.}"
  command_exists "$cmd" || error "$cmd is required. $hint"
}

usage() {
  cat <<'EOF'
Usage: bootstrap.sh [options]

Options:
  --openai-key=KEY        Provide the OpenAI API key for Codex.
  --shell-rc=PATH         Persist the API key in the specified shell rc file.
  --skip-headless-sync    Skip running Neovim headless Lazy sync (runs by default).
  --no-auto-launch        Skip launching LazyVim Codex after setup completes.
  --help                  Show this help message.

Environment:
  OPENAI_API_KEY          Used when --openai-key is not provided.
  NVIM_CONFIG_DIR         Override Neovim config directory (default ~/.config/nvim).
  NVIM_APPNAME            Respected if already exported for Neovim.
EOF
}

detect_platform() {
  case "$(uname -s)" in
    Darwin) echo "macos" ;;
    Linux) echo "linux" ;;
    *) error "Unsupported platform: $(uname -s)" ;;
  esac
}

detect_shell_rc() {
  local shell_path="${SHELL:-}"
  case "$shell_path" in
    */zsh) echo "${ZDOTDIR:-$HOME}/.zshrc" ;;
    */bash)
      if [ -f "$HOME/.bashrc" ] || [ ! -f "$HOME/.bash_profile" ]; then
        echo "$HOME/.bashrc"
      else
        echo "$HOME/.bash_profile"
      fi
      ;;
    */fish) echo "$HOME/.config/fish/config.fish" ;;
    *) echo "" ;;
  esac
}

persist_shell_export() {
  local shell_rc="$1"
  local var_name="$2"
  local value="$3"
  local note="${4:-Added by lazyvim-codex bootstrap}"

  touch "$shell_rc"
  if grep -Fq "${var_name}=" "$shell_rc"; then
    warn "$var_name already present in $shell_rc; skipping persistence."
    return 0
  fi

  info "Persisting $var_name to $shell_rc"
  {
    printf '\n# %s on %s\n' "$note" "$(date)"
    printf 'export %s=%q\n' "$var_name" "$value"
  } >>"$shell_rc"
}

ensure_dir() {
  mkdir -p "$1"
}

setup_lazyvim_dark_theme() {
  local theme_file="$NVIM_CONFIG_DIR/lua/plugins/colorscheme.lua"
  if [ -f "$theme_file" ]; then
    info "LazyVim colorscheme plugin already exists at $theme_file; skipping."
    return
  fi

  info "Configuring LazyVim to use a dark Tokyonight theme."
  ensure_dir "$(dirname "$theme_file")"
  cat >"$theme_file" <<'EOF'
return {
  {
    "folke/tokyonight.nvim",
    lazy = false,
    priority = 1000,
    opts = {
      style = "night",
      dim_inactive = true,
    },
    config = function(_, opts)
      require("tokyonight").setup(opts)
      vim.o.background = "dark"
      vim.cmd.colorscheme("tokyonight")
    end,
  },
}
EOF
}

setup_ghostty_theme() {
  local config_file="$GHOSTTY_CONFIG_FILE"
  ensure_dir "$(dirname "$config_file")"

  if [ -f "$config_file" ] && grep -Fq "lazyvim-codex bootstrap theme" "$config_file"; then
    info "Removing legacy Ghostty theme block inserted by a previous bootstrap run."
    local temp_file
    temp_file="$(mktemp)"
    awk '
      skip > 0 { skip--; next }
      /# lazyvim-codex bootstrap theme/ { skip = 3; next }
      { print }
    ' "$config_file" >"$temp_file"
    mv "$temp_file" "$config_file"
  fi

  if [ -f "$config_file" ] && grep -Fq "lazyvim-codex bootstrap preferences" "$config_file"; then
    info "Ghostty config already contains lazyvim-codex preferences block."
    return
  fi

  local theme_name="Catppuccin Mocha"
  local theme_line=""
  if ghostty_theme_exists "$theme_name"; then
    theme_line="theme = \"$theme_name\""
  else
    warn "Ghostty theme \"$theme_name\" not found; leaving theme unchanged."
    theme_line="# theme = \"$theme_name\""
  fi

  info "Adding Ghostty appearance hints to $config_file."
  {
    printf '\n# lazyvim-codex bootstrap preferences (%s)\n' "$(date)"
    echo '# Adjust these values as desired.'
    echo '# macos-appearance = "dark"'
    echo "$theme_line"
  } >>"$config_file"
}

create_launcher_script() {
  ensure_dir "$LOCAL_BIN_DIR"

  local workdir="$LAZYVIM_CODEX_WORKDIR"
  ensure_dir "$workdir"
  local ghostty_path="${DETECTED_GHOSTTY_PATH:-}"
  if [ -z "$ghostty_path" ]; then
    ghostty_path="$(detect_ghostty_path 2>/dev/null || true)"
  fi
  if [ -z "$ghostty_path" ]; then
    ghostty_path="ghostty"
  fi

  local codex_string="codex --full-access --dangerously-bypass-approvals-and-sandbox"

  info "Creating launcher script at $LAUNCHER_SCRIPT"
  cat >"$LAUNCHER_SCRIPT" <<EOF
#!/usr/bin/env bash
set -euo pipefail

DEFAULT_WORKDIR="$workdir"
WORKDIR="\${LAZYVIM_CODEX_WORKDIR:-\$DEFAULT_WORKDIR}"
CODEX_CMD=(codex --full-access --dangerously-bypass-approvals-and-sandbox)
CODEX_STRING="$codex_string"

cd "\$WORKDIR"

launch_with_ghostty() {
  local ghostty_bin="\$1"
  "\$ghostty_bin" --command="nvim" &
  local nvim_pid=\$!
  if command -v codex >/dev/null 2>&1; then
    "\$ghostty_bin" +new-window --command="\$CODEX_STRING" >/dev/null 2>&1 || true
  fi
  wait "\$nvim_pid"
}

if [ -n "$ghostty_path" ] && [ -x "$ghostty_path" ]; then
  launch_with_ghostty "$ghostty_path"
elif ghostty_bin="\$(command -v ghostty 2>/dev/null)"; then
  launch_with_ghostty "\$ghostty_bin"
else
  printf 'Ghostty not detected; launching LazyVim directly in this terminal. Run "%s" separately if needed.\n' "\${CODEX_CMD[*]}" >&2
  nvim
fi
EOF

  chmod +x "$LAUNCHER_SCRIPT"
}

setup_codex_agent_notes() {
  local agents_file="$LAZYVIM_CODEX_WORKDIR/AGENTS.md"
  ensure_dir "$LAZYVIM_CODEX_WORKDIR"

  local agents_needs_update=1
  if [ -f "$agents_file" ] && grep -Fq "--dangerously-bypass-approvals-and-sandbox" "$agents_file"; then
    agents_needs_update=0
  fi

  if [ "$agents_needs_update" -eq 0 ]; then
    info "AGENTS.md already contains updated Codex guidance."
    return
  fi

  info "Writing Codex agent guidance at $agents_file"
  cat >"$agents_file" <<'EOF'
# LazyVim Codex Workspace Guidelines

- The launcher opens Ghostty running LazyVim in the first window.
- Codex CLI runs in a separate Ghostty window using full-access YOLO flags.
- Use `ghostty +new-window --command="codex --full-access --dangerously-bypass-approvals-and-sandbox"` to spawn extra Codex sessions.
- Workspace files live in \`$LAZYVIM_CODEX_WORKDIR\`; stay rooted there unless you intentionally leave.
- When Ghostty is unavailable the launcher falls back to running LazyVim in the current terminal.
EOF
}

install_dependencies_macos() {
  if ! command_exists brew; then
    warn "Homebrew is not installed. Install it from https://brew.sh and re-run the script if dependencies are missing."
    return
  fi

  local packages=()
  command_exists git || packages+=("git")
  command_exists nvim || packages+=("neovim")
  command_exists npm || packages+=("node")

  if ((${#packages[@]})); then
    info "Installing required packages with Homebrew: ${packages[*]}"
    brew install "${packages[@]}"
  else
    info "All required Homebrew packages already installed."
  fi
}

install_dependencies_linux() {
  if command_exists apt-get; then
    local packages=()
    command_exists git || packages+=("git")
    command_exists curl || packages+=("curl")
    command_exists gpg || packages+=("gnupg")
    command_exists nvim || packages+=("neovim")
    if ! command_exists npm; then
      packages+=("nodejs" "npm")
    fi

    if ((${#packages[@]})); then
      info "Installing required packages with apt-get: ${packages[*]}"
      sudo apt-get update
      sudo apt-get install -y "${packages[@]}"
    else
      info "All required apt packages already installed."
    fi
  elif command_exists dnf; then
    local packages=()
    command_exists git || packages+=("git")
    command_exists curl || packages+=("curl")
    command_exists nvim || packages+=("neovim")
    if ! command_exists npm; then
      packages+=("nodejs" "npm")
    fi

    if ((${#packages[@]})); then
      info "Installing required packages with dnf: ${packages[*]}"
      sudo dnf install -y "${packages[@]}"
    else
      info "All required dnf packages already installed."
    fi
  elif command_exists pacman; then
    local packages=()
    command_exists git || packages+=("git")
    command_exists curl || packages+=("curl")
    command_exists nvim || packages+=("neovim")
    if ! command_exists npm; then
      packages+=("nodejs" "npm")
    fi

    if ((${#packages[@]})); then
      info "Installing required packages with pacman: ${packages[*]}"
      sudo pacman -Sy --needed "${packages[@]}"
    else
      info "All required pacman packages already installed."
    fi
  else
    warn "Unsupported package manager. Please install git, curl, neovim, and npm manually."
  fi
}

install_dependencies() {
  local platform
  platform="$(detect_platform)"
  case "$platform" in
    macos) install_dependencies_macos ;;
    linux) install_dependencies_linux ;;
  esac

  require_command git "Install git before proceeding."
  require_command nvim "Install Neovim (v0.9+) before proceeding."
  require_command npm "Install Node.js and npm before proceeding."
}

install_ghostty_macos() {
  if command_exists ghostty; then
    info "Ghostty already installed."
    return 0
  fi

  if ! command_exists brew; then
    warn "Homebrew not found; cannot install Ghostty automatically on macOS."
    return 1
  fi

  if brew list --cask ghostty >/dev/null 2>&1; then
    info "Ghostty cask already present."
    return 0
  fi

  info "Installing Ghostty via Homebrew cask."
  if brew install --cask ghostty; then
    info "Ghostty installed successfully."
    return 0
  fi

  warn "Failed to install Ghostty via Homebrew."
  return 1
}

install_ghostty_debian() {
  if command_exists ghostty; then
    return 0
  fi

  local keyring="/usr/share/keyrings/ghostty-archive-keyring.gpg"
  local repo_file="/etc/apt/sources.list.d/ghostty.sources"

  if [ ! -f "$keyring" ]; then
    info "Adding Ghostty Debian repository key."
    if ! curl -fsSL https://repo.ghostty.org/debian/ghostty.key | sudo gpg --dearmor -o "$keyring"; then
      warn "Failed to import Ghostty repository key."
      return 1
    fi
  fi

  if [ ! -f "$repo_file" ]; then
    info "Configuring Ghostty Debian repository."
    if ! sudo tee "$repo_file" >/dev/null <<EOF
Types: deb
URIs: https://repo.ghostty.org/debian
Suites: stable
Components: main
Signed-By: $keyring
EOF
    then
      warn "Failed to write Ghostty repository definition."
      return 1
    fi
  fi

  if ! sudo apt-get update; then
    warn "apt-get update failed after adding Ghostty repository."
    return 1
  fi

  if sudo apt-get install -y ghostty; then
    info "Ghostty installed via apt."
    return 0
  fi

  warn "Failed to install Ghostty via apt."
  return 1
}

install_ghostty_fedora() {
  if command_exists ghostty; then
    return 0
  fi

  local repo_file="/etc/yum.repos.d/ghostty.repo"
  if [ ! -f "$repo_file" ]; then
    info "Configuring Ghostty Fedora repository."
    if ! sudo rpm --import https://repo.ghostty.org/rpm/ghostty.asc; then
      warn "Failed to import Ghostty RPM repository key."
      return 1
    fi
    if ! sudo tee "$repo_file" >/dev/null <<'EOF'
[ghostty]
name=Ghostty
baseurl=https://repo.ghostty.org/rpm/
enabled=1
gpgcheck=1
repo_gpgcheck=1
gpgkey=https://repo.ghostty.org/rpm/ghostty.asc
EOF
    then
      warn "Failed to write Ghostty repo configuration."
      return 1
    fi
  fi

  if sudo dnf install -y ghostty; then
    info "Ghostty installed via dnf."
    return 0
  fi

  warn "Failed to install Ghostty via dnf."
  return 1
}

install_ghostty_arch() {
  if command_exists ghostty; then
    return 0
  fi

  if sudo pacman -S --needed --noconfirm ghostty; then
    info "Ghostty installed via pacman."
    return 0
  fi

  warn "Failed to install Ghostty via pacman."
  return 1
}

install_ghostty_linux() {
  if command_exists ghostty; then
    info "Ghostty already installed."
    return 0
  fi

  if command_exists apt-get; then
    install_ghostty_debian && return 0
  elif command_exists dnf; then
    install_ghostty_fedora && return 0
  elif command_exists pacman; then
    install_ghostty_arch && return 0
  fi

  warn "Automatic Ghostty install unsupported on this Linux distribution."
  return 1
}

install_ghostty() {
  local platform
  platform="$(detect_platform)"

  case "$platform" in
    macos) install_ghostty_macos ;;
    linux) install_ghostty_linux ;;
  esac

  if ! detect_ghostty_path >/dev/null; then
    return 1
  fi

  return 0
}

configure_default_terminal() {
  local shell_rc_override="$1"

  local ghostty_path
  ghostty_path="$(detect_ghostty_path)" || {
    warn "Ghostty binary not found; cannot set as default terminal."
    return 1
  }

  export TERMINAL="$ghostty_path"
  export DEFAULT_TERMINAL="$ghostty_path"
  info "TERMINAL and DEFAULT_TERMINAL set to $ghostty_path for current session."

  local shell_rc="$shell_rc_override"
  if [ -z "$shell_rc" ]; then
    shell_rc="$(detect_shell_rc)"
  fi

  if [ -n "$shell_rc" ]; then
    persist_shell_export "$shell_rc" "TERMINAL" "$ghostty_path" "Default terminal set by lazyvim-codex bootstrap"
    persist_shell_export "$shell_rc" "DEFAULT_TERMINAL" "$ghostty_path" "Default terminal set by lazyvim-codex bootstrap"
  else
    warn "Unable to determine shell rc file to persist TERMINAL variable."
  fi

  if [ "$(detect_platform)" = "linux" ] && command_exists update-alternatives; then
    info "Registering Ghostty as default x-terminal-emulator."
    if sudo update-alternatives --install /usr/bin/x-terminal-emulator x-terminal-emulator "$ghostty_path" 70; then
      if ! sudo update-alternatives --set x-terminal-emulator "$ghostty_path"; then
        warn "Failed to select Ghostty as default via update-alternatives."
      fi
    else
      warn "Failed to register Ghostty with update-alternatives."
    fi
  fi

  return 0
}

install_codex_cli() {
  if command_exists codex; then
    info "Codex CLI already installed."
    return
  fi

  info "Installing Codex CLI globally via npm."
  if npm install -g @openai/codex; then
    info "Codex CLI installation succeeded."
    return
  fi

  if command_exists sudo && [ "$(id -u)" -ne 0 ]; then
    warn "Retrying Codex CLI installation with sudo."
    sudo npm install -g @openai/codex || error "Failed to install Codex CLI with sudo."
  else
    error "Failed to install Codex CLI. Ensure you can run 'npm install -g @openai/codex'."
  fi
}

backup_existing_nvim_config() {
  if [ -d "$NVIM_CONFIG_DIR" ]; then
    local backup_dir="${NVIM_CONFIG_DIR}-backup-$(date +%Y%m%d%H%M%S)"
    info "Backing up existing Neovim config to $backup_dir"
    mv "$NVIM_CONFIG_DIR" "$backup_dir"
  fi
}

clone_lazyvim_starter() {
  info "Cloning LazyVim starter from $LAZYVIM_REPO"
  mkdir -p "$(dirname "$NVIM_CONFIG_DIR")"
  git clone --depth=1 "$LAZYVIM_REPO" "$NVIM_CONFIG_DIR"
  rm -rf "$NVIM_CONFIG_DIR/.git"
}

write_codex_plugin_config() {
  local plugin_dir
  plugin_dir="$(dirname "$CODEX_PLUGIN_FILE")"
  mkdir -p "$plugin_dir"

  info "Writing Codex LazyVim plugin configuration to $CODEX_PLUGIN_FILE"
  cat >"$CODEX_PLUGIN_FILE" <<'EOF'
return {
  {
    "johnseth97/codex.nvim",
    main = "codex",
    event = "VeryLazy",
    cmd = { "Codex", "CodexToggle" },
    keys = {
      {
        "<leader>cc",
        function()
          require("codex").toggle()
        end,
        desc = "Toggle Codex popup",
      },
    },
    opts = {
      cmd = { "codex", "--full-access", "--dangerously-bypass-approvals-and-sandbox" },
      keymaps = {
        toggle = nil,
        quit = "<C-q>",
      },
      border = "rounded",
      width = 0.8,
      height = 0.8,
      autoinstall = true,
    },
  },
}
EOF
}

setup_openai_api_key() {
  local provided_key="$1"
  local rc_override="$2"

  if [ -z "$provided_key" ]; then
    warn "OPENAI_API_KEY not supplied. Codex will require it before first use."
    return 1
  fi

  export OPENAI_API_KEY="$provided_key"
  info "OPENAI_API_KEY exported for current session."

  local shell_rc="$rc_override"
  if [ -z "$shell_rc" ]; then
    shell_rc="$(detect_shell_rc)"
  fi

  if [ -z "$shell_rc" ]; then
    warn "Unable to determine shell rc file. Add 'export OPENAI_API_KEY=...' manually."
    return 0
  fi

  persist_shell_export "$shell_rc" "OPENAI_API_KEY" "$provided_key"
}

sync_lazyvim() {
  info "Running LazyVim plugin sync headlessly (this may take a moment)..."
  if ! command_exists nvim; then
    warn "Neovim command not found during sync step; skipping."
    return 1
  fi

  if nvim --headless "+Lazy! sync" "+qall"; then
    return 0
  fi

  warn "Neovim Lazy sync failed. Check the output above for details."
  return 1
}

print_next_steps() {
  local have_api_key="$1"
  local ran_sync="$2"
  local ghostty_ready="$3"
  local launcher_path="${4:-$LAUNCHER_SCRIPT}"

  cat <<'EOF'

Bootstrap complete!

EOF

  if [ "$have_api_key" = "no" ]; then
    cat <<'EOF'
- OPENAI_API_KEY was not configured. Export it in your shell before launching Neovim:
      export OPENAI_API_KEY="your_api_key"
  Add that line to your shell rc file to persist it.
EOF
  fi

  if [ "$ran_sync" = "no" ]; then
    cat <<'EOF'
- Neovim headless sync was skipped. Run `nvim --headless "+Lazy! sync" "+qall"` manually before first use.
EOF
  fi

  if [ "$ghostty_ready" = "no" ]; then
    cat <<'EOF'
- Ghostty is not fully configured. Install it from https://ghostty.org and set it as your default terminal if desired.
EOF
  fi

  printf -- "- Launch using \`%s\` to open Ghostty with LazyVim and Codex.\n" "$launcher_path"
  printf -- "- Workspace instructions live in %s/AGENTS.md.\n" "$LAZYVIM_CODEX_WORKDIR"
  printf -- "- Launch \`nvim\` directly anytime to reuse the configured LazyVim setup.\n"
}

auto_launch_lazyvim_codex() {
  local ghostty_path
  ghostty_path="$(detect_ghostty_path)" || {
    error "Ghostty is required for automatic launch but was not detected."
  }

  if [ ! -x "$ghostty_path" ]; then
    error "Resolved Ghostty binary at $ghostty_path is not executable."
  fi

  if [ ! -x "$LAUNCHER_SCRIPT" ]; then
    error "Launcher script at $LAUNCHER_SCRIPT is missing or not executable."
  fi

  info "Launching LazyVim Codex environment..."
  if ! "$LAUNCHER_SCRIPT"; then
    warn "Launcher exited with a non-zero status; you may need to run it manually."
    return 1
  fi

  return 0
}

main() {
  local user_api_key=""
  local shell_rc_override=""
  local run_headless_sync=1
  local ghostty_status="yes"
  local auto_launch=1

  while [ "$#" -gt 0 ]; do
    case "$1" in
      --openai-key)
        shift || error "--openai-key requires a value."
        user_api_key="${1:-}"
        ;;
      --openai-key=*)
        user_api_key="${1#*=}"
        ;;
      --shell-rc)
        shift || error "--shell-rc requires a path."
        shell_rc_override="${1:-}"
        ;;
      --shell-rc=*)
        shell_rc_override="${1#*=}"
        ;;
      --skip-headless-sync)
        run_headless_sync=0
        ;;
      --no-auto-launch)
        auto_launch=0
        ;;
      --help)
        usage
        return 0
        ;;
      *)
        error "Unknown option: $1"
        ;;
    esac
    shift || break
  done

  install_dependencies
  if ! install_ghostty; then
    error "Ghostty installation failed. Install Ghostty manually and re-run the bootstrap."
  fi

  install_codex_cli
  backup_existing_nvim_config
  clone_lazyvim_starter
  write_codex_plugin_config
  setup_lazyvim_dark_theme
  setup_codex_agent_notes
  create_launcher_script

  if detect_ghostty_path >/dev/null; then
    setup_ghostty_theme
  fi

  local resolved_api_key="${user_api_key:-${OPENAI_API_KEY:-}}"
  local api_key_status="yes"
  if ! setup_openai_api_key "$resolved_api_key" "$shell_rc_override"; then
    api_key_status="no"
  fi

  local shell_rc_path="$shell_rc_override"
  if [ -z "$shell_rc_path" ]; then
    shell_rc_path="$(detect_shell_rc)"
  fi
  if [ -n "$shell_rc_path" ]; then
    persist_shell_export "$shell_rc_path" "LAZYVIM_CODEX_WORKDIR" "$LAZYVIM_CODEX_WORKDIR" "Codex workspace set by lazyvim-codex bootstrap"
  fi
  export LAZYVIM_CODEX_WORKDIR="$LAZYVIM_CODEX_WORKDIR"

  local sync_status="yes"
  if [ "$run_headless_sync" -eq 1 ]; then
    sync_lazyvim || sync_status="no"
  else
    sync_status="no"
  fi

  if ! configure_default_terminal "$shell_rc_override"; then
    ghostty_status="no"
  fi

  print_next_steps "$api_key_status" "$sync_status" "$ghostty_status" "$LAUNCHER_SCRIPT"
  if [ "$auto_launch" -eq 1 ]; then
    if ! auto_launch_lazyvim_codex; then
      auto_launch=0
    fi
  fi
}

main "$@"
