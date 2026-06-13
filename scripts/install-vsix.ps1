# Install a Continue VSIX into VSCodium (Windows).
#
# Copy this script next to a VSIX and run from PowerShell:
#   .\install-vsix.ps1
#   .\install-vsix.ps1 -VsixPath C:\Users\You\Downloads\continue-1.3.40.vsix
#   .\install-vsix.ps1 -DryRun
#
# With no -VsixPath, installs the newest continue-*.vsix in this script's directory.
#
# Environment override:
#   $env:CONTINUE_VSCODIUM_CMD = "C:\Program Files\VSCodium\bin\codium.cmd"

param(
    [Parameter(Position = 0)]
    [string]$VsixPath,

    [switch]$DryRun,

    [string]$VscodiumCmd = $env:CONTINUE_VSCODIUM_CMD
)

$ErrorActionPreference = "Stop"

function Write-ForkLog([string]$Message) {
    Write-Host "[fork] $Message"
}

function Write-ForkWarn([string]$Message) {
    Write-Warning "[fork] $Message"
}

function Write-ForkDie([string]$Message) {
    Write-Error "[fork] $Message"
}

function Invoke-Vscodium {
    param(
        [Parameter(ValueFromRemainingArguments = $true)]
        [string[]]$Args
    )

    Push-Location $env:TEMP
    try {
        & $VscodiumCmd @Args | Out-Null
        if ($null -ne $LASTEXITCODE) {
            return $LASTEXITCODE
        }
        return 0
    } finally {
        Pop-Location
    }
}

if (-not $VscodiumCmd) {
    $VscodiumCmd = Join-Path ${env:ProgramFiles} "VSCodium\bin\codium.cmd"
}

if (-not (Test-Path $VscodiumCmd)) {
    Write-ForkDie "VSCodium CLI not found: $VscodiumCmd. Set CONTINUE_VSCODIUM_CMD or install VSCodium."
}

$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path

if (-not $VsixPath) {
    $latest = Get-ChildItem -Path $ScriptDir -Filter "continue-*.vsix" -ErrorAction SilentlyContinue |
        Sort-Object LastWriteTime -Descending |
        Select-Object -First 1

    if ($latest) {
        $VsixPath = $latest.FullName
    }
}

if (-not $VsixPath -or -not (Test-Path -LiteralPath $VsixPath)) {
    Write-ForkDie "VSIX not found. Pass -VsixPath or place continue-*.vsix next to this script."
}

$VsixPath = (Resolve-Path -LiteralPath $VsixPath).Path

if ($VsixPath -match "continue-(\d+\.\d+\.\d+)\.vsix$") {
    $Version = $Matches[1]
} else {
    $Version = "unknown"
}

$ExtDir = Join-Path $env:USERPROFILE ".vscode-oss\extensions"
$ExtensionsJson = Join-Path $ExtDir "extensions.json"

Write-ForkLog "VSIX:           $VsixPath"
Write-ForkLog "Version:        $Version"
Write-ForkLog "Extensions dir: $ExtDir"
Write-ForkLog "VSCodium CLI:   $VscodiumCmd"

if ($DryRun) {
    Write-ForkLog "Dry run only. No changes made."
    exit 0
}

$vscodiumProcesses = Get-Process -Name "VSCodium" -ErrorAction SilentlyContinue
if ($vscodiumProcesses) {
    Write-ForkLog "Closing VSCodium to clear extension host state..."
    $vscodiumProcesses | Stop-Process -Force
    Start-Sleep -Seconds 2
}

Write-ForkLog "Cleaning up leftover Continue installs..."

Invoke-Vscodium --uninstall-extension Continue.continue | Out-Null

if (Test-Path $ExtDir) {
    Get-ChildItem -Path $ExtDir -Directory -Filter "continue.continue-*" -ErrorAction SilentlyContinue |
        Remove-Item -Recurse -Force -ErrorAction SilentlyContinue
    Get-ChildItem -Path $ExtDir -Directory -Filter "Continue.continue-*" -ErrorAction SilentlyContinue |
        Remove-Item -Recurse -Force -ErrorAction SilentlyContinue
}

if (Test-Path $ExtensionsJson) {
    $raw = Get-Content -LiteralPath $ExtensionsJson -Raw
    $entries = @($raw | ConvertFrom-Json)
    $kept = @($entries | Where-Object { $_.identifier.id -ne "continue.continue" })

    if ($kept.Count -lt $entries.Count) {
        ($kept | ConvertTo-Json -Compress -Depth 20) | Set-Content -LiteralPath $ExtensionsJson -NoNewline
        Write-ForkLog "Removed $($entries.Count - $kept.Count) stale Continue entry(ies) from extensions.json"
    }
}

Write-ForkLog "Installing via VSCodium CLI..."
$installExit = Invoke-Vscodium --install-extension $VsixPath --force
if ($installExit -ne 0) {
    Write-ForkWarn "codium --install-extension exited with code $installExit"
}

if ((Test-Path $ExtensionsJson) -and (Select-String -LiteralPath $ExtensionsJson -Pattern '"id":"continue.continue"' -Quiet)) {
    Write-ForkLog "Continue $Version registered in VSCodium."
    Write-ForkLog "Fully quit VSCodium (all windows), then reopen."
    exit 0
}

Write-ForkWarn "CLI finished but continue.continue not found in extensions.json yet."
Write-ForkDie "Install may have failed. Try manually: Extensions -> ... -> Install from VSIX..."
