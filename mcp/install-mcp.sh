#!/usr/bin/env bash
#
# install-mcp.sh - Merge voicemode MCP configuration into ~/.kimi/mcp.json
#
# Usage:
#   ./install-mcp.sh              # Merge config
#   ./install-mcp.sh --check      # Check if voicemode is already registered
#   ./install-mcp.sh --remove     # Remove voicemode from config
#

set -euo pipefail

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MCP_CONFIG="${SCRIPT_DIR}/mcp-config.json"
KIMI_MCP="${HOME}/.kimi/mcp.json"

# Colors for output (if terminal supports it)
if [[ -t 1 ]]; then
    RED='\033[0;31m'
    GREEN='\033[0;32m'
    YELLOW='\033[1;33m'
    BLUE='\033[0;34m'
    NC='\033[0m' # No Color
else
    RED='' GREEN='' YELLOW='' BLUE='' NC=''
fi

# Print helpers
info() { echo -e "${BLUE}ℹ${NC} $*"; }
success() { echo -e "${GREEN}✓${NC} $*"; }
warn() { echo -e "${YELLOW}⚠${NC} $*"; }
error() { echo -e "${RED}✗${NC} $*" >&2; }

# Check if jq is available
check_jq() {
    if command -v jq &>/dev/null; then
        return 0
    else
        return 1
    fi
}

# Merge using jq
merge_with_jq() {
    local target="$1"
    local source="$2"
    
    # Create backup
    cp "$target" "${target}.backup.$(date +%Y%m%d%H%M%S)"
    
    # Merge: source takes precedence for conflicting keys
    jq -s '.[0] * .[1]' "$target" "$source" > "${target}.tmp"
    mv "${target}.tmp" "$target"
}

# Merge without jq (basic implementation)
merge_without_jq() {
    local target="$1"
    local source="$2"
    
    # Create backup
    cp "$target" "${target}.backup.$(date +%Y%m%d%H%M%S)"
    
    # Simple merge: we just overwrite with the source for voicemode
    # This is a basic implementation - it assumes the structure is simple
    warn "jq not available, using basic merge"
    
    # Read the source config and extract voicemode section
    local voicemode_config
    voicemode_config=$(grep -A5 '"voicemode"' "$source" || true)
    
    if [[ -z "$voicemode_config" ]]; then
        error "Could not extract voicemode config from source"
        return 1
    fi
    
    # Check if mcpServers exists in target
    if grep -q '"mcpServers"' "$target" 2>/dev/null; then
        # Check if voicemode already exists
        if grep -q '"voicemode"' "$target" 2>/dev/null; then
            warn "voicemode already exists in config, replacing..."
            # Remove existing voicemode section (this is crude but works for simple cases)
            python3 << 'PYEOF'
import json
import sys

with open(sys.argv[1], 'r') as f:
    config = json.load(f)

with open(sys.argv[2], 'r') as f:
    new_config = json.load(f)

if 'mcpServers' in new_config and 'voicemode' in new_config.get('mcpServers', {}):
    config.setdefault('mcpServers', {})['voicemode'] = new_config['mcpServers']['voicemode']

with open(sys.argv[1], 'w') as f:
    json.dump(config, f, indent=2)
PYEOF
        else
            # Add voicemode to existing mcpServers
            python3 << 'PYEOF'
import json
import sys

with open(sys.argv[1], 'r') as f:
    config = json.load(f)

with open(sys.argv[2], 'r') as f:
    new_config = json.load(f)

if 'mcpServers' in new_config and 'voicemode' in new_config.get('mcpServers', {}):
    config.setdefault('mcpServers', {})['voicemode'] = new_config['mcpServers']['voicemode']

with open(sys.argv[1], 'w') as f:
    json.dump(config, f, indent=2)
PYEOF
        fi
    else
        # No mcpServers section, just copy the whole thing
        cp "$source" "$target"
    fi
}

# Check if voicemode is already registered
check_voicemode() {
    if [[ ! -f "$KIMI_MCP" ]]; then
        info "No existing MCP config found at ${KIMI_MCP}"
        return 1
    fi
    
    if grep -q '"voicemode"' "$KIMI_MCP" 2>/dev/null; then
        success "voicemode MCP is already registered in ${KIMI_MCP}"
        if command -v jq &>/dev/null; then
            echo "Current configuration:"
            jq '.mcpServers.voicemode' "$KIMI_MCP"
        fi
        return 0
    else
        info "voicemode MCP is not registered in ${KIMI_MCP}"
        return 1
    fi
}

# Remove voicemode from config
remove_voicemode() {
    if [[ ! -f "$KIMI_MCP" ]]; then
        warn "No MCP config found at ${KIMI_MCP}"
        return 0
    fi
    
    if ! grep -q '"voicemode"' "$KIMI_MCP" 2>/dev/null; then
        info "voicemode is not in the config"
        return 0
    fi
    
    # Create backup
    cp "$KIMI_MCP" "${KIMI_MCP}.backup.$(date +%Y%m%d%H%M%S)"
    
    if check_jq; then
        jq 'del(.mcpServers.voicemode)' "$KIMI_MCP" > "${KIMI_MCP}.tmp"
        mv "${KIMI_MCP}.tmp" "$KIMI_MCP"
    else
        python3 << 'PYEOF'
import json
import sys

with open(sys.argv[1], 'r') as f:
    config = json.load(f)

if 'mcpServers' in config and 'voicemode' in config['mcpServers']:
    del config['mcpServers']['voicemode']
    # Remove mcpServers if empty
    if not config['mcpServers']:
        del config['mcpServers']

with open(sys.argv[1], 'w') as f:
    json.dump(config, f, indent=2)
PYEOF
    fi
    
    success "Removed voicemode from ${KIMI_MCP}"
}

# Main install function
install_mcp() {
    info "Installing voicemode MCP configuration..."
    
    # Check source config exists
    if [[ ! -f "$MCP_CONFIG" ]]; then
        error "Source config not found: ${MCP_CONFIG}"
        exit 1
    fi
    
    # Validate source JSON
    if ! python3 -c "import json; json.load(open('${MCP_CONFIG}'))" 2>/dev/null; then
        error "Invalid JSON in source config: ${MCP_CONFIG}"
        exit 1
    fi
    
    # Create .kimi directory if needed
    mkdir -p "$(dirname "$KIMI_MCP")"
    
    if [[ -f "$KIMI_MCP" ]]; then
        # Validate existing config
        if ! python3 -c "import json; json.load(open('${KIMI_MCP}'))" 2>/dev/null; then
            error "Existing MCP config is invalid JSON: ${KIMI_MCP}"
            warn "Backing up to ${KIMI_MCP}.corrupt and creating new config"
            cp "$KIMI_MCP" "${KIMI_MCP}.corrupt"
            cp "$MCP_CONFIG" "$KIMI_MCP"
            success "Created new MCP config"
            exit 0
        fi
        
        # Merge configs
        if check_jq; then
            merge_with_jq "$KIMI_MCP" "$MCP_CONFIG"
        else
            merge_without_jq "$KIMI_MCP" "$MCP_CONFIG"
        fi
        success "Merged voicemode into existing MCP config: ${KIMI_MCP}"
    else
        # No existing config, just copy
        cp "$MCP_CONFIG" "$KIMI_MCP"
        success "Created new MCP config: ${KIMI_MCP}"
    fi
    
    # Verify installation
    if check_voicemode; then
        echo ""
        success "voicemode MCP installation complete!"
        info "You can now use the voicemode tool in Kimi"
        info "Test it by running: kimi 'use the voicemode tool to say hello'"
    else
        error "Installation verification failed"
        exit 1
    fi
}

# Show help
show_help() {
    cat << 'EOF'
Usage: install-mcp.sh [OPTIONS]

Install or manage the voicemode MCP configuration for Kimi.

OPTIONS:
  --check, -c     Check if voicemode is already registered
  --remove, -r    Remove voicemode from the MCP config
  --help, -h      Show this help message

DESCRIPTION:
  This script merges the voicemode MCP configuration into ~/.kimi/mcp.json.
  It will create the config file if it doesn't exist, or merge with existing
  configuration if it does.

  The script prefers to use 'jq' for JSON manipulation, but will fall back to
  Python's json module if jq is not available.

EXAMPLES:
  ./install-mcp.sh          # Install voicemode MCP
  ./install-mcp.sh --check  # Check if already installed
  ./install-mcp.sh --remove # Remove voicemode MCP
EOF
}

# Main entry point
main() {
    case "${1:-}" in
        --check|-c)
            check_voicemode
            ;;
        --remove|-r)
            remove_voicemode
            ;;
        --help|-h)
            show_help
            ;;
        "")
            install_mcp
            ;;
        *)
            error "Unknown option: $1"
            show_help
            exit 1
            ;;
    esac
}

main "$@"
