<#
.SYNOPSIS
    Installs IIS and publishes the health card site. Identical on AWS, Azure and GCP.

.DESCRIPTION
    Step 1. Run in an ELEVATED PowerShell window.
    Installs the Web Server role, copies .\site\ to C:\inetpub\HealthCard, creates a
    dedicated application pool and site on the port you choose, and copies your
    deployment.json somewhere the collector can find it.

.EXAMPLE
    .\1-Setup-IIS.ps1
    .\1-Setup-IIS.ps1 -Port 8080
#>

[CmdletBinding()]
param(
    [string]$SiteName     = 'HealthCard',
    [int]   $Port         = 80,
    [string]$PhysicalPath = 'C:\inetpub\HealthCard'
)

$ErrorActionPreference = 'Stop'

function Step { param($m) Write-Host "`n==> $m" -ForegroundColor Cyan }
function Ok   { param($m) Write-Host "    [ok] $m" -ForegroundColor Green }
function Warn { param($m) Write-Host "    [!!] $m" -ForegroundColor Yellow }

# --- 0. Elevation ---------------------------------------------------------------
$id = [Security.Principal.WindowsIdentity]::GetCurrent()
if (-not (New-Object Security.Principal.WindowsPrincipal($id)).IsInRole(
        [Security.Principal.WindowsBuiltInRole]::Administrator)) {
    throw "This script needs an elevated session. Right-click PowerShell and choose 'Run as administrator'."
}
Ok "Running elevated as $($id.Name)"

# --- 1. Install the web server role ---------------------------------------------
Step "Installing the Web Server (IIS) role"
$result = Install-WindowsFeature -Name Web-Server, Web-Mgmt-Console, Web-Mgmt-Tools -IncludeManagementTools
if (-not $result.Success) { throw "Install-WindowsFeature failed. Exit code: $($result.ExitCode)" }
Ok "Role installed. Restart needed: $($result.RestartNeeded)"

if ((Get-Service W3SVC).Status -ne 'Running') { Start-Service W3SVC; Start-Sleep 2 }
Ok "W3SVC is $((Get-Service W3SVC).Status)"

# --- 2. Windows Firewall (the inner firewall) -----------------------------------
Step "Allowing inbound TCP $Port through Windows Firewall"
$ruleName = "Lab HTTP $Port In"
if (-not (Get-NetFirewallRule -DisplayName $ruleName -ErrorAction SilentlyContinue)) {
    New-NetFirewallRule -DisplayName $ruleName -Direction Inbound -Protocol TCP `
        -LocalPort $Port -Action Allow | Out-Null
    Ok "Created inbound rule for TCP $Port"
} else {
    Ok "Inbound rule for TCP $Port already exists"
}

# --- 3. Copy the files ----------------------------------------------------------
$repoRoot = Split-Path -Parent $PSScriptRoot
$source   = Join-Path $repoRoot 'site'
if (-not (Test-Path $source)) {
    throw "Could not find '$source'. Run this script from inside the extracted repository folder."
}

Step "Copying files to $PhysicalPath"
New-Item -Path $PhysicalPath -ItemType Directory -Force | Out-Null
Copy-Item -Path (Join-Path $source '*') -Destination $PhysicalPath -Recurse -Force
New-Item -Path (Join-Path $PhysicalPath 'data') -ItemType Directory -Force | Out-Null
Ok "Copied $((Get-ChildItem $PhysicalPath -Recurse -File).Count) files"

# --- 4. deployment.json ---------------------------------------------------------
Step "Installing your deployment facts"
$deployment = Join-Path $repoRoot 'deployment.json'
if (-not (Test-Path $deployment)) { throw "deployment.json not found at $deployment" }

try { $d = Get-Content $deployment -Raw | ConvertFrom-Json }
catch { throw "deployment.json is not valid JSON. Fix the file and re-run. $($_.Exception.Message)" }

if ($d.owner -eq 'your-name-here') {
    Warn "deployment.json still says owner = 'your-name-here'. Edit it, then re-run this script."
}
New-Item -Path 'C:\LabTools' -ItemType Directory -Force | Out-Null
Copy-Item $deployment -Destination 'C:\LabTools\deployment.json' -Force
Ok "Cloud: $($d.cloud) · Region: $($d.region) · Zone: $($d.zone) · Owner: $($d.owner)"

# --- 5. Free the port if the default site holds it -------------------------------
Import-Module WebAdministration
$default = Get-Website -Name 'Default Web Site' -ErrorAction SilentlyContinue
if ($default -and $default.State -eq 'Started' -and
    ($default.bindings.Collection | Where-Object { $_.bindingInformation -like "*:$Port`:*" })) {
    Step "Stopping 'Default Web Site' so port $Port is free"
    Stop-Website -Name 'Default Web Site'
    Ok "Stopped (not deleted)"
}

# --- 6. App pool and site --------------------------------------------------------
Step "Creating application pool and site '$SiteName' on port $Port"
if (-not (Test-Path "IIS:\AppPools\$SiteName")) { New-WebAppPool -Name $SiteName | Out-Null }
Set-ItemProperty "IIS:\AppPools\$SiteName" -Name managedRuntimeVersion -Value ''  # static files only

if (Get-Website -Name $SiteName -ErrorAction SilentlyContinue) {
    Warn "Site exists. Recreating it so the binding is correct."
    Remove-Website -Name $SiteName
}
New-Website -Name $SiteName -Port $Port -PhysicalPath $PhysicalPath -ApplicationPool $SiteName | Out-Null
Start-Website -Name $SiteName
Ok "Site started"

# --- 7. Verify ------------------------------------------------------------------
Step "Requesting the site locally"
try {
    $r = Invoke-WebRequest -Uri "http://localhost:$Port/" -UseBasicParsing -TimeoutSec 15
    Ok "HTTP $($r.StatusCode) from http://localhost:$Port/"
} catch {
    Warn "Local request failed: $($_.Exception.Message)"
}

Write-Host "`nDeployed to $PhysicalPath on port $Port." -ForegroundColor Green
Write-Host "The page will show a collector error until you run .\2-Collect-Status.ps1 — that is expected." -ForegroundColor Gray
Write-Host "Your cloud's firewall must also allow port $Port before your laptop can reach it." -ForegroundColor Gray
