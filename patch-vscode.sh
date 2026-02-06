#!/bin/bash
# VS Code Extension Gallery Patcher (Universal Linux)
# Detects local VS Code install and/or remote vscode-server, patches accordingly
# Usage: ./patch-vscode.sh example.com

set -e

DOMAIN="${1:-}"

if [ -z "$DOMAIN" ]; then
    echo "Usage: $0 <domain>"
    echo "Example: $0 g.example.com"
    exit 1
fi

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

echo -e "${CYAN}=== VS Code Gallery Patcher ===${NC}"
echo -e "${CYAN}Proxy domain: $DOMAIN${NC}"

# --- Collect all candidate product.json files ---
CANDIDATES=()

# 1. vscode-server (remote SSH) — active process
COMMIT=$(ps aux 2>/dev/null | grep -oP 'Stable-[a-f0-9]+' | head -1 | sed 's/Stable-//')
if [ -n "$COMMIT" ]; then
    F="$HOME/.vscode-server/cli/servers/Stable-$COMMIT/server/product.json"
    [ -f "$F" ] && CANDIDATES+=("$F")
fi

# 2. vscode-server — fallback: latest by date
if [ ${#CANDIDATES[@]} -eq 0 ]; then
    LATEST_SERVER=$(ls -td "$HOME"/.vscode-server/cli/servers/Stable-*/server/product.json 2>/dev/null | head -1)
    [ -n "$LATEST_SERVER" ] && CANDIDATES+=("$LATEST_SERVER")
fi

# 3. Local VS Code installs
LOCAL_DIRS=(
    "/usr/share/code/resources/app"
    "/usr/lib/code/resources/app"
    "/opt/visual-studio-code/resources/app"
    "/snap/code/current/usr/share/code/resources/app"
    "$HOME/.local/share/code/resources/app"
)
for dir in "${LOCAL_DIRS[@]}"; do
    [ -f "$dir/product.json" ] && CANDIDATES+=("$dir/product.json")
done

# 4. Fallback: find
if [ ${#CANDIDATES[@]} -eq 0 ]; then
    while IFS= read -r f; do
        CANDIDATES+=("$f")
    done < <(find /usr /opt /snap "$HOME" -path "*/resources/app/product.json" -o -path "*/.vscode-server/*/product.json" 2>/dev/null | head -10)
fi

# --- Nothing found ---
if [ ${#CANDIDATES[@]} -eq 0 ]; then
    echo -e "${RED}ERROR: No VS Code product.json found!${NC}"
    echo "Make sure VS Code or vscode-server is installed."
    exit 1
fi

# --- Deduplicate ---
UNIQUE=()
declare -A SEEN
for f in "${CANDIDATES[@]}"; do
    real=$(readlink -f "$f" 2>/dev/null || echo "$f")
    if [ -z "${SEEN[$real]}" ]; then
        SEEN[$real]=1
        UNIQUE+=("$f")
    fi
done

# --- Select target ---
if [ ${#UNIQUE[@]} -eq 1 ]; then
    FILE="${UNIQUE[0]}"
    echo -e "${GREEN}Found: $FILE${NC}"
else
    echo -e "\n${YELLOW}Found multiple VS Code installations:${NC}"
    for i in "${!UNIQUE[@]}"; do
        # Label each candidate
        label=""
        case "${UNIQUE[$i]}" in
            */.vscode-server/*) label="(remote server)" ;;
            /snap/*)            label="(snap)" ;;
            *)                  label="(local)" ;;
        esac
        echo -e "  ${CYAN}$((i+1)))${NC} ${UNIQUE[$i]} ${GRAY}$label${NC}"
    done
    echo -en "\n${YELLOW}Select number [1]: ${NC}"
    read -r sel
    sel=${sel:-1}
    idx=$((sel-1))
    if [ $idx -lt 0 ] || [ $idx -ge ${#UNIQUE[@]} ]; then
        echo -e "${RED}Invalid selection.${NC}"
        exit 1
    fi
    FILE="${UNIQUE[$idx]}"
fi

# --- Check write permissions ---
if [ ! -w "$FILE" ]; then
    echo -e "${YELLOW}No write permission for $FILE${NC}"
    echo -e "${YELLOW}Re-running with sudo...${NC}"
    exec sudo "$0" "$@"
fi

# --- Read current state ---
CURRENT=$(grep -oP '"serviceUrl"\s*:\s*"\K[^"]+' "$FILE")
echo -e "\n${YELLOW}Current gallery: $CURRENT${NC}"

# --- Helpers ---
replace_value() {
    local file="$1" key="$2" new_value="$3"
    local escaped_value
    escaped_value=$(echo "$new_value" | sed 's/[&/\]/\\&/g')
    sed -i "s|\(\"$key\"\s*:\s*\)\"[^\"]*\"|\1\"$escaped_value\"|" "$file"
}

add_value_after() {
    local file="$1" after_key="$2" new_key="$3" new_value="$4"

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

# --- Decide action ---
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
        echo -e "${GRAY}Backup: $BACKUP${NC}"

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
        echo -e "${GRAY}Backup: $BACKUP${NC}"

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

# Suggest reload method based on context
if echo "$FILE" | grep -q ".vscode-server"; then
    echo -e "${CYAN}Reload VS Code window: Ctrl+Shift+P → 'Reload Window'${NC}"
else
    echo -e "${CYAN}Restart VS Code to apply changes.${NC}"
fi
