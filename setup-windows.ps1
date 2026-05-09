# setup-windows.ps1 — Windows setup for agent-teams (WSL2 + Ubuntu)
# Run as Administrator in PowerShell:
#   Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass
#   .\setup-windows.ps1
#
# What this does:
#   1. Enable WSL2 and Virtual Machine Platform
#   2. Install Ubuntu (default distro)
#   3. Clone agent-teams repo into ~/agent-teams inside Ubuntu
#   4. Run install.sh inside Ubuntu

#Requires -RunAsAdministrator

$ErrorActionPreference = "Stop"

function Write-Step($msg) {
    Write-Host ""
    Write-Host "==> $msg" -ForegroundColor Cyan
}

function Write-Ok($msg) {
    Write-Host "  OK  $msg" -ForegroundColor Green
}

function Write-Info($msg) {
    Write-Host "  i   $msg" -ForegroundColor Yellow
}

# ──────────────────────────────────────────────────────────────
# 1. Check Windows version (WSL2 requires Windows 10 2004+ or Windows 11)
# ──────────────────────────────────────────────────────────────
Write-Step "Checking Windows version..."
$build = [System.Environment]::OSVersion.Version.Build
if ($build -lt 19041) {
    Write-Host "Error: WSL2 requires Windows 10 version 2004 (build 19041) or later." -ForegroundColor Red
    Write-Host "       Current build: $build" -ForegroundColor Red
    Write-Host "       Update Windows via Settings > Windows Update." -ForegroundColor Red
    exit 1
}
Write-Ok "Windows build $build — compatible"

# ──────────────────────────────────────────────────────────────
# 2. Enable WSL and Virtual Machine Platform features
# ──────────────────────────────────────────────────────────────
Write-Step "Enabling WSL and Virtual Machine Platform features..."

$wslFeature = Get-WindowsOptionalFeature -Online -FeatureName Microsoft-Windows-Subsystem-Linux
$vmFeature  = Get-WindowsOptionalFeature -Online -FeatureName VirtualMachinePlatform

$rebootNeeded = $false

if ($wslFeature.State -ne "Enabled") {
    Write-Info "Enabling Microsoft-Windows-Subsystem-Linux..."
    Enable-WindowsOptionalFeature -Online -FeatureName Microsoft-Windows-Subsystem-Linux -NoRestart | Out-Null
    $rebootNeeded = $true
} else {
    Write-Ok "WSL feature already enabled"
}

if ($vmFeature.State -ne "Enabled") {
    Write-Info "Enabling VirtualMachinePlatform..."
    Enable-WindowsOptionalFeature -Online -FeatureName VirtualMachinePlatform -NoRestart | Out-Null
    $rebootNeeded = $true
} else {
    Write-Ok "VirtualMachinePlatform already enabled"
}

if ($rebootNeeded) {
    Write-Host ""
    Write-Host "  A reboot is required to finish enabling WSL2 features." -ForegroundColor Yellow
    Write-Host "  After rebooting, run this script again to continue setup." -ForegroundColor Yellow
    $ans = Read-Host "  Reboot now? [y/N]"
    if ($ans -match "^[Yy]$") {
        Restart-Computer -Force
    } else {
        Write-Host "  Please reboot manually, then re-run this script." -ForegroundColor Yellow
        exit 0
    }
}

# ──────────────────────────────────────────────────────────────
# 3. Set WSL default version to 2
# ──────────────────────────────────────────────────────────────
Write-Step "Setting WSL default version to 2..."
wsl --set-default-version 2 2>&1 | Out-Null
Write-Ok "WSL default = 2"

# ──────────────────────────────────────────────────────────────
# 4. Install Ubuntu if not already installed
# ──────────────────────────────────────────────────────────────
Write-Step "Checking Ubuntu installation..."
$distros = wsl --list --quiet 2>&1
$ubuntuInstalled = $distros | Where-Object { $_ -match "Ubuntu" }

if (-not $ubuntuInstalled) {
    Write-Info "Ubuntu not found — installing from Microsoft Store (this may take a few minutes)..."
    wsl --install -d Ubuntu
    Write-Host ""
    Write-Host "  Ubuntu installed. You will be prompted to create a UNIX username and password." -ForegroundColor Cyan
    Write-Host "  After setup completes, close the Ubuntu window and re-run this script." -ForegroundColor Cyan
    Write-Host "  Press Enter to open Ubuntu now..."
    Read-Host
    exit 0
} else {
    Write-Ok "Ubuntu already installed"
}

# ──────────────────────────────────────────────────────────────
# 5. Install git inside Ubuntu (needed to clone)
# ──────────────────────────────────────────────────────────────
Write-Step "Ensuring git is available inside Ubuntu..."
wsl -d Ubuntu -- bash -c "command -v git >/dev/null 2>&1 || (sudo apt-get update -qq && sudo apt-get install -y git)"
Write-Ok "git ready"

# ──────────────────────────────────────────────────────────────
# 6. Clone or update the repo inside Ubuntu home
# ──────────────────────────────────────────────────────────────
Write-Step "Setting up agent-teams repo inside Ubuntu..."

$repoUrl   = "https://github.com/itseed/agent-teams.git"
$targetDir = "~/agent-teams"

$cloneResult = wsl -d Ubuntu -- bash -c "
  if [ -d '$targetDir/.git' ]; then
    echo 'exists'
  else
    git clone '$repoUrl' '$targetDir' 2>&1 && echo 'cloned'
  fi
"

if ($cloneResult -match "exists") {
    Write-Info "Repo already exists at $targetDir — pulling latest..."
    wsl -d Ubuntu -- bash -c "cd $targetDir && git pull --ff-only"
    Write-Ok "Repo updated"
} elseif ($cloneResult -match "cloned") {
    Write-Ok "Repo cloned to $targetDir"
} else {
    Write-Host "  Clone output: $cloneResult" -ForegroundColor Yellow
    Write-Host ""
    Write-Host "  Could not clone automatically. Clone manually inside Ubuntu:" -ForegroundColor Yellow
    Write-Host "    git clone $repoUrl ~/agent-teams" -ForegroundColor White
    exit 1
}

# ──────────────────────────────────────────────────────────────
# 7. Run install.sh inside Ubuntu
# ──────────────────────────────────────────────────────────────
Write-Step "Running install.sh inside Ubuntu..."
wsl -d Ubuntu -- bash -c "cd ~/agent-teams && bash install.sh"

# ──────────────────────────────────────────────────────────────
# Done
# ──────────────────────────────────────────────────────────────
Write-Host ""
Write-Host "Setup complete!" -ForegroundColor Green
Write-Host ""
Write-Host "To start the agent team, open Ubuntu terminal and run:" -ForegroundColor Cyan
Write-Host "  cd ~/agent-teams"
Write-Host "  ./start-team.sh"
Write-Host ""
Write-Host "Or open Ubuntu directly from Start Menu > Ubuntu"
