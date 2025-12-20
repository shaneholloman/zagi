#!/bin/sh
set -e

# zagi installer
# Usage: curl -fsSL zagi.sh/install | sh

REPO="mattzcarey/zagi"
INSTALL_DIR="${ZAGI_INSTALL_DIR:-$HOME/.local/bin}"

# Colors (if terminal supports them)
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
NC='\033[0m' # No Color

info() { printf "${GREEN}==>${NC} %s\n" "$1"; }
warn() { printf "${YELLOW}warning:${NC} %s\n" "$1"; }
error() { printf "${RED}error:${NC} %s\n" "$1" >&2; exit 1; }

# Detect OS and architecture
detect_platform() {
    OS="$(uname -s)"
    ARCH="$(uname -m)"

    case "$OS" in
        Linux)  OS="linux" ;;
        Darwin) OS="macos" ;;
        *) error "Unsupported OS: $OS" ;;
    esac

    case "$ARCH" in
        x86_64|amd64) ARCH="x86_64" ;;
        arm64|aarch64) ARCH="aarch64" ;;
        *) error "Unsupported architecture: $ARCH" ;;
    esac

    PLATFORM="${OS}-${ARCH}"
}

# Get latest release version from GitHub
get_latest_version() {
    if command -v curl >/dev/null 2>&1; then
        VERSION=$(curl -fsSL "https://api.github.com/repos/${REPO}/releases/latest" | grep '"tag_name"' | sed -E 's/.*"([^"]+)".*/\1/')
    elif command -v wget >/dev/null 2>&1; then
        VERSION=$(wget -qO- "https://api.github.com/repos/${REPO}/releases/latest" | grep '"tag_name"' | sed -E 's/.*"([^"]+)".*/\1/')
    else
        error "curl or wget is required"
    fi

    if [ -z "$VERSION" ]; then
        error "Could not determine latest version"
    fi
}

# Download and install binary
install_binary() {
    DOWNLOAD_URL="https://github.com/${REPO}/releases/download/${VERSION}/zagi-${PLATFORM}.tar.gz"

    info "Downloading zagi ${VERSION} for ${PLATFORM}..."

    # Create install directory
    mkdir -p "$INSTALL_DIR"

    # Download and extract
    TMP_DIR=$(mktemp -d)
    trap "rm -rf $TMP_DIR" EXIT

    if command -v curl >/dev/null 2>&1; then
        curl -fsSL "$DOWNLOAD_URL" | tar -xz -C "$TMP_DIR"
    else
        wget -qO- "$DOWNLOAD_URL" | tar -xz -C "$TMP_DIR"
    fi

    # Install binary
    mv "$TMP_DIR/zagi" "$INSTALL_DIR/zagi"
    chmod +x "$INSTALL_DIR/zagi"

    info "Installed zagi to $INSTALL_DIR/zagi"
}

# Detect shell and config file
detect_shell_config() {
    SHELL_NAME=$(basename "$SHELL")

    case "$SHELL_NAME" in
        bash)
            if [ -f "$HOME/.bashrc" ]; then
                SHELL_CONFIG="$HOME/.bashrc"
            elif [ -f "$HOME/.bash_profile" ]; then
                SHELL_CONFIG="$HOME/.bash_profile"
            else
                SHELL_CONFIG="$HOME/.bashrc"
            fi
            ALIAS_CMD="alias git='zagi'"
            ;;
        zsh)
            SHELL_CONFIG="$HOME/.zshrc"
            ALIAS_CMD="alias git='zagi'"
            ;;
        fish)
            SHELL_CONFIG="$HOME/.config/fish/config.fish"
            ALIAS_CMD="alias git 'zagi'"
            ;;
        *)
            SHELL_CONFIG=""
            ALIAS_CMD=""
            ;;
    esac
}

# Setup alias in shell config
setup_alias() {
    detect_shell_config

    if [ -z "$SHELL_CONFIG" ]; then
        warn "Could not detect shell config. Add this alias manually:"
        echo "  alias git='zagi'"
        return
    fi

    # Check if alias already exists
    if [ -f "$SHELL_CONFIG" ] && grep -q "alias git=" "$SHELL_CONFIG" 2>/dev/null; then
        warn "Git alias already exists in $SHELL_CONFIG"
        return
    fi

    # Add alias
    info "Adding git alias to $SHELL_CONFIG..."

    # Create config file if it doesn't exist
    mkdir -p "$(dirname "$SHELL_CONFIG")"
    touch "$SHELL_CONFIG"

    # Append alias
    echo "" >> "$SHELL_CONFIG"
    echo "# zagi - a better git for agents" >> "$SHELL_CONFIG"
    echo "$ALIAS_CMD" >> "$SHELL_CONFIG"

    info "Added: $ALIAS_CMD"
}

# Ensure install dir is in PATH
check_path() {
    case ":$PATH:" in
        *":$INSTALL_DIR:"*) ;;
        *)
            warn "$INSTALL_DIR is not in your PATH"
            echo ""
            echo "Add this to your shell config:"
            echo "  export PATH=\"\$PATH:$INSTALL_DIR\""
            echo ""

            # Try to add it automatically
            detect_shell_config
            if [ -n "$SHELL_CONFIG" ] && [ -f "$SHELL_CONFIG" ]; then
                if ! grep -q "$INSTALL_DIR" "$SHELL_CONFIG" 2>/dev/null; then
                    echo "export PATH=\"\$PATH:$INSTALL_DIR\"" >> "$SHELL_CONFIG"
                    info "Added $INSTALL_DIR to PATH in $SHELL_CONFIG"
                fi
            fi
            ;;
    esac
}

# Main
main() {
    info "Installing zagi..."

    detect_platform
    get_latest_version
    install_binary
    check_path
    setup_alias

    echo ""
    info "Installation complete!"
    echo ""
    echo "Restart your shell or run:"
    echo "  source $SHELL_CONFIG"
    echo ""
    echo "Then use 'git' as normal - zagi will handle it!"
}

main
