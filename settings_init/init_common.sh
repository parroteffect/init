#!/usr/bin/env bash
set -euo pipefail
IFS=$'\n\t'

# =============================================================================
# System Initialization Script v4.4
# - Installs: zsh, oh-my-zsh, miniconda, nvm + Node.js LTS, eza/exa, zellij,
#             neovim (+ file tree, tabs, search, LSP/autocomplete, treesitter,
#             git signs, image/PDF viewing), tree-sitter CLI,
#             win32yank + hangul-ime (WSL), zsh-autosuggestions, zsh-syntax-highlighting
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
  echo "apt could not install eza/exa; trying GitHub release..."

  local arch asset url tmpdir bin
  arch="$(uname -m)"

  case "${arch}" in
    x86_64|amd64) asset="eza_x86_64-unknown-linux-gnu.tar.gz" ;;
    aarch64|arm64) asset="eza_aarch64-unknown-linux-gnu.tar.gz" ;;
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

# -----------------------------------------------------------------------------
# Install zellij (terminal multiplexer) from the latest GitHub release
# -----------------------------------------------------------------------------
install_zellij() {
  if command -v zellij >/dev/null 2>&1; then
    echo "zellij already installed, skipping..."
    return 0
  fi

  log "Installing zellij"

  local arch asset url tmpdir bin
  arch="$(uname -m)"

  case "${arch}" in
    x86_64|amd64) asset="zellij-x86_64-unknown-linux-musl.tar.gz" ;;
    aarch64|arm64) asset="zellij-aarch64-unknown-linux-musl.tar.gz" ;;
    *)
      echo "Warning: unsupported architecture (${arch}). Skipping zellij install."
      return 0
      ;;
  esac

  url="https://github.com/zellij-org/zellij/releases/latest/download/${asset}"
  tmpdir="$(mktemp -d)"

  if ! curl -LfsS --retry 8 --retry-all-errors --retry-delay 2 \
      --connect-timeout 10 --max-time 180 "${url}" -o "${tmpdir}/zellij.tar.gz"; then
    echo "Warning: GitHub download failed. Skipping zellij install."
    rm -rf "${tmpdir}"
    return 0
  fi

  if ! tar -xzf "${tmpdir}/zellij.tar.gz" -C "${tmpdir}"; then
    echo "Warning: failed to extract zellij. Skipping."
    rm -rf "${tmpdir}"
    return 0
  fi

  bin="${tmpdir}/zellij"
  if [[ ! -x "${bin}" ]]; then
    bin="$(find "${tmpdir}" -maxdepth 3 -type f -name zellij 2>/dev/null | head -n 1 || true)"
  fi

  if [[ -z "${bin:-}" || ! -f "${bin}" ]]; then
    echo "Warning: failed to locate zellij binary. Skipping."
    rm -rf "${tmpdir}"
    return 0
  fi

  ${SUDO} install -m 0755 "${bin}" /usr/local/bin/zellij
  rm -rf "${tmpdir}"
  echo "Installed zellij to /usr/local/bin/zellij"
}

# -----------------------------------------------------------------------------
# Install Neovim from the latest GitHub release
# - apt ships an old version (0.9.x on Ubuntu 24.04); nvim-treesitter needs >= 0.12
# - Installs to /opt/nvim and links /usr/local/bin/nvim
# -----------------------------------------------------------------------------
NVIM_MIN_VERSION="0.12"

install_neovim() {
  local current
  if command -v nvim >/dev/null 2>&1; then
    current="$(nvim --version | head -n 1 | sed -E 's/^NVIM v([0-9]+\.[0-9]+).*/\1/')"
    if [[ "$(printf '%s\n' "${NVIM_MIN_VERSION}" "${current}" | sort -V | head -n 1)" == "${NVIM_MIN_VERSION}" ]]; then
      echo "Neovim ${current} already installed, skipping..."
      return 0
    fi
    echo "Neovim ${current} is older than ${NVIM_MIN_VERSION}; installing latest release..."
  fi

  log "Installing Neovim"

  local arch asset url tmpdir
  arch="$(uname -m)"

  case "${arch}" in
    x86_64|amd64) asset="nvim-linux-x86_64" ;;
    aarch64|arm64) asset="nvim-linux-arm64" ;;
    *)
      echo "Warning: unsupported architecture (${arch}). Skipping Neovim install."
      return 0
      ;;
  esac

  url="https://github.com/neovim/neovim/releases/latest/download/${asset}.tar.gz"
  tmpdir="$(mktemp -d)"

  if ! curl -LfsS --retry 8 --retry-all-errors --retry-delay 2 \
      --connect-timeout 10 --max-time 300 "${url}" -o "${tmpdir}/nvim.tar.gz"; then
    echo "Warning: GitHub download failed. Skipping Neovim install."
    rm -rf "${tmpdir}"
    return 0
  fi

  if ! tar -xzf "${tmpdir}/nvim.tar.gz" -C "${tmpdir}"; then
    echo "Warning: failed to extract Neovim. Skipping."
    rm -rf "${tmpdir}"
    return 0
  fi

  # Make sure the binary actually runs here (e.g. glibc too old) before replacing anything
  if ! "${tmpdir}/${asset}/bin/nvim" --version >/dev/null 2>&1; then
    echo "Warning: downloaded Neovim does not run on this system. Skipping."
    rm -rf "${tmpdir}"
    return 0
  fi

  ${SUDO} rm -rf /opt/nvim
  ${SUDO} cp -r "${tmpdir}/${asset}" /opt/nvim
  ${SUDO} ln -sf /opt/nvim/bin/nvim /usr/local/bin/nvim
  rm -rf "${tmpdir}"
  echo "Installed $(/opt/nvim/bin/nvim --version | head -n 1) to /opt/nvim"
}

# -----------------------------------------------------------------------------
# Install win32yank (WSL only): clipboard bridge between Neovim and Windows
# - Handles UTF-8 (Korean) and CRLF line endings correctly
# - Neovim picks it up automatically from PATH
# -----------------------------------------------------------------------------
install_win32yank() {
  if ! grep -qi microsoft /proc/version 2>/dev/null; then
    return 0
  fi

  if command -v win32yank.exe >/dev/null 2>&1; then
    echo "win32yank already installed, skipping..."
    return 0
  fi

  log "Installing win32yank (WSL clipboard for Neovim)"

  local url tmpdir
  url="https://github.com/equalsraf/win32yank/releases/download/v0.1.1/win32yank-x64.zip"
  tmpdir="$(mktemp -d)"

  if ! curl -LfsS --retry 8 --retry-all-errors --retry-delay 2 \
      --connect-timeout 10 --max-time 120 "${url}" -o "${tmpdir}/win32yank.zip"; then
    echo "Warning: GitHub download failed. Skipping win32yank install."
    rm -rf "${tmpdir}"
    return 0
  fi

  if ! unzip -o -q "${tmpdir}/win32yank.zip" win32yank.exe -d "${tmpdir}"; then
    echo "Warning: failed to extract win32yank. Skipping."
    rm -rf "${tmpdir}"
    return 0
  fi

  ${SUDO} install -m 0755 "${tmpdir}/win32yank.exe" /usr/local/bin/win32yank.exe
  rm -rf "${tmpdir}"
  echo "Installed win32yank to /usr/local/bin/win32yank.exe"
}

# -----------------------------------------------------------------------------
# Build hangul-ime.exe (WSL only): Neovim calls it when leaving insert mode so
# the Windows Korean IME goes back to English and j/k/dd ... work right away.
# - Compiled from the C# source below with the compiler that ships with Windows
#   (.NET Framework 4), so no prebuilt binary is downloaded
# - `hangul-ime.exe en` presses the Han/Eng key only if the IME is in Hangul mode;
#   `hangul-ime.exe status` prints what it sees (for troubleshooting)
# -----------------------------------------------------------------------------
HANGUL_IME_VERSION="1"

install_hangul_ime() {
  if ! grep -qi microsoft /proc/version 2>/dev/null; then
    return 0
  fi

  if [[ -x /usr/local/bin/hangul-ime.exe ]] && [[ "$(/usr/local/bin/hangul-ime.exe version 2>/dev/null \
      | tr -d '\r')" == "hangul-ime ${HANGUL_IME_VERSION}" ]]; then
    echo "hangul-ime already installed, skipping..."
    return 0
  fi

  log "Building hangul-ime (Korean IME auto-switch for Neovim)"

  local csc tmpdir out
  csc="/mnt/c/Windows/Microsoft.NET/Framework64/v4.0.30319/csc.exe"
  if [[ ! -x "${csc}" ]]; then
    echo "Warning: Windows C# compiler not found (${csc}). Skipping hangul-ime."
    return 0
  fi

  tmpdir="$(as_user mktemp -d)"
  as_user tee "${tmpdir}/hangul-ime.cs" >/dev/null <<'CS_EOF'
// hangul-ime: switch the Windows Korean IME of the foreground window to English.
using System;
using System.Runtime.InteropServices;
using System.Text;

static class HangulIme
{
    const uint WM_IME_CONTROL = 0x0283;
    const int IMC_GETCONVERSIONMODE = 0x0001;
    const int IMC_GETOPENSTATUS = 0x0005;
    const int IME_CMODE_HANGUL = 0x0001;
    const ushort VK_HANGUL = 0x15;
    const uint KEYEVENTF_KEYUP = 0x0002;
    const uint SMTO_ABORTIFHUNG = 0x0002;

    [StructLayout(LayoutKind.Sequential)]
    struct RECT { public int Left, Top, Right, Bottom; }

    [StructLayout(LayoutKind.Sequential)]
    struct GUITHREADINFO
    {
        public int cbSize, flags;
        public IntPtr hwndActive, hwndFocus, hwndCapture, hwndMenuOwner, hwndMoveSize, hwndCaret;
        public RECT rcCaret;
    }

    [StructLayout(LayoutKind.Sequential)]
    struct KEYBDINPUT { public ushort wVk, wScan; public uint dwFlags, time; public IntPtr dwExtraInfo; }

    [StructLayout(LayoutKind.Sequential)]
    struct MOUSEINPUT { public int dx, dy; public uint mouseData, dwFlags, time; public IntPtr dwExtraInfo; }

    [StructLayout(LayoutKind.Explicit)]
    struct InputUnion { [FieldOffset(0)] public MOUSEINPUT mi; [FieldOffset(0)] public KEYBDINPUT ki; }

    [StructLayout(LayoutKind.Sequential)]
    struct INPUT { public uint type; public InputUnion u; }

    [DllImport("user32.dll")] static extern IntPtr GetForegroundWindow();
    [DllImport("user32.dll")] static extern uint GetWindowThreadProcessId(IntPtr hWnd, IntPtr pid);
    [DllImport("user32.dll")] static extern bool GetGUIThreadInfo(uint tid, ref GUITHREADINFO info);
    [DllImport("user32.dll", CharSet = CharSet.Unicode)] static extern int GetClassName(IntPtr hWnd, StringBuilder buf, int max);
    [DllImport("user32.dll")] static extern IntPtr SendMessageTimeout(IntPtr hWnd, uint msg, IntPtr wParam, IntPtr lParam, uint flags, uint timeout, out IntPtr result);
    [DllImport("user32.dll")] static extern uint SendInput(uint n, INPUT[] inputs, int size);
    [DllImport("user32.dll")] static extern uint MapVirtualKey(uint code, uint mapType);
    [DllImport("imm32.dll")] static extern IntPtr ImmGetDefaultIMEWnd(IntPtr hWnd);

    // IME window of the control that has keyboard focus in the foreground app
    static IntPtr ImeWindow(out IntPtr foreground)
    {
        foreground = GetForegroundWindow();
        if (foreground == IntPtr.Zero) return IntPtr.Zero;
        IntPtr target = foreground;
        var gti = new GUITHREADINFO();
        gti.cbSize = Marshal.SizeOf(typeof(GUITHREADINFO));
        if (GetGUIThreadInfo(GetWindowThreadProcessId(foreground, IntPtr.Zero), ref gti) && gti.hwndFocus != IntPtr.Zero)
            target = gti.hwndFocus;
        return ImmGetDefaultIMEWnd(target);
    }

    static long Query(IntPtr ime, int command)
    {
        IntPtr result;
        if (SendMessageTimeout(ime, WM_IME_CONTROL, (IntPtr)command, IntPtr.Zero, SMTO_ABORTIFHUNG, 200, out result) == IntPtr.Zero)
            return -1;
        return result.ToInt64();
    }

    static void PressHangulKey()
    {
        var inputs = new INPUT[2];
        ushort scan = (ushort)MapVirtualKey(VK_HANGUL, 0);
        for (int i = 0; i < 2; i++)
        {
            inputs[i].type = 1; // INPUT_KEYBOARD
            inputs[i].u.ki.wVk = VK_HANGUL;
            inputs[i].u.ki.wScan = scan;
            inputs[i].u.ki.dwFlags = i == 0 ? 0 : KEYEVENTF_KEYUP;
        }
        SendInput(2, inputs, Marshal.SizeOf(typeof(INPUT)));
    }

    static int Main(string[] args)
    {
        string cmd = args.Length > 0 ? args[0] : "";
        if (cmd == "version")
        {
            Console.WriteLine("hangul-ime 1");
            return 0;
        }

        IntPtr foreground;
        IntPtr ime = ImeWindow(out foreground);
        if (ime == IntPtr.Zero) return 2;
        long conv = Query(ime, IMC_GETCONVERSIONMODE);
        bool hangul = conv >= 0 && (conv & IME_CMODE_HANGUL) != 0;

        if (cmd == "status")
        {
            var cls = new StringBuilder(256);
            GetClassName(foreground, cls, cls.Capacity);
            Console.WriteLine("window={0} conversion={1} open={2} -> {3}",
                cls, conv, Query(ime, IMC_GETOPENSTATUS), hangul ? "hangul" : "english");
            return 0;
        }
        if (cmd == "en")
        {
            if (hangul) PressHangulKey();
            return 0;
        }
        Console.Error.WriteLine("usage: hangul-ime.exe en|status|version");
        return 1;
    }
}
CS_EOF

  if ! out="$(cd "${tmpdir}" && as_user "${csc}" /nologo /optimize /target:exe \
      /out:hangul-ime.exe hangul-ime.cs 2>&1)" || [[ ! -f "${tmpdir}/hangul-ime.exe" ]]; then
    echo "${out}"
    echo "Warning: failed to build hangul-ime. Skipping."
    rm -rf "${tmpdir}"
    return 0
  fi

  ${SUDO} install -m 0755 "${tmpdir}/hangul-ime.exe" /usr/local/bin/hangul-ime.exe
  rm -rf "${tmpdir}"
  echo "Installed hangul-ime to /usr/local/bin/hangul-ime.exe"
}

# -----------------------------------------------------------------------------
# Install tree-sitter CLI from the latest GitHub release
# - nvim-treesitter uses it to build language parsers (accurate syntax colors)
# - nvim-treesitter needs >= 0.26.1 and warns against the npm package
# -----------------------------------------------------------------------------
TREE_SITTER_MIN_VERSION="0.26.1"

install_tree_sitter_cli() {
  local current
  if command -v tree-sitter >/dev/null 2>&1; then
    current="$(tree-sitter --version 2>/dev/null | awk '{print $2}')"
    if [[ -n "${current}" && "$(printf '%s\n' "${TREE_SITTER_MIN_VERSION}" "${current}" \
        | sort -V | head -n 1)" == "${TREE_SITTER_MIN_VERSION}" ]]; then
      echo "tree-sitter CLI ${current} already installed, skipping..."
      return 0
    fi
  fi

  log "Installing tree-sitter CLI"

  local arch asset url tmpdir
  arch="$(uname -m)"

  case "${arch}" in
    x86_64|amd64) asset="tree-sitter-linux-x64" ;;
    aarch64|arm64) asset="tree-sitter-linux-arm64" ;;
    *)
      echo "Warning: unsupported architecture (${arch}). Skipping tree-sitter CLI install."
      return 0
      ;;
  esac

  url="https://github.com/tree-sitter/tree-sitter/releases/latest/download/${asset}.gz"
  tmpdir="$(mktemp -d)"

  if ! curl -LfsS --retry 8 --retry-all-errors --retry-delay 2 \
      --connect-timeout 10 --max-time 180 "${url}" -o "${tmpdir}/tree-sitter.gz"; then
    echo "Warning: GitHub download failed. Skipping tree-sitter CLI install."
    rm -rf "${tmpdir}"
    return 0
  fi

  # Make sure the binary actually runs here (it needs a recent glibc)
  if ! gunzip "${tmpdir}/tree-sitter.gz" || ! chmod +x "${tmpdir}/tree-sitter" \
      || ! "${tmpdir}/tree-sitter" --version >/dev/null 2>&1; then
    echo "Warning: downloaded tree-sitter CLI does not run on this system. Skipping."
    rm -rf "${tmpdir}"
    return 0
  fi

  ${SUDO} install -m 0755 "${tmpdir}/tree-sitter" /usr/local/bin/tree-sitter
  rm -rf "${tmpdir}"
  echo "Installed $(/usr/local/bin/tree-sitter --version) to /usr/local/bin/tree-sitter"
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
# libatomic1: required by recent Node.js builds installed via nvm (v26+)
${SUDO} apt install -y nano zsh git curl wget ca-certificates tar bc libatomic1

install_ls_icons_tool
install_zellij
install_neovim

# Neovim plugin dependencies:
#   imagemagick -> image.nvim (decode/resize, sixel encoding)
#   mupdf-tools -> pdf-view.nvim (mutool renders PDF pages)
#   unzip       -> win32yank install
#   ripgrep, fd-find -> telescope.nvim (search text, find files)
#   build-essential  -> compiles telescope-fzf-native and treesitter parsers
#                       (and C/C++ work in general)
#   shellcheck       -> bash-language-server uses it to catch shell script mistakes
#   python3-venv     -> Mason installs Python-based language servers into a venv
${SUDO} apt install -y imagemagick mupdf-tools unzip ripgrep fd-find build-essential \
  shellcheck python3-venv
install_win32yank
install_hangul_ime
install_tree_sitter_cli

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
# 2b. nvm + Node.js LTS (npm bundled)
# -----------------------------------------------------------------------------
NVM_DIR="${TARGET_HOME}/.nvm"

log "nvm + Node.js"
if [[ -d "${NVM_DIR}" ]]; then
  echo "nvm already installed at ${NVM_DIR}, skipping install..."
else
  echo "Installing nvm..."
  as_user env HOME="${TARGET_HOME}" PROFILE=/dev/null \
    bash -c "$(curl -fsSL https://raw.githubusercontent.com/nvm-sh/nvm/v0.40.1/install.sh)"
fi

echo "Installing latest LTS Node.js..."
as_user env HOME="${TARGET_HOME}" NVM_DIR="${NVM_DIR}" bash -c '
  set -e
  . "$NVM_DIR/nvm.sh"
  nvm install --lts
  nvm alias default "lts/*"
  echo "node: $(node -v), npm: $(npm -v)"
'

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

as_user mkdir -p "${ZSH_CUSTOM}/themes"
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
# ==== PATH ====
# User-local binaries (claude, pipx, etc.); zsh does not read ~/.profile
export PATH="$HOME/.local/bin:$PATH"

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

# ==== nvm (Node Version Manager) ====
export NVM_DIR="$HOME/.nvm"
[[ -s "$NVM_DIR/nvm.sh" ]] && source "$NVM_DIR/nvm.sh"
[[ -s "$NVM_DIR/bash_completion" ]] && source "$NVM_DIR/bash_completion"

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
if [[ -x "${CONDA_DIR}/bin/conda" ]]; then
  as_user "${CONDA_DIR}/bin/conda" init bash >/dev/null || true
  as_user "${CONDA_DIR}/bin/conda" init zsh  >/dev/null || true
  as_user "${CONDA_DIR}/bin/conda" config --set auto_activate_base true >/dev/null || true
  as_user "${CONDA_DIR}/bin/conda" config --set changeps1 false >/dev/null || true
else
  echo "Warning: conda not found at ${CONDA_DIR}/bin/conda; skipping conda init."
fi

# -----------------------------------------------------------------------------
# 7b. Neovim config (~/.config/nvim/init.lua)
# - VS Code-like: file tree, tabs, file/text search, LSP + autocomplete,
#   treesitter colors, git change marks, image/PDF viewing (lazy.nvim plugins)
# - Graphics: kitty protocol on kitty/Ghostty, sixel elsewhere (Windows Terminal >= 1.22)
# -----------------------------------------------------------------------------
log "Configuring Neovim"
NVIM_CONFIG_DIR="${TARGET_HOME}/.config/nvim"
as_user mkdir -p "${NVIM_CONFIG_DIR}"

if [[ -f "${NVIM_CONFIG_DIR}/init.lua" ]]; then
  as_user cp "${NVIM_CONFIG_DIR}/init.lua" "${NVIM_CONFIG_DIR}/init.lua.backup.$(date +%s)"
fi

as_user tee "${NVIM_CONFIG_DIR}/init.lua" >/dev/null <<'NVIM_EOF'
-- =============================================================================
-- Neovim config (generated by init_common.sh; edit the script, not this file)
-- =============================================================================

-- ==== Options ====
vim.g.mapleader = " "
vim.opt.number = true
vim.opt.mouse = "a"
vim.opt.termguicolors = true
vim.opt.ignorecase = true
vim.opt.smartcase = true
vim.opt.undofile = true
vim.opt.confirm = true -- :q with unsaved changes asks to save instead of failing
vim.opt.laststatus = 3 -- one status line at the bottom (like VS Code)
vim.opt.signcolumn = "yes" -- keep the error-marker column so text does not shift

-- `nvim .` leaves an empty [No Name] buffer behind; drop it once a real file is opened
vim.api.nvim_create_autocmd("BufReadPost", {
  callback = function(ev)
    vim.schedule(function()
      for _, b in ipairs(vim.api.nvim_list_bufs()) do
        if b ~= ev.buf and vim.api.nvim_buf_is_valid(b) and vim.bo[b].buflisted
          and vim.api.nvim_buf_get_name(b) == "" and vim.bo[b].buftype == ""
          and not vim.bo[b].modified and vim.api.nvim_buf_line_count(b) == 1
          and vim.api.nvim_buf_get_lines(b, 0, 1, false)[1] == ""
          and #vim.fn.win_findbuf(b) == 0 then
          vim.api.nvim_buf_delete(b, {})
        end
      end
    end)
  end,
})

-- ==== Clipboard ====
-- y/p share the system clipboard (WSL: win32yank.exe). Deferred because
-- clipboard detection scans PATH, which is slow on WSL.
vim.schedule(function()
  if vim.fn.has("clipboard") == 1 then
    vim.opt.clipboard = "unnamedplus"
  end
end)

-- ==== Reload files changed outside nvim (Claude Code, git checkout, ...) ====
-- Unsaved edits are never thrown away: nvim asks first if both sides changed.
vim.api.nvim_create_autocmd({ "FocusGained", "BufEnter", "CursorHold" }, {
  callback = function()
    if vim.fn.mode() ~= "c" and vim.fn.getcmdwintype() == "" then
      vim.cmd("checktime")
    end
  end,
})
vim.api.nvim_create_autocmd("FileChangedShellPost", {
  callback = function(ev)
    vim.notify("바깥에서 바뀐 파일을 다시 불러왔어요: " .. vim.fn.fnamemodify(ev.file, ":t"))
  end,
})

-- ==== Korean IME: back to English when leaving insert mode (WSL) ====
-- hangul-ime.exe (built by init_common.sh) presses Han/Eng only if Hangul is on,
-- so j/k/dd ... work right after Esc even if you were typing Korean.
local hangul_ime = "/usr/local/bin/hangul-ime.exe"
if (vim.uv or vim.loop).fs_stat(hangul_ime) then
  local function ime_to_english()
    pcall(vim.system, { hangul_ime, "en" }) -- async, does not block typing
  end
  vim.api.nvim_create_autocmd({ "InsertLeave", "CmdlineLeave" }, { callback = ime_to_english })
  vim.api.nvim_create_autocmd("FocusGained", { -- coming back from another app
    callback = function()
      if not vim.api.nvim_get_mode().mode:match("^[iRct]") then ime_to_english() end
    end,
  })
end

-- ==== Keymaps (descriptions show up in the Space popup) ====
vim.keymap.set({ "n", "i", "x" }, "<C-s>", "<Cmd>write<CR>", { desc = "저장" })

-- Undo (u) in smaller steps: break the undo block at , . ; while typing
for _, ch in ipairs({ ",", ".", ";" }) do
  vim.keymap.set("i", ch, ch .. "<C-g>u")
end

-- Close a tab (buffer) like VS Code: if it has unsaved changes, ask
-- Save / Don't save / Cancel. Keeps the window layout (mini.bufremove).
local function close_buffer(buf)
  if buf == nil or buf == 0 then buf = vim.api.nvim_get_current_buf() end
  local force = false
  if vim.bo[buf].modified then
    local name = vim.fn.fnamemodify(vim.api.nvim_buf_get_name(buf), ":t")
    local choice = vim.fn.confirm(
      ("'%s' 변경 내용을 저장할까요?"):format(name ~= "" and name or "[No Name]"),
      "&Yes 저장\n&No 저장 안 함\n&Cancel 취소", 1)
    if choice == 1 then
      local ok, err = pcall(vim.api.nvim_buf_call, buf, function() vim.cmd("silent write") end)
      if not ok then
        vim.notify("저장 실패: " .. tostring(err), vim.log.levels.ERROR)
        return
      end
      vim.cmd("redraw") -- clear the prompt so no "Press ENTER" appears
      vim.api.nvim_echo({ { "저장됨: " .. name } }, false, {})
    elseif choice == 2 then
      force = true
    else
      return
    end
  end
  require("mini.bufremove").delete(buf, force)
end

-- ==== Code intelligence (LSP): errors, go to definition, rename ... ====
vim.diagnostic.config({
  virtual_text = { spacing = 2, prefix = "●" }, -- show the message at the end of the line
  severity_sort = true,
  float = { border = "rounded", source = true },
})

vim.api.nvim_create_autocmd("LspAttach", {
  callback = function(ev)
    local client = vim.lsp.get_client_by_id(ev.data.client_id)
    -- Python gets two servers; let basedpyright answer hover (K), not ruff
    if client and client.name == "ruff" then
      client.server_capabilities.hoverProvider = false
    end

    local function map(lhs, rhs, desc)
      vim.keymap.set("n", lhs, rhs, { buffer = ev.buf, desc = desc })
    end
    -- one result: jump straight there; several: pick from a popup
    map("gd", "<Cmd>Telescope lsp_definitions<CR>", "정의로 이동")
    map("<F12>", "<Cmd>Telescope lsp_definitions<CR>", "정의로 이동")
    map("<S-F12>", "<Cmd>Telescope lsp_references<CR>", "사용하는 곳 찾기")
    map("<F2>", vim.lsp.buf.rename, "이름 바꾸기")
    map("K", function() vim.lsp.buf.hover({ border = "rounded" }) end, "설명 보기")
    map("<leader>ca", vim.lsp.buf.code_action, "빠른 수정 (코드 액션)")
    map("<leader>cr", vim.lsp.buf.rename, "이름 바꾸기")
    map("<leader>cu", "<Cmd>Telescope lsp_references<CR>", "사용하는 곳 찾기")
    map("<leader>cd", vim.diagnostic.open_float, "이 줄의 에러 보기")
    map("<leader>cD", "<Cmd>Telescope diagnostics<CR>", "전체 에러 목록")
    map("<leader>cs", "<Cmd>Telescope lsp_document_symbols<CR>", "이 파일의 함수/클래스 목록")
    map("<leader>cf", function() vim.lsp.buf.format({ async = true }) end, "코드 정리 (포맷)")
  end,
})

-- ==== lazy.nvim (plugin manager) ====
local lazypath = vim.fn.stdpath("data") .. "/lazy/lazy.nvim"
if not (vim.uv or vim.loop).fs_stat(lazypath) then
  local out = vim.fn.system({
    "git", "clone", "--filter=blob:none", "--branch=stable",
    "https://github.com/folke/lazy.nvim.git", lazypath,
  })
  if vim.v.shell_error ~= 0 then
    vim.api.nvim_echo({ { "Failed to clone lazy.nvim:\n" .. out, "ErrorMsg" } }, true, {})
    return
  end
end
vim.opt.rtp:prepend(lazypath)

-- Kitty graphics protocol (kitty, Ghostty) is the best path; otherwise use sixel
-- (Windows Terminal >= 1.22 under WSL).
local function has_kitty_graphics()
  local term = vim.env.TERM or ""
  return vim.env.KITTY_WINDOW_ID ~= nil
    or vim.env.GHOSTTY_RESOURCES_DIR ~= nil
    or term:match("kitty") ~= nil
    or term:match("ghostty") ~= nil
end

require("lazy").setup({
  spec = {
    -- ---- Space popup: lists the available shortcuts ----
    {
      "folke/which-key.nvim",
      event = "VeryLazy",
      opts = {
        spec = {
          { "<leader>b", group = "탭" },
          { "<leader>c", group = "코드" },
          { "<leader>f", group = "찾기" },
          { "<leader>g", group = "Git" },
          { "<leader>u", group = "켜기/끄기" },
        },
      },
    },

    -- ---- File tree on the left (like VS Code's Explorer) ----
    {
      "nvim-neo-tree/neo-tree.nvim",
      branch = "v3.x",
      dependencies = {
        "nvim-lua/plenary.nvim",
        "MunifTanjim/nui.nvim",
        "nvim-tree/nvim-web-devicons",
      },
      lazy = false, -- `nvim .` opens the tree
      keys = {
        { "<C-b>", "<Cmd>Neotree toggle<CR>", desc = "파일 트리 열기/닫기" },
        { "<leader>e", "<Cmd>Neotree focus<CR>", desc = "파일 트리로 이동" },
      },
      opts = {
        close_if_last_window = true, -- closing the last file also closes the tree
        window = { width = 32 },
        filesystem = {
          follow_current_file = { enabled = true }, -- highlight the open file
          use_libuv_file_watcher = true, -- refresh when files change on disk
          filtered_items = { hide_dotfiles = false, hide_gitignored = false },
          hijack_netrw_behavior = "open_default",
        },
      },
    },

    -- ---- Tabs on top (one per open file) ----
    { "nvim-mini/mini.bufremove", version = "*" }, -- close a file, keep the layout
    {
      "akinsho/bufferline.nvim",
      version = "*",
      dependencies = { "nvim-tree/nvim-web-devicons", "nvim-mini/mini.bufremove" },
      lazy = false,
      keys = {
        { "<S-l>", "<Cmd>BufferLineCycleNext<CR>", desc = "다음 탭" },
        { "<S-h>", "<Cmd>BufferLineCyclePrev<CR>", desc = "이전 탭" },
        { "<leader>x", function() close_buffer(0) end, desc = "탭 닫기" },
        { "<leader>bo", "<Cmd>BufferLineCloseOthers<CR>", desc = "다른 탭 모두 닫기" },
      },
      opts = {
        options = {
          -- clicking a tab's X (or right-clicking it) closes it; asks if unsaved
          close_command = close_buffer,
          right_mouse_command = close_buffer,
          always_show_bufferline = true,
          offsets = {
            { filetype = "neo-tree", text = "탐색기", text_align = "left", separator = true },
          },
        },
      },
    },

    -- ---- Find files / search text (like VS Code's Ctrl+P and Ctrl+Shift+F) ----
    {
      "nvim-telescope/telescope.nvim",
      version = "*",
      dependencies = {
        "nvim-lua/plenary.nvim",
        { "nvim-telescope/telescope-fzf-native.nvim", build = "make" }, -- faster matching
      },
      cmd = "Telescope",
      keys = {
        { "<C-p>", "<Cmd>Telescope find_files<CR>", desc = "파일 찾기" },
        { "<leader>ff", "<Cmd>Telescope find_files<CR>", desc = "파일 찾기" },
        { "<leader>fg", "<Cmd>Telescope live_grep<CR>", desc = "전체 검색 (글자)" },
        { "<leader>fw", "<Cmd>Telescope grep_string<CR>", desc = "커서 아래 단어 전체 검색" },
        { "<leader>fr", "<Cmd>Telescope oldfiles<CR>", desc = "최근 연 파일" },
        { "<leader>fb", "<Cmd>Telescope buffers<CR>", desc = "열린 파일(탭) 목록" },
      },
      config = function()
        local telescope = require("telescope")
        local actions = require("telescope.actions")
        local rg_extra = { "--hidden", "--glob", "!**/.git/*" } -- include dotfiles, skip .git
        telescope.setup({
          defaults = {
            sorting_strategy = "ascending",
            layout_config = { prompt_position = "top" }, -- search box on top, like VS Code
            mappings = {
              i = { ["<Esc>"] = actions.close }, -- one Esc closes the popup
            },
            -- Never open the chosen file inside the file tree window
            get_selection_window = function()
              local cur = vim.api.nvim_get_current_win()
              if vim.bo[vim.api.nvim_win_get_buf(cur)].filetype ~= "neo-tree" then return 0 end
              for _, win in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
                local buf = vim.api.nvim_win_get_buf(win)
                if vim.bo[buf].filetype ~= "neo-tree" and vim.api.nvim_win_get_config(win).relative == "" then
                  return win
                end
              end
              return 0
            end,
          },
          pickers = {
            find_files = { hidden = true, file_ignore_patterns = { "^%.git/" } },
            live_grep = { additional_args = rg_extra },
            grep_string = { additional_args = rg_extra },
            oldfiles = { only_cwd = true }, -- recent files of this project only
          },
        })
        pcall(telescope.load_extension, "fzf") -- skip quietly if it was not built
      end,
    },

    -- ---- Language servers (Python, C/C++, Shell), installed by Mason ----
    {
      "mason-org/mason-lspconfig.nvim",
      lazy = false,
      dependencies = {
        { "mason-org/mason.nvim", opts = {} }, -- :Mason opens the installer window
        "neovim/nvim-lspconfig", -- ready-made settings for each server
      },
      opts = {
        ensure_installed = { "basedpyright", "ruff", "clangd", "bashls" },
      },
      config = function(_, opts)
        -- basedpyright's default ("recommended") flags almost everything;
        -- use the usual pyright level instead
        vim.lsp.config("basedpyright", {
          settings = { basedpyright = { analysis = { typeCheckingMode = "standard" } } },
        })
        require("mason-lspconfig").setup(opts) -- also enables the installed servers
      end,
    },

    -- ---- Autocomplete popup while typing (like VS Code IntelliSense) ----
    {
      "saghen/blink.cmp",
      version = "1.*", -- release tag -> prebuilt fuzzy matcher binary
      dependencies = { "rafamadriz/friendly-snippets" },
      event = { "InsertEnter", "CmdlineEnter" },
      opts = {
        keymap = {
          preset = "super-tab", -- Tab accepts the suggestion
          ["<CR>"] = { "accept", "fallback" }, -- Enter accepts too
        },
        appearance = { nerd_font_variant = "mono" },
        completion = { documentation = { auto_show = true, auto_show_delay_ms = 300 } },
        signature = { enabled = true }, -- show function parameters while typing
        sources = { default = { "lsp", "path", "snippets", "buffer" } },
        fuzzy = { implementation = "prefer_rust_with_warning" },
      },
    },

    -- ---- Syntax colors from a real parser (treesitter), not regex guesses ----
    {
      "nvim-treesitter/nvim-treesitter",
      branch = "main",
      lazy = false, -- does not support lazy-loading
      build = ":TSUpdate",
      config = function()
        local ts = require("nvim-treesitter")
        -- Parsers are compiled (tree-sitter CLI + C compiler) by init_common.sh;
        -- add more later with :TSInstall <language>
        local wanted = {
          "python", "c", "cpp", "bash", "zsh", "lua", "vim", "vimdoc", "query",
          "markdown", "markdown_inline", "json", "yaml", "toml", "cmake", "make",
          "diff", "gitcommit", "dockerfile",
        }
        if #vim.api.nvim_list_uis() == 0 and vim.fn.executable("tree-sitter") == 1 then
          local installed = ts.get_installed("parsers")
          local missing = vim.tbl_filter(function(lang)
            return not vim.list_contains(installed, lang)
          end, wanted)
          if #missing > 0 then pcall(function() ts.install(missing):wait(600000) end) end
        end

        vim.api.nvim_create_autocmd("FileType", {
          group = vim.api.nvim_create_augroup("treesitter_colors", { clear = true }),
          callback = function(ev)
            -- very large files (logs, generated code): keep the fast regex colors
            local stat = (vim.uv or vim.loop).fs_stat(vim.api.nvim_buf_get_name(ev.buf))
            if stat and stat.size > 1024 * 1024 then return end
            pcall(vim.treesitter.start, ev.buf) -- no parser for this language: skip
          end,
        })
      end,
    },

    -- ---- Git: changed lines marked next to the line numbers (like VS Code) ----
    {
      "lewis6991/gitsigns.nvim",
      version = "*",
      event = { "BufReadPre", "BufNewFile" },
      opts = {
        on_attach = function(buf)
          local gs = require("gitsigns")
          local function map(lhs, rhs, desc)
            vim.keymap.set("n", lhs, rhs, { buffer = buf, desc = desc })
          end
          map("]h", function() gs.nav_hunk("next") end, "다음 변경 위치")
          map("[h", function() gs.nav_hunk("prev") end, "이전 변경 위치")
          map("<leader>gp", gs.preview_hunk, "바뀐 내용 미리보기")
          map("<leader>gr", gs.reset_hunk, "이 변경 되돌리기 (마지막 커밋 상태로)")
          map("<leader>gb", function() gs.blame_line({ full = true }) end, "이 줄 누가 언제 바꿨나")
          map("<leader>ub", gs.toggle_current_line_blame, "줄 끝 작성자 표시 켜기/끄기")
        end,
      },
    },

    -- ---- Images: open *.png etc. as pictures, render images in markdown ----
    {
      "3rd/image.nvim",
      build = false, -- magick_cli processor: no luarocks build
      lazy = false, -- must hook image files before the first buffer is read
      cond = function()
        return vim.fn.executable("magick") == 1 or vim.fn.executable("convert") == 1
      end,
      opts = {
        backend = has_kitty_graphics() and "kitty" or "sixel",
        processor = "magick_cli",
        integrations = {
          markdown = {
            enabled = true,
            -- sixel is slow: only draw the image under the cursor
            only_render_image_at_cursor = true,
            only_render_image_at_cursor_mode = "popup",
          },
        },
        max_height_window_percentage = 50,
        window_overlap_clear_enabled = false,
        hijack_file_patterns = { "*.png", "*.jpg", "*.jpeg", "*.gif", "*.webp", "*.avif" },
      },
      config = function(_, opts)
        local image = require("image")
        image.setup(opts)

        vim.keymap.set("n", "<leader>ui", function()
          if image.is_enabled() then image.disable() else image.enable() end
        end, { desc = "이미지 표시 켜기/끄기" })

        if opts.backend ~= "sixel" then return end

        -- Sixel pixels live in the text grid: anything nvim draws over an image
        -- erases it, and image.nvim only repaints on geometry changes. Repaint
        -- (debounced) after redraw-ish events. Encoded sixel is cached, so this
        -- is a write, not another ImageMagick run.
        -- (approach from github.com/lenhattri/nvim-wsl)
        local timer = nil
        local function repaint()
          if timer then timer:stop() end
          timer = vim.defer_fn(function()
            timer = nil
            if not image.is_enabled() then return end
            for _, img in ipairs(image.get_images()) do
              img:clear(true) -- shallow clear so the next render really repaints
              img:render()
            end
          end, 150)
        end

        local group = vim.api.nvim_create_augroup("image_sixel_repaint", { clear = true })
        vim.api.nvim_create_autocmd({
          "WinScrolled", "WinResized", "VimResized", "InsertLeave",
          "WinEnter", "TabEnter", "FocusGained", "CmdlineLeave", "WinClosed",
        }, { group = group, callback = repaint })

        -- The cursor line would be drawn on top of the picture
        vim.api.nvim_create_autocmd("FileType", {
          group = group,
          pattern = "image_nvim",
          callback = function()
            vim.opt_local.cursorline = false
            vim.opt_local.list = false
          end,
        })
      end,
    },

    -- ---- PDFs: `nvim file.pdf` opens a page viewer (needs mutool) ----
    {
      "rohit746/pdf-view.nvim",
      lazy = false, -- must hook *.pdf before a PDF given on the command line is read
      opts = {
        -- Windows Terminal does not report its pixel size over WSL, but its sixel
        -- always uses a fixed virtual 10x20 px cell (microsoft/terminal#17504)
        cell_size = (vim.env.WT_SESSION and not has_kitty_graphics()) and { 10, 20 } or nil,
      },
    },
  },
  rocks = { enabled = false },
  checker = { enabled = false },
  change_detection = { notify = false },
})
NVIM_EOF

# Pre-install plugins (and compile treesitter parsers) so the first launch is clean
echo "Installing Neovim plugins and syntax parsers (first run takes a few minutes)..."
if command -v nvim >/dev/null 2>&1; then
  as_user env HOME="${TARGET_HOME}" timeout 900 nvim --headless "+Lazy! sync" +qa >/dev/null 2>&1 \
    || echo "Warning: plugin install did not finish; open nvim and run :Lazy sync"
fi

# Pre-install the language servers (Mason) that are not installed yet.
# bash-language-server is an npm package, so load nvm's Node first.
echo "Installing language servers (can take a few minutes)..."
MASON_BIN="${TARGET_HOME}/.local/share/nvim/mason/bin"
MASON_MISSING=""
for entry in basedpyright:basedpyright-langserver ruff:ruff clangd:clangd \
             bash-language-server:bash-language-server; do
  [[ -x "${MASON_BIN}/${entry#*:}" ]] || MASON_MISSING="${MASON_MISSING} ${entry%%:*}"
done
if [[ -z "${MASON_MISSING}" ]]; then
  echo "Language servers already installed, skipping..."
elif command -v nvim >/dev/null 2>&1; then
  as_user env HOME="${TARGET_HOME}" NVM_DIR="${NVM_DIR}" MASON_PKGS="${MASON_MISSING}" bash -c '
    [[ -s "$NVM_DIR/nvm.sh" ]] && . "$NVM_DIR/nvm.sh"
    timeout 900 nvim --headless -c "MasonInstall ${MASON_PKGS}" -c qall
  ' >/dev/null 2>&1 || echo "Warning: some language servers did not install; open nvim and run :Mason"
fi

# -----------------------------------------------------------------------------
# 8. Set default shell
# -----------------------------------------------------------------------------
log "Setting zsh as default shell"
ZSH_BIN="$(command -v zsh)"
if [[ "${EUID}" -eq 0 ]]; then
  chsh -s "${ZSH_BIN}" "${TARGET_USER}" || echo "Warning: chsh failed. You can still run: exec zsh"
else
  ${SUDO} chsh -s "${ZSH_BIN}" "${TARGET_USER}" || echo "Warning: chsh failed. You can still run: exec zsh"
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
echo "  ✓ nvm: $([ -s ~/.nvm/nvm.sh ] && echo 'Installed' || echo 'Not found')"
echo "  ✓ Node: $(command -v node >/dev/null && node -v || echo 'Not found')"
echo "  ✓ npm: $(command -v npm >/dev/null && npm -v || echo 'Not found')"
echo "  ✓ eza: $(command -v eza >/dev/null && eza --version | head -1 || echo 'Not found')"
echo "  ✓ zellij: $(command -v zellij >/dev/null && zellij --version || echo 'Not found')"
echo "  ✓ Neovim: $(command -v nvim >/dev/null && nvim --version | head -1 || echo 'Not found')"
echo "  ✓ nvim config: $([ -f ~/.config/nvim/init.lua ] && echo 'Installed' || echo 'Not found')"
echo "  ✓ ImageMagick: $(command -v convert >/dev/null && convert -version | head -1 | cut -d' ' -f2-3 || echo 'Not found')"
echo "  ✓ mutool: $(command -v mutool >/dev/null && mutool -v 2>&1 | head -1 || echo 'Not found')"
echo "  ✓ win32yank: $(command -v win32yank.exe >/dev/null && echo 'Installed' || echo 'Not found (only needed on WSL)')"
echo "  ✓ ripgrep: $(command -v rg >/dev/null && rg --version | head -1 || echo 'Not found')"
echo "  ✓ fd: $(command -v fdfind >/dev/null && fdfind --version || echo 'Not found')"
echo "  ✓ tree-sitter: $(command -v tree-sitter >/dev/null && tree-sitter --version || echo 'Not found')"
echo "  ✓ Syntax parsers: $(ls ~/.local/share/nvim/site/parser 2>/dev/null | sed 's/\.so$//' | tr '\n' ' ' || echo 'Not found')"
echo "  ✓ hangul-ime: $(command -v hangul-ime.exe >/dev/null && echo 'Installed' || echo 'Not found (only needed on WSL)')"
echo "  ✓ Language servers: $(ls ~/.local/share/nvim/mason/bin 2>/dev/null | tr '\n' ' ' || echo 'Not found')"
echo "  ✓ Theme: $(grep '^ZSH_THEME=' ~/.zshrc 2>/dev/null || echo 'Not set')"
echo "  ✓ Simplerich: $([ -d ~/.oh-my-zsh/custom/themes/simplerich-zsh-theme ] && echo 'Installed' || echo 'Not found')"
VERIFY_EOF
chmod +x /tmp/verify_setup.sh

# -----------------------------------------------------------------------------
# Done
# -----------------------------------------------------------------------------
log "Setup complete"
echo "Done!"
echo ""
echo "Next steps:"
echo "  1. Restart shell: exec zsh"
echo "  2. Verify: /tmp/verify_setup.sh"
echo ""
echo "Note: Icons require a Nerd Font in your terminal."

