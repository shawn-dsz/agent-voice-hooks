#!/usr/bin/env bash
# Kimi Voice Hooks - One-Command Installer
# https://github.com/yourusername/kimi-voice-hooks
#
# Usage:
#   curl -fsSL https://raw.githubusercontent.com/yourusername/kimi-voice-hooks/main/install.sh | bash
#   ./install.sh                    # Install or upgrade
#   ./install.sh --uninstall        # Remove installation
#   ./install.sh --upgrade          # Force upgrade
#   ./install.sh --help             # Show help

set -euo pipefail

# Version
VERSION="0.1.0"

# Installation paths
INSTALL_DIR="${HOME}/.local/share/kimi-voice"
BIN_DIR="${HOME}/.local/bin"
CONFIG_DIR="${HOME}/.config/kimi-voice"
SKILL_DIR="${HOME}/.config/agents/skills/voice-announce"
KIMI_MCP="${HOME}/.kimi/mcp.json"

# Repository structure (for development installs)
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Colors for output
if [[ -t 1 ]]; then
    RED='\033[0;31m'
    GREEN='\033[0;32m'
    YELLOW='\033[1;33m'
    BLUE='\033[0;34m'
    CYAN='\033[0;36m'
    BOLD='\033[1m'
    NC='\033[0m' # No Color
else
    RED='' GREEN='' YELLOW='' BLUE='' CYAN='' BOLD='' NC=''
fi

# Print helpers
info() { echo -e "${BLUE}ℹ${NC} $*"; }
success() { echo -e "${GREEN}✓${NC} $*"; }
warn() { echo -e "${YELLOW}⚠${NC} $*"; }
error() { echo -e "${RED}✗${NC} $*" >&2; }
step() { echo -e "\n${BOLD}${CYAN}▶${NC} $*"; }

# ============================================================================
# CHECK PREREQUISITES
# ============================================================================

check_prereqs() {
    step "Checking prerequisites..."
    
    local has_error=false
    
    # Check Python 3.10+
    info "Checking Python version..."
    local python_cmd
    local version
    local major
    local minor
    
    if command -v python3 &>/dev/null; then
        python_cmd="python3"
    elif command -v python &>/dev/null; then
        python_cmd="python"
    else
        error "Python 3 is required but not found."
        error "Please install Python 3.10 or later."
        has_error=true
    fi
    
    if [[ -n "${python_cmd:-}" ]]; then
        version=$($python_cmd --version 2>&1 | cut -d' ' -f2)
        major=$(echo "$version" | cut -d'.' -f1)
        minor=$(echo "$version" | cut -d'.' -f2)
        
        if [[ "$major" -lt 3 ]] || [[ "$major" -eq 3 && "$minor" -lt 10 ]]; then
            error "Python 3.10+ is required, found $version"
            has_error=true
        else
            success "Python $version found"
        fi
    fi
    
    # Check kimi CLI
    info "Checking Kimi CLI..."
    if command -v kimi &>/dev/null; then
        local kimi_version
        kimi_version=$(kimi --version 2>&1 | head -1 || echo "unknown")
        success "Kimi CLI found ($kimi_version)"
    else
        error "Kimi CLI not found. Please install Kimi Code CLI first."
        error "Visit: https://github.com/yourusername/kimi-cli"
        has_error=true
    fi
    
    # Check voicemode (optional - warn if not found)
    info "Checking VoiceMode..."
    if command -v voicemode &>/dev/null; then
        success "VoiceMode is installed"
    else
        warn "VoiceMode not found - voice output will fall back to 'say' or silent mode"
        warn "To install VoiceMode: uvx voice-mode-install"
    fi
    
    if [[ "$has_error" == true ]]; then
        return 1
    fi
    
    return 0
}

# ============================================================================
# INSTALL BRIDGE
# ============================================================================

install_bridge() {
    step "Installing bridge..."
    
    # Determine source directory
    local src_bridge_dir
    if [[ -d "${SCRIPT_DIR}/bridge" ]]; then
        # Running from repo clone
        src_bridge_dir="${SCRIPT_DIR}/bridge"
    elif [[ -d "/tmp/kimi-voice-hooks/bridge" ]]; then
        # Running from downloaded archive
        src_bridge_dir="/tmp/kimi-voice-hooks/bridge"
    else
        error "Could not find bridge source directory"
        return 1
    fi
    
    # Create installation directory
    info "Creating installation directory: $INSTALL_DIR"
    mkdir -p "$INSTALL_DIR"
    
    # Copy bridge files
    info "Copying bridge files..."
    cp -r "$src_bridge_dir"/*.py "$INSTALL_DIR/"
    cp -r "$src_bridge_dir"/kimi-voice "$INSTALL_DIR/"
    
    # Make scripts executable
    chmod +x "$INSTALL_DIR/kimi-voice"
    
    success "Bridge installed to $INSTALL_DIR"
    
    # Create symlink in bin directory
    info "Creating symlink in $BIN_DIR..."
    mkdir -p "$BIN_DIR"
    
    if [[ -L "$BIN_DIR/kimi-voice" ]]; then
        rm "$BIN_DIR/kimi-voice"
    fi
    
    ln -s "$INSTALL_DIR/kimi-voice" "$BIN_DIR/kimi-voice"
    success "Symlink created: $BIN_DIR/kimi-voice"
    
    # Check if bin directory is in PATH
    if [[ ":$PATH:" != *":$BIN_DIR:"* ]]; then
        warn "$BIN_DIR is not in your PATH"
        info "Add this to your shell profile (~/.bashrc, ~/.zshrc, etc.):"
        info "  export PATH=\"$BIN_DIR:\$PATH\""
    fi
}

# ============================================================================
# REGISTER MCP
# ============================================================================

register_mcp() {
    step "Registering voicemode MCP..."
    
    # Determine source config
    local src_mcp_config
    if [[ -f "${SCRIPT_DIR}/mcp/mcp-config.json" ]]; then
        src_mcp_config="${SCRIPT_DIR}/mcp/mcp-config.json"
    elif [[ -f "/tmp/kimi-voice-hooks/mcp/mcp-config.json" ]]; then
        src_mcp_config="/tmp/kimi-voice-hooks/mcp/mcp-config.json"
    else
        warn "MCP config not found, skipping MCP registration"
        return 0
    fi
    
    # Validate source JSON
    if ! python3 -c "import json; json.load(open('$src_mcp_config'))" 2>/dev/null; then
        error "Invalid JSON in MCP config: $src_mcp_config"
        return 1
    fi
    
    # Create .kimi directory if needed
    mkdir -p "$(dirname "$KIMI_MCP")"
    
    if [[ -f "$KIMI_MCP" ]]; then
        info "Merging with existing MCP config..."
        
        # Validate existing config
        if ! python3 -c "import json; json.load(open('$KIMI_MCP'))" 2>/dev/null; then
            warn "Existing MCP config is invalid, backing up and creating new"
            cp "$KIMI_MCP" "${KIMI_MCP}.backup.$(date +%Y%m%d%H%M%S)"
            cp "$src_mcp_config" "$KIMI_MCP"
            success "Created new MCP config"
            return 0
        fi
        
        # Merge configs using Python (more reliable than jq)
        python3 << PYEOF
import json
import sys

try:
    with open('$KIMI_MCP', 'r') as f:
        existing = json.load(f)
    
    with open('$src_mcp_config', 'r') as f:
        new = json.load(f)
    
    # Merge mcpServers
    if 'mcpServers' in new:
        existing.setdefault('mcpServers', {}).update(new['mcpServers'])
    
    with open('$KIMI_MCP', 'w') as f:
        json.dump(existing, f, indent=2)
    
    print("Merged successfully")
except Exception as e:
    print(f"Error: {e}", file=sys.stderr)
    sys.exit(1)
PYEOF
        success "Merged voicemode into $KIMI_MCP"
    else
        cp "$src_mcp_config" "$KIMI_MCP"
        success "Created new MCP config: $KIMI_MCP"
    fi
}

# ============================================================================
# INSTALL SKILL
# ============================================================================

install_skill() {
    step "Installing voice-announce skill..."
    
    # Determine source skill
    local src_skill_dir
    if [[ -d "${SCRIPT_DIR}/skills/voice-announce" ]]; then
        src_skill_dir="${SCRIPT_DIR}/skills/voice-announce"
    elif [[ -d "/tmp/kimi-voice-hooks/skills/voice-announce" ]]; then
        src_skill_dir="/tmp/kimi-voice-hooks/skills/voice-announce"
    else
        warn "Skill not found, skipping skill installation"
        return 0
    fi
    
    # Create skill directory
    info "Creating skill directory: $SKILL_DIR"
    mkdir -p "$SKILL_DIR"
    
    # Copy skill files
    cp "$src_skill_dir"/*.md "$SKILL_DIR/"
    
    success "Skill installed to $SKILL_DIR"
    info "Use /skill:voice-announce in Kimi to activate"
}

# ============================================================================
# CREATE CONFIG
# ============================================================================

create_config() {
    step "Creating default configuration..."
    
    # Determine source config
    local src_config
    if [[ -f "${SCRIPT_DIR}/config/kimi-voice.toml" ]]; then
        src_config="${SCRIPT_DIR}/config/kimi-voice.toml"
    elif [[ -f "/tmp/kimi-voice-hooks/config/kimi-voice.toml" ]]; then
        src_config="/tmp/kimi-voice-hooks/config/kimi-voice.toml"
    else
        warn "Default config not found, creating minimal config"
        src_config=""
    fi
    
    # Create config directory
    mkdir -p "$CONFIG_DIR"
    
    local config_file="$CONFIG_DIR/config.toml"
    
    if [[ -f "$config_file" ]]; then
        info "Config already exists at $config_file"
        info "Keeping existing config (use --upgrade to overwrite)"
        return 0
    fi
    
    if [[ -n "$src_config" ]]; then
        cp "$src_config" "$config_file"
    else
        # Create minimal config
        cat > "$config_file" << 'EOF'
# Kimi Voice Hooks Configuration
# https://github.com/yourusername/kimi-voice-hooks

[voice]
backend = "voicemode"
voice = "af_sky"
speed = 1.0

[idle]
timeout = 60
enabled = true

[events]
announce_turn_end = true
announce_approval = true
announce_idle = true
announce_errors = false

[bridge]
kimi_command = "kimi"
extra_args = []
EOF
    fi
    
    success "Config created at $config_file"
}

# ============================================================================
# VALIDATE INSTALLATION
# ============================================================================

validate() {
    step "Validating installation..."
    
    local has_error=false
    
    # Check bridge files
    if [[ -f "$INSTALL_DIR/bridge.py" ]]; then
        success "bridge.py installed"
    else
        error "bridge.py not found"
        has_error=true
    fi
    
    if [[ -f "$INSTALL_DIR/kimi-voice" ]]; then
        success "kimi-voice script installed"
    else
        error "kimi-voice script not found"
        has_error=true
    fi
    
    # Check symlink
    if [[ -L "$BIN_DIR/kimi-voice" ]]; then
        success "kimi-voice symlink in PATH"
    else
        warn "kimi-voice not in PATH ($BIN_DIR)"
    fi
    
    # Check config
    if [[ -f "$CONFIG_DIR/config.toml" ]]; then
        success "Configuration file exists"
    else
        error "Configuration file missing"
        has_error=true
    fi
    
    # Check MCP
    if [[ -f "$KIMI_MCP" ]]; then
        if grep -q '"voicemode"' "$KIMI_MCP" 2>/dev/null; then
            success "voicemode MCP registered"
        else
            warn "voicemode MCP may not be registered correctly"
        fi
    else
        warn "MCP config not found"
    fi
    
    # Check skill
    if [[ -f "$SKILL_DIR/SKILL.md" ]]; then
        success "voice-announce skill installed"
    else
        warn "voice-announce skill not found"
    fi
    
    # Run tests if available
    if [[ -f "${SCRIPT_DIR}/tests/run-all-tests.sh" ]]; then
        info "Running test suite..."
        if bash "${SCRIPT_DIR}/tests/run-all-tests.sh" --quick; then
            success "All tests passed"
        else
            warn "Some tests failed (non-fatal)"
        fi
    elif [[ -f "${SCRIPT_DIR}/tests/test-voice.sh" ]]; then
        info "Running voice tests..."
        if bash "${SCRIPT_DIR}/tests/test-voice.sh" --quick; then
            success "Voice tests passed"
        else
            warn "Voice tests failed (non-fatal)"
        fi
    fi
    
    if [[ "$has_error" == true ]]; then
        return 1
    fi
    
    return 0
}

# ============================================================================
# UNINSTALL
# ============================================================================

uninstall() {
    step "Uninstalling Kimi Voice Hooks..."
    
    info "Removing bridge files..."
    if [[ -d "$INSTALL_DIR" ]]; then
        rm -rf "$INSTALL_DIR"
        success "Removed $INSTALL_DIR"
    fi
    
    info "Removing symlink..."
    if [[ -L "$BIN_DIR/kimi-voice" ]]; then
        rm "$BIN_DIR/kimi-voice"
        success "Removed $BIN_DIR/kimi-voice"
    fi
    
    info "Removing configuration..."
    if [[ -d "$CONFIG_DIR" ]]; then
        read -p "Remove config directory ($CONFIG_DIR)? [y/N] " -n 1 -r
        echo
        if [[ $REPLY =~ ^[Yy]$ ]]; then
            rm -rf "$CONFIG_DIR"
            success "Removed $CONFIG_DIR"
        else
            info "Keeping config at $CONFIG_DIR"
        fi
    fi
    
    info "Removing skill..."
    if [[ -d "$SKILL_DIR" ]]; then
        rm -rf "$SKILL_DIR"
        success "Removed $SKILL_DIR"
    fi
    
    info "Removing MCP registration..."
    if [[ -f "$KIMI_MCP" ]]; then
        python3 << PYEOF
import json
import sys

try:
    with open('$KIMI_MCP', 'r') as f:
        config = json.load(f)
    
    if 'mcpServers' in config and 'voicemode' in config['mcpServers']:
        del config['mcpServers']['voicemode']
        
        # Remove empty mcpServers
        if not config['mcpServers']:
            del config['mcpServers']
        
        with open('$KIMI_MCP', 'w') as f:
            json.dump(config, f, indent=2)
        
        print("Removed voicemode from MCP config")
except Exception as e:
    print(f"Note: Could not update MCP config: {e}", file=sys.stderr)
PYEOF
    fi
    
    success "Uninstall complete"
}

# ============================================================================
# UPGRADE
# ============================================================================

upgrade() {
    step "Upgrading Kimi Voice Hooks..."
    
    # Backup existing config
    if [[ -f "$CONFIG_DIR/config.toml" ]]; then
        cp "$CONFIG_DIR/config.toml" "$CONFIG_DIR/config.toml.backup.$(date +%Y%m%d%H%M%S)"
        info "Backed up existing config"
    fi
    
    # Re-install everything
    install_bridge
    register_mcp
    install_skill
    
    # Don't overwrite config on upgrade
    info "Keeping existing configuration (backup created)"
    
    validate
}

# ============================================================================
# SHOW HELP
# ============================================================================

show_help() {
    cat << 'EOF'
Kimi Voice Hooks Installer
==========================

One-command installer for voice notifications in Kimi Code CLI.

USAGE:
    install.sh [OPTIONS]

OPTIONS:
    --install           Install Kimi Voice Hooks (default)
    --uninstall         Remove Kimi Voice Hooks
    --upgrade           Upgrade to latest version
    --help, -h          Show this help message
    --version, -v       Show version information

EXAMPLES:
    # Install (run from cloned repo)
    ./install.sh

    # Install via curl
    curl -fsSL https://raw.githubusercontent.com/yourusername/kimi-voice-hooks/main/install.sh | bash

    # Upgrade existing installation
    ./install.sh --upgrade

    # Remove completely
    ./install.sh --uninstall

WHAT GETS INSTALLED:
    ~/.local/share/kimi-voice/       Bridge scripts and Python modules
    ~/.local/bin/kimi-voice          Command-line wrapper (symlink)
    ~/.config/kimi-voice/config.toml Configuration file
    ~/.config/agents/skills/         Voice-announce skill
    ~/.kimi/mcp.json                 MCP registration for voicemode

REQUIREMENTS:
    - Python 3.10+
    - Kimi Code CLI (kimi)
    - macOS or Linux

For more information, visit:
    https://github.com/yourusername/kimi-voice-hooks
EOF
}

show_version() {
    echo "Kimi Voice Hooks Installer v$VERSION"
    echo "Bridge for Kimi Code CLI with voice notifications"
}

# ============================================================================
# MAIN
# ============================================================================

main() {
    case "${1:-}" in
        --help|-h)
            show_help
            exit 0
            ;;
        --version|-v)
            show_version
            exit 0
            ;;
        --uninstall)
            uninstall
            exit 0
            ;;
        --upgrade)
            upgrade
            exit 0
            ;;
        --install|"")
            # Continue with installation
            ;;
        *)
            error "Unknown option: $1"
            show_help
            exit 1
            ;;
    esac
    
    # Banner
    echo -e "${BOLD}"
    echo "╔════════════════════════════════════════════════════════════╗"
    echo "║          Kimi Voice Hooks Installer v$VERSION               ║"
    echo "║         Voice notifications for Kimi Code CLI              ║"
    echo "╚════════════════════════════════════════════════════════════╝"
    echo -e "${NC}"
    
    # Run installation steps
    check_prereqs || exit 1
    install_bridge
    register_mcp
    install_skill
    create_config
    
    echo ""
    if validate; then
        echo ""
        echo -e "${GREEN}${BOLD}✓ Installation complete!${NC}"
        echo ""
        echo "Get started:"
        echo "  kimi-voice \"help me refactor this code\""
        echo ""
        echo "Configuration:"
        echo "  ~/.config/kimi-voice/config.toml"
        echo ""
        echo "For help and troubleshooting:"
        echo "  kimi-voice --help"
        echo "  cat ~/.local/share/kimi-voice/README.md"
    else
        echo ""
        echo -e "${YELLOW}${BOLD}⚠ Installation completed with warnings${NC}"
        echo "Some components may not be working correctly."
        echo "Check the error messages above for details."
        exit 1
    fi
}

main "$@"
