# VS Code Extension Gallery Patcher (Windows)
# Usage: .\patch-vscode.ps1 -Domain "g.example.com"

param(
    [Parameter(Mandatory=$true)]
    [string]$Domain
)

# Strip trailing slash and protocol if provided
$Domain = $Domain -replace '/$', '' -replace '^https?://', ''

$PROXY_SERVICE = "https://$Domain/vscode/gallery"
$PROXY_ITEM = "https://$Domain/vscode/items"
$PROXY_CACHE = "https://$Domain/vscode/cache/index"
$PROXY_CONTROL = "https://$Domain/vscode/control"

$MS_SERVICE = "https://marketplace.visualstudio.com/_apis/public/gallery"
$MS_ITEM = "https://marketplace.visualstudio.com/items"
$MS_CACHE = "https://vscode.blob.core.windows.net/gallery/index"

Write-Host "=== VS Code Gallery Patcher ===" -ForegroundColor Cyan
Write-Host "Proxy domain: $Domain" -ForegroundColor Cyan

# Find product.json
$file = Get-ChildItem -Path "$env:LOCALAPPDATA\Programs\Microsoft VS Code" -Recurse -Filter "product.json" -ErrorAction SilentlyContinue | 
        Where-Object { $_.FullName -match "resources\\app\\product\.json$" } | 
        Select-Object -First 1

if (-not $file) {
    Write-Host "ERROR: product.json not found!" -ForegroundColor Red
    exit 1
}

Write-Host "Found: $($file.FullName)" -ForegroundColor Green

# Read file as raw text (preserves all original formatting)
try {
    $jsonText = [System.IO.File]::ReadAllText($file.FullName)
} catch {
    Write-Host "ERROR: Cannot read product.json!" -ForegroundColor Red
    Write-Host "Error: $_" -ForegroundColor Red
    exit 1
}

# Detect current state
$isProxy = $jsonText -notmatch '"serviceUrl"\s*:\s*"https://marketplace\.visualstudio\.com'

# Helper: replace JSON string value by key (preserves indentation and surrounding structure)
function Replace-JsonValue($text, $key, $newValue) {
    $escaped = [regex]::Escape($key)
    $pattern = '("' + $escaped + '"\s*:\s*)"[^"]*"'
    $replacement = '${1}"' + $newValue + '"'
    return [regex]::Replace($text, $pattern, $replacement)
}

# Helper: add key-value after existing key if missing
function Add-JsonValueAfter($text, $afterKey, $newKey, $newValue) {
    if ($text -match [regex]::Escape("`"$newKey`"")) {
        return (Replace-JsonValue $text $newKey $newValue)
    }
    $escaped = [regex]::Escape($afterKey)
    $pattern = '("' + $escaped + '"\s*:\s*"[^"]*")(,?)'
    $match = [regex]::Match($text, $pattern)
    if ($match.Success) {
        $pos = $match.Index
        $lineStart = $text.LastIndexOf("`n", $pos) + 1
        $indent = ""
        if ($text.Substring($lineStart) -match '^([\t ]+)') {
            $indent = $matches[1]
        }
        $insertion = $match.Value.TrimEnd(',') + ",`n" + $indent + "`"$newKey`": `"$newValue`""
        $text = $text.Substring(0, $match.Index) + $insertion + $text.Substring($match.Index + $match.Length)
    }
    return $text
}

# Show current gallery URL
if ($jsonText -match '"serviceUrl"\s*:\s*"([^"]*)"') {
    Write-Host "`nCurrent gallery: $($matches[1])" -ForegroundColor Yellow
}

# Decide action
if ($isProxy) {
    Write-Host "`nRestore to Microsoft Marketplace? (Y/N): " -ForegroundColor Yellow -NoNewline
    $choice = Read-Host
    
    if ($choice -eq "Y" -or $choice -eq "y") {
        $jsonText = Replace-JsonValue $jsonText "serviceUrl" $MS_SERVICE
        $jsonText = Replace-JsonValue $jsonText "itemUrl" $MS_ITEM
        $jsonText = Replace-JsonValue $jsonText "cacheUrl" $MS_CACHE
        $jsonText = Replace-JsonValue $jsonText "controlUrl" ""
        $action = "Restored to Microsoft"
    } else {
        Write-Host "Cancelled." -ForegroundColor Yellow
        exit 0
    }
} else {
    Write-Host "`nPatch to use proxy? (Y/N): " -ForegroundColor Yellow -NoNewline
    $choice = Read-Host
    
    if ($choice -eq "Y" -or $choice -eq "y") {
        $jsonText = Replace-JsonValue $jsonText "serviceUrl" $PROXY_SERVICE
        $jsonText = Replace-JsonValue $jsonText "itemUrl" $PROXY_ITEM
        $jsonText = Replace-JsonValue $jsonText "cacheUrl" $PROXY_CACHE
        $jsonText = Add-JsonValueAfter $jsonText "cacheUrl" "controlUrl" $PROXY_CONTROL
        $action = "Patched to proxy"
    } else {
        Write-Host "Cancelled." -ForegroundColor Yellow
        exit 0
    }
}

# Backup
$backup = "$($file.FullName).backup_$(Get-Date -Format 'yyyyMMdd_HHmmss')"
Copy-Item $file.FullName $backup -Force
Write-Host "`nBackup: $backup" -ForegroundColor Gray

# Save (UTF-8 without BOM, same as original)
try {
    $utf8NoBom = New-Object System.Text.UTF8Encoding $false
    [System.IO.File]::WriteAllText($file.FullName, $jsonText, $utf8NoBom)
    
    Write-Host "`nDONE! $action" -ForegroundColor Green
    Write-Host "Restart VS Code to apply changes." -ForegroundColor Cyan
} catch {
    Write-Host "`nERROR: Failed to save product.json!" -ForegroundColor Red
    Write-Host "Error: $_" -ForegroundColor Red
    Write-Host "Backup is safe at: $backup" -ForegroundColor Yellow
    exit 1
}
