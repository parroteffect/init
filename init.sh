#!/usr/bin/env bash
set -euo pipefail
IFS=$'\n\t'

# =============================================================================
# System Initialization Script v4.2
# - Installs: zsh, oh-my-zsh, miniconda, eza, zsh plugins
# - Theme: simplerich (customized from github.com/parroteffect/zsh-theme)
# =============================================================================

log() { echo -e "\n=== $* ==="; }

# -----------------------------------------------------------------------------
# Determine target user
# - If run with sudo, configure the invoking user (SUDO_USER)
# - Otherwise configure the current user
# -----------------------------------------------------------------------------
if [[ "${EUID}" -eq 0 && -n "${SUDO_USER:-}" && "${SUDO_USER}" != "root" ]]; then
  TARGET_USER="${SUDO_USER}"
else
  TARGET_USER="$(id -un)"
fi

TARGET_HOME="$(eval echo "~${TARGET_USER}")"
TARGET_GROUP="$(id -gn "${TARGET_USER}")"

if [[ "${EUID}" -eq 0 ]]; then
  SUDO=""
else
  SUDO="sudo"
fi

as_user() {
  if [[ "${EUID}" -eq 0 && "${TARGET_USER}" != "root" ]]; then
    sudo -u "${TARGET_USER}" -H "$@"
  else
    "$@"
  fi
}

# -----------------------------------------------------------------------------
# Install eza/exa for ls icons
# -----------------------------------------------------------------------------
install_ls_icons_tool() {
  if command -v eza >/dev/null 2>&1 || command -v exa >/dev/null 2>&1; then
    return 0
  fi

  log "Installing eza/exa (for ls icons)"

  # Try apt first
  if ${SUDO} apt install -y eza >/dev/null 2>&1; then
    echo "Installed eza via apt"
    return 0
  fi

  if ${SUDO} apt install -y exa >/dev/null 2>&1; then
    echo "Installed exa via apt (fallback)"
    return 0
  fi

  # Fallback: download from GitHub
  echo "apt couldn't install eza/exa; trying GitHub release..."

  local arch asset url tmpdir bin
  arch="$(uname -m)"

  case "${arch}" in
    x86_64|amd64)   asset="eza_x86_64-unknown-linux-gnu.tar.gz" ;;
    aarch64|arm64)  asset="eza_aarch64-unknown-linux-gnu.tar.gz" ;;
    armv7l|armv7|armhf) asset="eza_arm-unknown-linux-gnueabihf.tar.gz" ;;
    *)
      echo "Warning: unsupported architecture (${arch}). Skipping eza install."
      return 0
      ;;
  esac

  url="https://github.com/eza-community/eza/releases/latest/download/${asset}"
  tmpdir="$(mktemp -d)"

  if ! curl -LfsS --retry 8 --retry-all-errors --retry-delay 2 \
      --connect-timeout 10 --max-time 120 "${url}" -o "${tmpdir}/eza.tar.gz"; then
    echo "Warning: GitHub download failed. Skipping eza install."
    rm -rf "${tmpdir}"
    return 0
  fi

  if ! tar -xzf "${tmpdir}/eza.tar.gz" -C "${tmpdir}"; then
    echo "Warning: failed to extract eza. Skipping."
    rm -rf "${tmpdir}"
    return 0
  fi

  bin="${tmpdir}/eza"
  if [[ ! -x "${bin}" ]]; then
    bin="$(find "${tmpdir}" -maxdepth 3 -type f -name eza -perm -u+x 2>/dev/null | head -n 1 || true)"
  fi

  if [[ -z "${bin:-}" || ! -x "${bin}" ]]; then
    echo "Warning: failed to locate eza binary. Skipping."
    rm -rf "${tmpdir}"
    return 0
  fi

  ${SUDO} install -m 0755 "${bin}" /usr/local/bin/eza
  rm -rf "${tmpdir}"
  echo "Installed eza to /usr/local/bin/eza"
}

# =============================================================================
# MAIN
# =============================================================================
log "Starting system initialization"
echo "User: ${TARGET_USER}"
echo "Home: ${TARGET_HOME}"

# -----------------------------------------------------------------------------
# 1. Install packages
# -----------------------------------------------------------------------------
log "Updating package list"
${SUDO} apt update

log "Installing packages"
${SUDO} apt install -y nano zsh git curl wget ca-certificates tar bc

install_ls_icons_tool

# Check for distro-packaged zsh plugins
USE_DISTRO_PLUGINS=0
if apt-cache show zsh-autosuggestions >/dev/null 2>&1 && \
   apt-cache show zsh-syntax-highlighting >/dev/null 2>&1; then
  log "Installing zsh plugins from apt"
  ${SUDO} apt install -y zsh-autosuggestions zsh-syntax-highlighting
  USE_DISTRO_PLUGINS=1
fi

# -----------------------------------------------------------------------------
# 2. Miniconda
# -----------------------------------------------------------------------------
CONDA_DIR="${TARGET_HOME}/miniconda3"

log "Miniconda"
if [[ -d "${CONDA_DIR}" ]]; then
  echo "Already installed at ${CONDA_DIR}, skipping..."
else
  echo "Installing Miniconda..."
  CONDA_INSTALLER="Miniconda3-latest-Linux-x86_64.sh"
  wget -q "https://repo.anaconda.com/miniconda/${CONDA_INSTALLER}" -O "/tmp/${CONDA_INSTALLER}"
  as_user bash "/tmp/${CONDA_INSTALLER}" -b -p "${CONDA_DIR}"
  rm -f "/tmp/${CONDA_INSTALLER}"
  echo "Miniconda installed!"
fi

# -----------------------------------------------------------------------------
# 3. Oh My Zsh
# -----------------------------------------------------------------------------
log "Oh My Zsh"
if [[ -d "${TARGET_HOME}/.oh-my-zsh" ]]; then
  echo "Already installed, skipping..."
else
  echo "Installing Oh My Zsh..."
  as_user env RUNZSH=no CHSH=no HOME="${TARGET_HOME}" \
    sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)" "" --unattended
fi

ZSH_CUSTOM="${TARGET_HOME}/.oh-my-zsh/custom"

# -----------------------------------------------------------------------------
# 4. Simplerich ZSH Theme (customized)
# -----------------------------------------------------------------------------
log "Simplerich theme"
SIMPLERICH_DIR="${ZSH_CUSTOM}/themes/simplerich-zsh-theme"

# Always fresh clone to get latest version
if [[ -d "${SIMPLERICH_DIR}" ]]; then
  echo "Removing old version..."
  rm -rf "${SIMPLERICH_DIR}"
fi

as_user git clone --recursive --depth=1 https://github.com/parroteffect/zsh-theme "${SIMPLERICH_DIR}"
as_user cp "${SIMPLERICH_DIR}/simplerich.zsh-theme" "${TARGET_HOME}/.oh-my-zsh/themes/"
echo "Theme installed!"

# -----------------------------------------------------------------------------
# 5. ZSH Plugins (if not installed via apt)
# -----------------------------------------------------------------------------
if [[ "${USE_DISTRO_PLUGINS}" -eq 0 ]]; then
  log "Installing zsh plugins via git"
  as_user mkdir -p "${ZSH_CUSTOM}/plugins"

  if [[ ! -d "${ZSH_CUSTOM}/plugins/zsh-autosuggestions" ]]; then
    as_user git clone --depth=1 https://github.com/zsh-users/zsh-autosuggestions \
      "${ZSH_CUSTOM}/plugins/zsh-autosuggestions"
  else
    echo "zsh-autosuggestions already installed"
  fi

  if [[ ! -d "${ZSH_CUSTOM}/plugins/zsh-syntax-highlighting" ]]; then
    as_user git clone --depth=1 https://github.com/zsh-users/zsh-syntax-highlighting \
      "${ZSH_CUSTOM}/plugins/zsh-syntax-highlighting"
  else
    echo "zsh-syntax-highlighting already installed"
  fi
fi

# -----------------------------------------------------------------------------
# 6. Configure .zshrc
# -----------------------------------------------------------------------------
log "Configuring .zshrc"

if [[ -f "${TARGET_HOME}/.zshrc" ]]; then
  cp "${TARGET_HOME}/.zshrc" "${TARGET_HOME}/.zshrc.backup.$(date +%s)"
fi

TMP_ZSHRC="/tmp/zshrc.${TARGET_USER}.$$"
cat > "${TMP_ZSHRC}" <<'ZSHRC_EOF'
# ==== Oh My Zsh ====
export ZSH="$HOME/.oh-my-zsh"
ZSH_THEME="simplerich"
plugins=(git)

# Simplerich theme requires zsh-git-prompt BEFORE oh-my-zsh
if [[ -r "$ZSH/custom/themes/simplerich-zsh-theme/zsh-git-prompt/zshrc.sh" ]]; then
  source "$ZSH/custom/themes/simplerich-zsh-theme/zsh-git-prompt/zshrc.sh"
fi

source "$ZSH/oh-my-zsh.sh"

# ==== ls with icons (eza/exa) ====
if command -v eza >/dev/null 2>&1; then
  alias ls='eza --icons=auto'
  alias ll='eza -al --icons=auto --group-directories-first'
  alias la='eza -a --icons=auto'
  alias lt='eza -T --icons=auto'
elif command -v exa >/dev/null 2>&1; then
  alias ls='exa --icons'
  alias ll='exa -al --icons --group-directories-first'
  alias la='exa -a --icons'
  alias lt='exa -T --icons'
fi

# ==== ZSH Plugins ====
export ZSH_AUTOSUGGEST_USE_ASYNC=0

# Autosuggestions
if [[ -r /usr/share/zsh-autosuggestions/zsh-autosuggestions.zsh ]]; then
  source /usr/share/zsh-autosuggestions/zsh-autosuggestions.zsh
elif [[ -r "$ZSH/custom/plugins/zsh-autosuggestions/zsh-autosuggestions.zsh" ]]; then
  source "$ZSH/custom/plugins/zsh-autosuggestions/zsh-autosuggestions.zsh"
fi

# Syntax highlighting (must be last)
if [[ -r /usr/share/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh ]]; then
  source /usr/share/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh
elif [[ -r "$ZSH/custom/plugins/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh" ]]; then
  source "$ZSH/custom/plugins/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh"
fi
ZSHRC_EOF

${SUDO} install -m 0644 -o "${TARGET_USER}" -g "${TARGET_GROUP}" "${TMP_ZSHRC}" "${TARGET_HOME}/.zshrc"
rm -f "${TMP_ZSHRC}"

# -----------------------------------------------------------------------------
# 7. Conda initialization
# -----------------------------------------------------------------------------
log "Initializing conda"
as_user "${CONDA_DIR}/bin/conda" init bash >/dev/null || true
as_user "${CONDA_DIR}/bin/conda" init zsh  >/dev/null || true
as_user "${CONDA_DIR}/bin/conda" config --set auto_activate_base true >/dev/null || true
as_user "${CONDA_DIR}/bin/conda" config --set changeps1 false >/dev/null || true

# -----------------------------------------------------------------------------
# 8. Set default shell
# -----------------------------------------------------------------------------
log "Setting zsh as default shell"
ZSH_BIN="$(command -v zsh)"
if [[ "${EUID}" -eq 0 ]]; then
  chsh -s "${ZSH_BIN}" "${TARGET_USER}"
else
  ${SUDO} chsh -s "${ZSH_BIN}" "${TARGET_USER}"
fi

# -----------------------------------------------------------------------------
# 9. Verification script
# -----------------------------------------------------------------------------
log "Creating verification script"
cat > /tmp/verify_setup.sh <<'VERIFY_EOF'
#!/usr/bin/env zsh
set -e
echo "Verifying installation..."
echo "  ✓ Zsh: $(zsh --version)"
echo "  ✓ Oh My Zsh: $([ -d ~/.oh-my-zsh ] && echo 'Installed' || echo 'Not found')"
echo "  ✓ Conda: $(command -v conda >/dev/null && conda --version || echo 'Not found')"
echo "  ✓ eza: $(command -v eza >/dev/null && eza --version | head -1 || echo 'Not found')"
echo "  ✓ Theme: $(grep '^ZSH_THEME=' ~/.zshrc 2>/dev/null || echo 'Not set')"
echo "  ✓ Simplerich: $([ -d ~/.oh-my-zsh/custom/themes/simplerich-zsh-theme ] && echo 'Installed' || echo 'Not found')"
VERIFY_EOF
chmod +x /tmp/verify_setup.sh

# -----------------------------------------------------------------------------
# Done
# -----------------------------------------------------------------------------
log "Setup complete"
echo "✅ Done!"
echo ""
echo "Next steps:"
echo "  1. Restart shell: exec zsh"
echo "  2. Verify: /tmp/verify_setup.sh"
echo ""
echo "Note: Icons require a Nerd Font in your terminal."
