#!/usr/bin/env bash
set -euo pipefail
IFS=$'\n\t'

# =============================================================================
# System Initialization Script v4.4
# - Installs: zsh, oh-my-zsh, miniconda, nvm + Node.js LTS, eza/exa, zellij,
#             neovim (+ file tree, tabs, image/PDF viewing), win32yank (WSL),
#             zsh-autosuggestions, zsh-syntax-highlighting
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
# - apt ships an old version (0.9.x on Ubuntu 24.04); many plugins need >= 0.11
# - Installs to /opt/nvim and links /usr/local/bin/nvim
# -----------------------------------------------------------------------------
NVIM_MIN_VERSION="0.11"

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
#   build-essential  -> compiles telescope-fzf-native (and C/C++ work in general)
${SUDO} apt install -y imagemagick mupdf-tools unzip ripgrep fd-find build-essential
install_win32yank

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
# - lazy.nvim + image.nvim (images) + pdf-view.nvim (PDFs)
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
          { "<leader>f", group = "찾기" },
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

# Pre-install plugins so the first launch is clean
echo "Installing Neovim plugins..."
if command -v nvim >/dev/null 2>&1; then
  as_user env HOME="${TARGET_HOME}" timeout 300 nvim --headless "+Lazy! sync" +qa >/dev/null 2>&1 \
    || echo "Warning: plugin install did not finish; open nvim and run :Lazy sync"
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

