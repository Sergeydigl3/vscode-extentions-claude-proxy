#!/bin/bash
# VS Code Extension Gallery Patcher (Linux)
# Usage: ./patch-vscode.sh example.com

set -e

DOMAIN="${1:-}"

if [ -z "$DOMAIN" ]; then
    echo "Usage: $0 <domain>"
    echo "Example: $0 g.example.com"
    exit 1
fi

# Strip trailing slash and protocol if provided
DOMAIN=$(echo "$DOMAIN" | sed 's|^https\?://||; s|/$||')

PROXY_SERVICE="https://$DOMAIN/vscode/gallery"
PROXY_ITEM="https://$DOMAIN/vscode/items"
PROXY_CACHE="https://$DOMAIN/vscode/cache/index"
PROXY_CONTROL="https://$DOMAIN/vscode/control"

MS_SERVICE="https://marketplace.visualstudio.com/_apis/public/gallery"
MS_ITEM="https://marketplace.visualstudio.com/items"
MS_CACHE="https://vscode.blob.core.windows.net/gallery/index"

CYAN='\033[0;36m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
GRAY='\033[0;90m'
NC='\033[0m'

echo -e "${CYAN}=== VS Code Gallery Patcher (Linux) ===${NC}"
echo -e "${CYAN}Proxy domain: $DOMAIN${NC}"

# Find product.json
SEARCH_DIRS=(
    "/usr/share/code/resources/app"
    "/usr/lib/code/resources/app"
    "/opt/visual-studio-code/resources/app"
    "/snap/code/current/usr/share/code/resources/app"
    "$HOME/.local/share/code/resources/app"
)

FILE=""
for dir in "${SEARCH_DIRS[@]}"; do
    if [ -f "$dir/product.json" ]; then
        FILE="$dir/product.json"
        break
    fi
done

# Fallback: search with find
if [ -z "$FILE" ]; then
    FILE=$(find /usr /opt /snap "$HOME/.local" -path "*/resources/app/product.json" -name "product.json" 2>/dev/null | head -1)
fi

if [ -z "$FILE" ] || [ ! -f "$FILE" ]; then
    echo -e "${RED}ERROR: product.json not found!${NC}"
    exit 1
fi

echo -e "${GREEN}Found: $FILE${NC}"

# Check write permissions
if [ ! -w "$FILE" ]; then
    echo -e "${YELLOW}No write permission. Re-running with sudo...${NC}"
    exec sudo "$0" "$@"
fi

# Read current serviceUrl
CURRENT=$(grep -oP '"serviceUrl"\s*:\s*"\K[^"]+' "$FILE")
echo -e "\n${YELLOW}Current gallery: $CURRENT${NC}"

# Helper: replace JSON string value by key (preserves formatting)
replace_value() {
    local file="$1"
    local key="$2"
    local new_value="$3"
    local escaped_value
    escaped_value=$(echo "$new_value" | sed 's/[&/\]/\\&/g')
    sed -i "s|\(\"$key\"\s*:\s*\)\"[^\"]*\"|\1\"$escaped_value\"|" "$file"
}

# Helper: add key-value after existing key if missing
add_value_after() {
    local file="$1"
    local after_key="$2"
    local new_key="$3"
    local new_value="$4"

    if grep -q "\"$new_key\"" "$file"; then
        replace_value "$file" "$new_key" "$new_value"
        return
    fi

    local escaped_value
    escaped_value=$(echo "$new_value" | sed 's/[&/\]/\\&/g')
    local indent
    indent=$(grep "\"$after_key\"" "$file" | head -1 | sed 's/\([[:space:]]*\).*/\1/')

    sed -i "/\"$after_key\"/s/$/,/" "$file"
    sed -i "/\"$after_key\"/a\\${indent}\"$new_key\": \"$escaped_value\"" "$file"
}

# Detect current state
IS_PROXY=false
if ! echo "$CURRENT" | grep -q "marketplace\.visualstudio\.com"; then
    IS_PROXY=true
fi

if $IS_PROXY; then
    echo -en "\n${YELLOW}Restore to Microsoft Marketplace? (y/N): ${NC}"
    read -r choice

    if [[ "$choice" =~ ^[Yy]$ ]]; then
        BACKUP="${FILE}.backup_$(date +%Y%m%d_%H%M%S)"
        cp "$FILE" "$BACKUP"
        echo -e "\n${GRAY}Backup: $BACKUP${NC}"

        replace_value "$FILE" "serviceUrl" "$MS_SERVICE"
        replace_value "$FILE" "itemUrl" "$MS_ITEM"
        replace_value "$FILE" "cacheUrl" "$MS_CACHE"
        replace_value "$FILE" "controlUrl" ""
        ACTION="Restored to Microsoft"
    else
        echo -e "${YELLOW}Cancelled.${NC}"
        exit 0
    fi
else
    echo -en "\n${YELLOW}Patch to use proxy? (y/N): ${NC}"
    read -r choice

    if [[ "$choice" =~ ^[Yy]$ ]]; then
        BACKUP="${FILE}.backup_$(date +%Y%m%d_%H%M%S)"
        cp "$FILE" "$BACKUP"
        echo -e "\n${GRAY}Backup: $BACKUP${NC}"

        replace_value "$FILE" "serviceUrl" "$PROXY_SERVICE"
        replace_value "$FILE" "itemUrl" "$PROXY_ITEM"
        replace_value "$FILE" "cacheUrl" "$PROXY_CACHE"
        add_value_after "$FILE" "cacheUrl" "controlUrl" "$PROXY_CONTROL"
        ACTION="Patched to proxy"
    else
        echo -e "${YELLOW}Cancelled.${NC}"
        exit 0
    fi
fi

echo -e "\n${GREEN}DONE! $ACTION${NC}"
echo -e "${CYAN}Restart VS Code to apply changes.${NC}"
