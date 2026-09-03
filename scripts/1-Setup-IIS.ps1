# Step 1 - Install IIS and publish the Health Card website

[CmdletBinding()]
param(
    [string]$SiteName     = 'HealthCard',
    [int]   $Port         = 80,
    [string]$PhysicalPath = 'C:\inetpub\HealthCard'
)

$ErrorActionPreference = "Stop"

# --- 0. Administrator check -----------------------------------------------------
$id = [Security.Principal.WindowsIdentity]::GetCurrent()
$principal = New-Object Security.Principal.WindowsPrincipal($id)
if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Write-Host "ERROR: PowerShell must be running as Administrator." -ForegroundColor Red
    Write-Host "Close this window, open PowerShell as Administrator, and run the script again."
    exit 1
}

Write-Host ""
Write-Host "=============================================" -ForegroundColor Cyan
Write-Host "       Health Card IIS Setup" -ForegroundColor Cyan
Write-Host "=============================================" -ForegroundColor Cyan
Write-Host ""
Write-Host "[OK] Running as Administrator" -ForegroundColor Green

# --- 1. Install IIS -------------------------------------------------------------
Write-Host ""
Write-Host "==> Installing IIS..." -ForegroundColor Cyan
$result = Install-WindowsFeature -Name Web-Server, Web-Mgmt-Console, Web-Mgmt-Tools -IncludeManagementTools
if (-not $result.Success) {
    Write-Host "ERROR: IIS installation failed." -ForegroundColor Red
    exit 1
}
Write-Host "[OK] IIS installed" -ForegroundColor Green

# --- 2. Start IIS service -------------------------------------------------------
Write-Host ""
Write-Host "==> Starting IIS service..." -ForegroundColor Cyan
if ((Get-Service W3SVC).Status -ne "Running") {
    Start-Service W3SVC
    Start-Sleep -Seconds 2
}
Write-Host "[OK] W3SVC status: $((Get-Service W3SVC).Status)" -ForegroundColor Green

# --- 3. Windows Firewall --------------------------------------------------------
Write-Host ""
Write-Host "==> Configuring Windows Firewall for TCP $Port..." -ForegroundColor Cyan
$ruleName = "Lab HTTP $Port In"
if (-not (Get-NetFirewallRule -DisplayName $ruleName -ErrorAction SilentlyContinue)) {
    New-NetFirewallRule -DisplayName $ruleName -Direction Inbound `
        -Protocol TCP -LocalPort $Port -Action Allow | Out-Null
    Write-Host "[OK] Windows Firewall allows TCP $Port" -ForegroundColor Green
} else {
    Write-Host "[OK] Windows Firewall rule already exists" -ForegroundColor Green
}

# --- 4. Find and copy website files ---------------------------------------------
Write-Host ""
Write-Host "==> Finding website files..." -ForegroundColor Cyan
$repoRoot = Split-Path -Parent $PSScriptRoot
$source   = Join-Path $repoRoot "site"
if (-not (Test-Path $source)) {
    Write-Host "ERROR: Website folder was not found: $source" -ForegroundColor Red
    exit 1
}
Write-Host "[OK] Website folder found: $source" -ForegroundColor Green

Write-Host ""
Write-Host "==> Publishing website to $PhysicalPath..." -ForegroundColor Cyan
New-Item -Path $PhysicalPath -ItemType Directory -Force | Out-Null
Copy-Item -Path (Join-Path $source "*") -Destination $PhysicalPath -Recurse -Force
New-Item -Path (Join-Path $PhysicalPath "data") -ItemType Directory -Force | Out-Null
$fileCount = (Get-ChildItem $PhysicalPath -Recurse -File).Count
Write-Host "[OK] Copied $fileCount files" -ForegroundColor Green

# --- 5. Read and install deployment.json ----------------------------------------
Write-Host ""
Write-Host "==> Reading deployment.json..." -ForegroundColor Cyan
$deploymentPath = Join-Path $repoRoot "deployment.json"
if (-not (Test-Path $deploymentPath)) {
    Write-Host "ERROR: deployment.json was not found: $deploymentPath" -ForegroundColor Red
    exit 1
}
try {
    $d = Get-Content $deploymentPath -Raw | ConvertFrom-Json
} catch {
    Write-Host "ERROR: deployment.json contains invalid JSON." -ForegroundColor Red
    Write-Host $_.Exception.Message -ForegroundColor Red
    exit 1
}
if ($d.owner -eq "your-name-here") {
    Write-Host "WARNING: deployment.json still contains owner = your-name-here" -ForegroundColor Yellow
    Write-Host "Edit deployment.json with your information before continuing." -ForegroundColor Yellow
}

Write-Host ""
Write-Host "==> Installing deployment information..." -ForegroundColor Cyan
New-Item -Path "C:\LabTools" -ItemType Directory -Force | Out-Null
Copy-Item $deploymentPath -Destination "C:\LabTools\deployment.json" -Force
Write-Host "[OK] deployment.json copied to C:\LabTools" -ForegroundColor Green
Write-Host "Cloud   : $($d.cloud)" -ForegroundColor Gray
Write-Host "Region  : $($d.region)" -ForegroundColor Gray
Write-Host "Zone    : $($d.zone)" -ForegroundColor Gray
Write-Host "Owner   : $($d.owner)" -ForegroundColor Gray

# --- 6. Configure IIS site -------------------------------------------------------
Write-Host ""
Write-Host "==> Loading IIS management tools..." -ForegroundColor Cyan
Import-Module WebAdministration
Write-Host "[OK] WebAdministration loaded" -ForegroundColor Green

# Stop Default Web Site if it uses our port
Write-Host ""
Write-Host "==> Checking port $Port..." -ForegroundColor Cyan
$defaultSite = Get-Website -Name "Default Web Site" -ErrorAction SilentlyContinue
if ($defaultSite -and $defaultSite.State -eq "Started") {
    $usesPort = $defaultSite.Bindings.Collection | Where-Object { $_.bindingInformation -like "*:$Port`:*" }
    if ($usesPort) {
        Write-Host "Default Web Site is using port $Port. Stopping it..." -ForegroundColor Yellow
        Stop-Website -Name "Default Web Site"
        Write-Host "[OK] Default Web Site stopped" -ForegroundColor Green
    }
}

# Application pool
Write-Host ""
Write-Host "==> Creating application pool..." -ForegroundColor Cyan
$appPoolPath = "IIS:\AppPools\$SiteName"
if (-not (Test-Path $appPoolPath)) {
    New-WebAppPool -Name $SiteName | Out-Null
    Write-Host "[OK] Application pool created: $SiteName" -ForegroundColor Green
} else {
    Write-Host "[OK] Application pool already exists" -ForegroundColor Green
}
Set-ItemProperty $appPoolPath -Name managedRuntimeVersion -Value ""

# Remove old site if it exists, then create fresh
Write-Host ""
Write-Host "==> Configuring $SiteName website on port $Port..." -ForegroundColor Cyan
$oldSite = Get-Website -Name $SiteName -ErrorAction SilentlyContinue
if ($oldSite) {
    Write-Host "Removing old $SiteName configuration..." -ForegroundColor Yellow
    Remove-Website -Name $SiteName
    Write-Host "[OK] Old website removed" -ForegroundColor Green
}
New-Website -Name $SiteName -Port $Port -PhysicalPath $PhysicalPath -ApplicationPool $SiteName | Out-Null
Write-Host "[OK] $SiteName website created" -ForegroundColor Green

Start-Website -Name $SiteName
Write-Host "[OK] $SiteName website started" -ForegroundColor Green

# --- 7. Test locally ------------------------------------------------------------
Write-Host ""
Write-Host "==> Testing website locally..." -ForegroundColor Cyan
try {
    $response = Invoke-WebRequest -Uri "http://localhost:$Port/" -UseBasicParsing -TimeoutSec 15
    Write-Host "[OK] Website returned HTTP $($response.StatusCode)" -ForegroundColor Green
    Write-Host "[OK] http://localhost:$Port/" -ForegroundColor Green
} catch {
    Write-Host "[WARNING] Local website request failed." -ForegroundColor Yellow
    Write-Host $_.Exception.Message -ForegroundColor Yellow
}

# --- 8. Done --------------------------------------------------------------------
Write-Host ""
Write-Host "=============================================" -ForegroundColor Green
Write-Host "          IIS SETUP COMPLETE" -ForegroundColor Green
Write-Host "=============================================" -ForegroundColor Green
Write-Host ""
Write-Host "Website path : $PhysicalPath" -ForegroundColor Gray
Write-Host "Website port : $Port" -ForegroundColor Gray
Write-Host "Website URL  : http://localhost:$Port/" -ForegroundColor Gray
Write-Host "Config file  : C:\LabTools\deployment.json" -ForegroundColor Gray
Write-Host ""
Write-Host "The page may show a collector error until Step 2 is run." -ForegroundColor Yellow
Write-Host "Your cloud firewall must also allow TCP port $Port from your IP." -ForegroundColor Yellow
Write-Host ""
Write-Host "Step 1 completed successfully." -ForegroundColor Green
