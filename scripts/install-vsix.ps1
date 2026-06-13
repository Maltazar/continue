# Install a Continue VSIX into VSCodium (Windows).
#
# Local VSIX (copy script next to the VSIX, or pass -VsixPath):
#   .\install-vsix.ps1
#   .\install-vsix.ps1 -VsixPath C:\Users\You\Downloads\continue-1.3.45.vsix
#
# From a GitHub Release (downloads continue-*.vsix from the release assets):
#   .\install-vsix.ps1 -GitHubRepo Maltazar/continue
#   .\install-vsix.ps1 -GitHubRepo Maltazar/continue -Version 1.3.45
#
#   .\install-vsix.ps1 -DryRun
#
# Environment:
#   $env:CONTINUE_VSCODIUM_CMD = "C:\Program Files\VSCodium\bin\codium.cmd"
#   $env:GITHUB_TOKEN            # optional; for private repos

param(
    [Parameter(Position = 0)]
    [string]$VsixPath,

    [string]$GitHubRepo,

    [string]$Version = "latest",

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

function Get-GitHubRequestHeaders {
    $headers = @{
        "User-Agent" = "continue-fork-installer"
        Accept       = "application/vnd.github+json"
    }

    if ($env:GITHUB_TOKEN) {
        $headers["Authorization"] = "Bearer $env:GITHUB_TOKEN"
    }

    return $headers
}

function Get-VsixFromGitHubRelease {
    param(
        [string]$Repo,
        [string]$Version
    )

    $headers = Get-GitHubRequestHeaders

    if ($Version -eq "latest") {
        $releaseUri = "https://api.github.com/repos/$Repo/releases/latest"
    } else {
        $tag = "continue-v$Version"
        $releaseUri = "https://api.github.com/repos/$Repo/releases/tags/$tag"
    }

    Write-ForkLog "Fetching release metadata from GitHub ($Repo, version: $Version)..."

    try {
        $release = Invoke-RestMethod -Uri $releaseUri -Headers $headers
    } catch {
        Write-ForkDie "Could not fetch GitHub release for $Repo (version: $Version). $_"
    }

    $asset = @($release.assets | Where-Object { $_.name -like "continue-*.vsix" } | Sort-Object name -Descending)[0]
    if (-not $asset) {
        Write-ForkDie "Release '$($release.tag_name)' has no continue-*.vsix asset."
    }

    $dest = Join-Path $env:TEMP $asset.name
    Write-ForkLog "Downloading $($asset.name) ($([math]::Round($asset.size / 1MB, 1)) MB)..."

    Invoke-WebRequest -Uri $asset.browser_download_url -OutFile $dest -Headers $headers -UseBasicParsing

    return $dest
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

if ($GitHubRepo -and $VsixPath) {
    Write-ForkDie "Use either -GitHubRepo or -VsixPath, not both."
}

if ($GitHubRepo) {
    $VsixPath = Get-VsixFromGitHubRelease -Repo $GitHubRepo -Version $Version
}

if (-not $VsixPath) {
    $latest = Get-ChildItem -Path $ScriptDir -Filter "continue-*.vsix" -ErrorAction SilentlyContinue |
        Sort-Object LastWriteTime -Descending |
        Select-Object -First 1

    if ($latest) {
        $VsixPath = $latest.FullName
    }
}

if (-not $VsixPath -or -not (Test-Path -LiteralPath $VsixPath)) {
    Write-ForkDie "VSIX not found. Pass -VsixPath, -GitHubRepo, or place continue-*.vsix next to this script."
}

$VsixPath = (Resolve-Path -LiteralPath $VsixPath).Path

if ($VsixPath -match "continue-(\d+\.\d+\.\d+)\.vsix$") {
    $InstalledVersion = $Matches[1]
} else {
    $InstalledVersion = "unknown"
}

$ExtDir = Join-Path $env:USERPROFILE ".vscode-oss\extensions"
$ExtensionsJson = Join-Path $ExtDir "extensions.json"

Write-ForkLog "VSIX:           $VsixPath"
Write-ForkLog "Version:        $InstalledVersion"
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
    Write-ForkLog "Continue $InstalledVersion registered in VSCodium."
    Write-ForkLog "Fully quit VSCodium (all windows), then reopen."
    exit 0
}

Write-ForkWarn "CLI finished but continue.continue not found in extensions.json yet."
Write-ForkDie "Install may have failed. Try manually: Extensions -> ... -> Install from VSIX..."
