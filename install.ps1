#Requires -Version 5.1
<#
.SYNOPSIS
    Claude Code Secure Installer for Windows
.DESCRIPTION
    Installs Claude Code end-to-end on Windows: Git, Node.js, Claude Code CLI,
    authentication, and optionally the OpenAI Codex plugin.
.NOTES
    Run as a regular user (NOT as Administrator).
    Script will request elevation only when strictly necessary.
#>

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# ── Constants ─────────────────────────────────────────────────────────────────
$MIN_NODE_MAJOR  = 18
$MIN_NODE_MINOR  = 18
$CLAUDE_PKG      = "@anthropic-ai/claude-code"
$CODEX_MKT       = "openai/codex-plugin-cc"
$LOG_FILE        = Join-Path $env:TEMP ("claude-install-{0}.log" -f (Get-Date -Format "yyyyMMdd-HHmmss"))
$NPM_REGISTRY    = "https://registry.npmjs.org/"

# ── Helpers ───────────────────────────────────────────────────────────────────
function Write-Step  { param($msg) Write-Host "  [INFO]  $msg" -ForegroundColor Cyan }
function Write-OK    { param($msg) Write-Host "  [OK]    $msg" -ForegroundColor Green }
function Write-Warn  { param($msg) Write-Host "  [WARN]  $msg" -ForegroundColor Yellow }
function Write-Fail  { param($msg) Write-Host "  [ERROR] $msg" -ForegroundColor Red }
function Abort       { param($msg) Write-Fail $msg; exit 1 }

function Test-Command {
    param($Name)
    $null -ne (Get-Command $Name -ErrorAction SilentlyContinue)
}

function Refresh-Path {
    $env:PATH = [System.Environment]::GetEnvironmentVariable("PATH", "Machine") + ";" +
                [System.Environment]::GetEnvironmentVariable("PATH", "User")
}

function Get-NodeVersion {
    try {
        $raw = (node -e "process.stdout.write(process.version)" 2>$null)
        if ($raw -match 'v(\d+)\.(\d+)') {
            return @{ Major = [int]$Matches[1]; Minor = [int]$Matches[2] }
        }
    } catch {}
    return $null
}

function Test-NodeVersionOk {
    $v = Get-NodeVersion
    if ($null -eq $v) { return $false }
    if ($v.Major -gt $MIN_NODE_MAJOR) { return $true }
    if ($v.Major -eq $MIN_NODE_MAJOR -and $v.Minor -ge $MIN_NODE_MINOR) { return $true }
    return $false
}

function Download-Verified {
    param(
        [string]$Url,
        [string]$Dest,
        [string]$Description
    )
    Write-Step "Downloading $Description..."
    $wc = New-Object System.Net.WebClient
    $wc.Headers.Add("User-Agent", "claude-code-installer/1.0")
    try {
        $wc.DownloadFile($Url, $Dest)
    } catch {
        Abort "Download failed: $_"
    }
    if (-not (Test-Path $Dest) -or (Get-Item $Dest).Length -eq 0) {
        Abort "Downloaded file is empty or missing: $Dest"
    }
    Write-OK "Downloaded: $Dest"
}

# ── Banner ────────────────────────────────────────────────────────────────────
function Show-Banner {
    Write-Host ""
    Write-Host "  ╔══════════════════════════════════════════╗" -ForegroundColor Cyan
    Write-Host "  ║      Claude Code — Secure Installer      ║" -ForegroundColor Cyan
    Write-Host "  ║            Windows Edition               ║" -ForegroundColor Cyan
    Write-Host "  ╚══════════════════════════════════════════╝" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "  Log file: $LOG_FILE"
    Write-Host ""
}

# ── Step 1: Execution Policy ──────────────────────────────────────────────────
function Ensure-ExecutionPolicy {
    Write-Step "Checking PowerShell execution policy..."
    $policy = Get-ExecutionPolicy -Scope Process
    if ($policy -eq 'Restricted' -or $policy -eq 'Undefined') {
        # FIX (MEDIUM): Use Process scope — expires when this session ends, never persists to the user profile.
        Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass -Force
        Write-OK "Execution policy set to Bypass for this session only (Process scope)."
    } else {
        Write-OK "Execution policy OK: $policy"
    }
}

# ── Step 2: Check/Install Git ─────────────────────────────────────────────────
function Ensure-Git {
    Write-Step "Checking for Git..."
    if (Test-Command "git") {
        Write-OK "Git found: $(git --version)"
        return
    }
    Write-Warn "Git not found. Installing via winget..."
    try {
        winget install --id Git.Git -e --source winget --silent --accept-package-agreements --accept-source-agreements 2>&1 | Out-File $LOG_FILE -Append
        Refresh-Path
    } catch {
        Write-Warn "winget install failed. Trying direct EXE download with signature verification..."
        # FIX (LOW): use a random temp dir to prevent predictable path races
        $gitTempDir   = Join-Path ([System.IO.Path]::GetTempPath()) ([System.IO.Path]::GetRandomFileName())
        New-Item -ItemType Directory -Path $gitTempDir -ErrorAction Stop | Out-Null
        $gitInstaller = Join-Path $gitTempDir ([System.IO.Path]::GetRandomFileName() + ".exe")

        $apiResp = Invoke-RestMethod "https://api.github.com/repos/git-for-windows/git/releases/latest" -ErrorAction Stop
        $asset   = $apiResp.assets | Where-Object { $_.name -match "Git-.*-64-bit\.exe$" } | Select-Object -First 1
        Download-Verified -Url $asset.browser_download_url -Dest $gitInstaller -Description "Git for Windows"

        # FIX (HIGH): verify Authenticode signature before executing
        Write-Step "Verifying Git installer signature..."
        $sig = Get-AuthenticodeSignature $gitInstaller
        if ($sig.Status -ne 'Valid') {
            Remove-Item $gitTempDir -Recurse -Force -ErrorAction SilentlyContinue
            Abort "Git installer signature invalid (status: $($sig.Status)) — aborting for security."
        }
        if ($sig.SignerCertificate.Subject -notmatch 'Johannes Schindelin|Git for Windows') {
            Remove-Item $gitTempDir -Recurse -Force -ErrorAction SilentlyContinue
            Abort "Git installer signer unexpected: $($sig.SignerCertificate.Subject) — aborting for security."
        }
        Write-OK "Signature verified: $($sig.SignerCertificate.Subject)"

        Start-Process -FilePath $gitInstaller -ArgumentList "/VERYSILENT /NORESTART /NOCANCEL" -Wait
        Remove-Item $gitTempDir -Recurse -Force -ErrorAction SilentlyContinue
        Refresh-Path
    }
    if (-not (Test-Command "git")) { Abort "Git installation failed." }
    Write-OK "Git installed: $(git --version)"
}

# ── Step 3: Check/Install Node.js ─────────────────────────────────────────────
function Ensure-Node {
    Write-Step "Checking for Node.js (requires v${MIN_NODE_MAJOR}.${MIN_NODE_MINOR}+)..."

    if (Test-NodeVersionOk) {
        Write-OK "Node.js $(node --version) — meets requirements"
        return
    }

    if (Test-Command "node") {
        Write-Warn "Node.js $(node --version) is too old. Need v${MIN_NODE_MAJOR}.${MIN_NODE_MINOR}+."
    } else {
        Write-Warn "Node.js not found."
    }

    # Try winget first (no admin needed for user scope)
    Write-Step "Installing Node.js LTS via winget..."
    try {
        winget install --id OpenJS.NodeJS.LTS -e --source winget --silent --accept-package-agreements --accept-source-agreements 2>&1 | Out-File $LOG_FILE -Append
        Refresh-Path
    } catch {
        Write-Warn "winget failed. Downloading Node.js MSI directly..."
        # FIX (LOW): random dir name prevents predictable temp path race
        $nodeDir      = Join-Path ([System.IO.Path]::GetTempPath()) ([System.IO.Path]::GetRandomFileName())
        New-Item -ItemType Directory -Path $nodeDir -ErrorAction Stop | Out-Null

        # Fetch current LTS version from official index
        $nodeIndex = Invoke-RestMethod "https://nodejs.org/dist/index.json" -ErrorAction Stop
        $lts       = $nodeIndex | Where-Object { $_.lts -ne $false } | Select-Object -First 1
        $version   = $lts.version
        $msiUrl    = "https://nodejs.org/dist/$version/node-$version-x64.msi"
        $shaUrl    = "https://nodejs.org/dist/$version/SHASUMS256.txt"
        $msiPath   = Join-Path $nodeDir "node.msi"
        $shaPath   = Join-Path $nodeDir "SHASUMS256.txt"

        Download-Verified -Url $msiUrl  -Dest $msiPath -Description "Node.js $version"
        Download-Verified -Url $shaUrl  -Dest $shaPath -Description "Node.js SHA256 checksums"

        # Verify checksum
        Write-Step "Verifying SHA256 checksum..."
        $actual   = (Get-FileHash $msiPath -Algorithm SHA256).Hash.ToLower()
        $msiFile  = "node-$version-x64.msi"
        $expected = (Select-String -Path $shaPath -Pattern $msiFile | Select-Object -First 1).Line.Split()[0].ToLower()

        if ($actual -ne $expected) {
            Remove-Item $nodeDir -Recurse -Force
            Abort "SHA256 mismatch! Expected: $expected  Got: $actual — Aborting for security."
        }
        Write-OK "Checksum verified."

        Start-Process msiexec.exe -ArgumentList "/i `"$msiPath`" /quiet /norestart ADDLOCAL=ALL" -Wait
        Remove-Item $nodeDir -Recurse -Force -ErrorAction SilentlyContinue
        Refresh-Path
    }

    if (-not (Test-NodeVersionOk)) { Abort "Node.js installation failed or version still too old. Install from https://nodejs.org" }
    Write-OK "Node.js ready: $(node --version)"
}

# ── Step 4: Install Claude Code ───────────────────────────────────────────────
function Install-ClaudeCode {
    Write-Step "Installing Claude Code from npm (official registry)..."

    # FIX (LOW): resolve absolute path to npm to prevent PATH hijacking
    $npmExe = (Get-Command npm -CommandType Application -ErrorAction Stop).Source
    Write-Step "Using npm at: $npmExe"

    # Force official registry for security
    $npmArgs = @("install", "-g", $CLAUDE_PKG, "--registry", $NPM_REGISTRY)
    $result  = & $npmExe @npmArgs 2>&1
    $result | Out-File $LOG_FILE -Append

    Refresh-Path
    if (-not (Test-Command "claude")) { Abort "Claude Code installation failed. Check log: $LOG_FILE" }
    Write-OK "Claude Code installed: $(claude --version)"
}

# ── Step 5: Verify Installation ───────────────────────────────────────────────
function Verify-Install {
    Write-Step "Verifying installation..."
    $failed = $false
    foreach ($cmd in @("node","npm","claude")) {
        if (Test-Command $cmd) {
            Write-OK "$cmd found"
        } else {
            Write-Fail "$cmd NOT found"
            $failed = $true
        }
    }
    if ($failed) { Abort "Verification failed. Check log: $LOG_FILE" }

    Write-Host ""
    Write-Host "    node   -> $(node --version)"    -ForegroundColor White
    Write-Host "    npm    -> $(npm --version)"     -ForegroundColor White
    Write-Host "    claude -> $(claude --version)"  -ForegroundColor White
}

# ── Step 6: Authenticate ──────────────────────────────────────────────────────
function Start-Auth {
    Write-Host ""
    Write-Step "Starting Claude Code authentication..."
    Write-Host ""
    Write-Host "  You will be redirected to claude.ai to log in." -ForegroundColor White
    Write-Host "  Make sure you have a Claude account ready." -ForegroundColor White
    Write-Host ""
    Read-Host "  Press ENTER to open the browser login (Ctrl+C to skip)"
    try {
        claude login
    } catch {
        Write-Warn "Login skipped or failed. Run 'claude login' manually later."
    }
}

# ── Step 7: Optional Codex Plugin ────────────────────────────────────────────
function Install-CodexPlugin {
    Write-Host ""
    $answer = Read-Host "  Install the OpenAI Codex plugin for Claude Code? [y/N]"
    if ($answer -match '^[Yy]') {
        Write-Step "Adding OpenAI Codex marketplace..."
        try {
            claude plugin marketplace add $CODEX_MKT 2>&1 | Out-File $LOG_FILE -Append
            claude plugin install "codex@openai-codex" 2>&1 | Out-File $LOG_FILE -Append
            Write-OK "Codex plugin installed. Restart Claude Code and run /codex:setup"
        } catch {
            Write-Warn "Codex plugin install failed. Retry manually: claude plugin marketplace add $CODEX_MKT"
        }
    } else {
        Write-Step "Skipping Codex plugin."
    }
}

# ── Main ──────────────────────────────────────────────────────────────────────
Show-Banner
Ensure-ExecutionPolicy
Ensure-Git
Ensure-Node
Install-ClaudeCode
Verify-Install
Start-Auth
Install-CodexPlugin

Write-Host ""
Write-Host "  ✓ Claude Code setup complete!" -ForegroundColor Green
Write-Host ""
Write-Host "  Run 'claude' to start." -ForegroundColor White
Write-Host "  Log saved to: $LOG_FILE" -ForegroundColor Gray
Write-Host ""
