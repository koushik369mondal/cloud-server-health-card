```powershell
# Step 1 - Install IIS and publish the Health Card website

$ErrorActionPreference = "Stop"

# ------------------------------------------------------------
# 0. Check Administrator privileges
# ------------------------------------------------------------

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

$SiteName = "HealthCard"
$Port = 80
$PhysicalPath = "C:\inetpub\HealthCard"

Write-Host "[OK] Running as Administrator" -ForegroundColor Green

# ------------------------------------------------------------
# 1. Install IIS
# ------------------------------------------------------------

Write-Host ""
Write-Host "==> Installing IIS..." -ForegroundColor Cyan

$result = Install-WindowsFeature `
    -Name Web-Server, Web-Mgmt-Console, Web-Mgmt-Tools `
    -IncludeManagementTools

if (-not $result.Success) {
    Write-Host "ERROR: IIS installation failed." -ForegroundColor Red
    exit 1
}

Write-Host "[OK] IIS installed" -ForegroundColor Green

# ------------------------------------------------------------
# 2. Start IIS service
# ------------------------------------------------------------

Write-Host ""
Write-Host "==> Starting IIS service..." -ForegroundColor Cyan

$service = Get-Service W3SVC

if ($service.Status -ne "Running") {
    Start-Service W3SVC
    Start-Sleep -Seconds 2
}

Write-Host "[OK] W3SVC status: $((Get-Service W3SVC).Status)" -ForegroundColor Green

# ------------------------------------------------------------
# 3. Windows Firewall
# ------------------------------------------------------------

Write-Host ""
Write-Host "==> Configuring Windows Firewall for TCP 80..." -ForegroundColor Cyan

$ruleName = "Lab HTTP 80 In"

$existingRule = Get-NetFirewallRule `
    -DisplayName $ruleName `
    -ErrorAction SilentlyContinue

if (-not $existingRule) {

    New-NetFirewallRule `
        -DisplayName $ruleName `
        -Direction Inbound `
        -Protocol TCP `
        -LocalPort 80 `
        -Action Allow | Out-Null

    Write-Host "[OK] Windows Firewall allows TCP 80" -ForegroundColor Green

}
else {

    Write-Host "[OK] Windows Firewall rule already exists" -ForegroundColor Green

}

# ------------------------------------------------------------
# 4. Find website files
# ------------------------------------------------------------

Write-Host ""
Write-Host "==> Finding website files..." -ForegroundColor Cyan

$repoRoot = Split-Path -Parent $PSScriptRoot
$source = Join-Path $repoRoot "site"

if (-not (Test-Path $source)) {

    Write-Host "ERROR: Website folder was not found:" -ForegroundColor Red
    Write-Host $source -ForegroundColor Red

    exit 1
}

Write-Host "[OK] Website folder found: $source" -ForegroundColor Green

# ------------------------------------------------------------
# 5. Copy website files
# ------------------------------------------------------------

Write-Host ""
Write-Host "==> Publishing website to $PhysicalPath..." -ForegroundColor Cyan

New-Item `
    -Path $PhysicalPath `
    -ItemType Directory `
    -Force | Out-Null

Copy-Item `
    -Path (Join-Path $source "*") `
    -Destination $PhysicalPath `
    -Recurse `
    -Force

New-Item `
    -Path (Join-Path $PhysicalPath "data") `
    -ItemType Directory `
    -Force | Out-Null

$fileCount = (Get-ChildItem $PhysicalPath -Recurse -File).Count

Write-Host "[OK] Copied $fileCount files" -ForegroundColor Green

# ------------------------------------------------------------
# 6. Read deployment.json
# ------------------------------------------------------------

Write-Host ""
Write-Host "==> Reading deployment.json..." -ForegroundColor Cyan

$deployment = Join-Path $repoRoot "deployment.json"

if (-not (Test-Path $deployment)) {

    Write-Host "ERROR: deployment.json was not found:" -ForegroundColor Red
    Write-Host $deployment -ForegroundColor Red

    exit 1
}

try {

    $d = Get-Content $deployment -Raw | ConvertFrom-Json

}
catch {

    Write-Host "ERROR: deployment.json contains invalid JSON." -ForegroundColor Red
    Write-Host $_.Exception.Message -ForegroundColor Red

    exit 1
}

if ($d.owner -eq "your-name-here") {

    Write-Host ""
    Write-Host "WARNING: deployment.json still contains owner = your-name-here" -ForegroundColor Yellow
    Write-Host "Edit deployment.json with your information before continuing." -ForegroundColor Yellow

}

# ------------------------------------------------------------
# 7. Copy deployment.json for collector
# ------------------------------------------------------------

Write-Host ""
Write-Host "==> Installing deployment information..." -ForegroundColor Cyan

New-Item `
    -Path "C:\LabTools" `
    -ItemType Directory `
    -Force | Out-Null

Copy-Item `
    $deployment `
    -Destination "C:\LabTools\deployment.json" `
    -Force

Write-Host "[OK] deployment.json copied to C:\LabTools" -ForegroundColor Green

Write-Host ""
Write-Host "Cloud   : $($d.cloud)" -ForegroundColor Gray
Write-Host "Region  : $($d.region)" -ForegroundColor Gray
Write-Host "Zone    : $($d.zone)" -ForegroundColor Gray
Write-Host "Owner   : $($d.owner)" -ForegroundColor Gray

# ------------------------------------------------------------
# 8. Import IIS management module
# ------------------------------------------------------------

Write-Host ""
Write-Host "==> Loading IIS management tools..." -ForegroundColor Cyan

Import-Module WebAdministration

Write-Host "[OK] WebAdministration loaded" -ForegroundColor Green

# ------------------------------------------------------------
# 9. Stop Default Web Site if it uses port 80
# ------------------------------------------------------------

Write-Host ""
Write-Host "==> Checking port 80..." -ForegroundColor Cyan

$defaultSite = Get-Website `
    -Name "Default Web Site" `
    -ErrorAction SilentlyContinue

if ($defaultSite) {

    $usesPort80 = $defaultSite.Bindings.Collection |
    Where-Object {
        $_.bindingInformation -like "*:80:*"
    }

    if ($defaultSite.State -eq "Started" -and $usesPort80) {

        Write-Host "Default Web Site is using port 80." -ForegroundColor Yellow
        Write-Host "Stopping Default Web Site..." -ForegroundColor Yellow

        Stop-Website -Name "Default Web Site"

        Write-Host "[OK] Default Web Site stopped" -ForegroundColor Green

    }

}

# ------------------------------------------------------------
# 10. Create application pool
# ------------------------------------------------------------

Write-Host ""
Write-Host "==> Creating application pool..." -ForegroundColor Cyan

$appPoolPath = "IIS:\AppPools\$SiteName"

if (-not (Test-Path $appPoolPath)) {

    New-WebAppPool -Name $SiteName | Out-Null

    Write-Host "[OK] Application pool created: $SiteName" -ForegroundColor Green

}
else {

    Write-Host "[OK] Application pool already exists" -ForegroundColor Green

}

Set-ItemProperty `
    $appPoolPath `
    -Name managedRuntimeVersion `
    -Value ""

# ------------------------------------------------------------
# 11. Remove old HealthCard website if necessary
# ------------------------------------------------------------

Write-Host ""
Write-Host "==> Checking HealthCard website..." -ForegroundColor Cyan

$oldSite = Get-Website `
    -Name $SiteName `
    -ErrorAction SilentlyContinue

if ($oldSite) {

    Write-Host "Existing HealthCard website found." -ForegroundColor Yellow
    Write-Host "Removing old configuration..." -ForegroundColor Yellow

    Remove-Website -Name $SiteName

    Write-Host "[OK] Old website removed" -ForegroundColor Green

}

# ------------------------------------------------------------
# 12. Create HealthCard website
# ------------------------------------------------------------

Write-Host ""
Write-Host "==> Creating HealthCard website on port 80..." -ForegroundColor Cyan

New-Website `
    -Name $SiteName `
    -Port $Port `
    -PhysicalPath $PhysicalPath `
    -ApplicationPool $SiteName | Out-Null

Write-Host "[OK] HealthCard website created" -ForegroundColor Green

# ------------------------------------------------------------
# 13. Start website
# ------------------------------------------------------------

Write-Host ""
Write-Host "==> Starting HealthCard website..." -ForegroundColor Cyan

Start-Website -Name $SiteName

Write-Host "[OK] HealthCard website started" -ForegroundColor Green

# ------------------------------------------------------------
# 14. Test website locally
# ------------------------------------------------------------

Write-Host ""
Write-Host "==> Testing website locally..." -ForegroundColor Cyan

try {

    $response = Invoke-WebRequest `
        -Uri "http://localhost:80/" `
        -UseBasicParsing `
        -TimeoutSec 15

    Write-Host ""
    Write-Host "[OK] Website returned HTTP $($response.StatusCode)" -ForegroundColor Green
    Write-Host "[OK] http://localhost:80/" -ForegroundColor Green

}
catch {

    Write-Host ""
    Write-Host "[WARNING] Local website request failed." -ForegroundColor Yellow
    Write-Host $_.Exception.Message -ForegroundColor Yellow

}

# ------------------------------------------------------------
# 15. Finished
# ------------------------------------------------------------

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
Write-Host "Your cloud firewall must also allow TCP port 80 from your IP." -ForegroundColor Yellow

Write-Host ""
Write-Host "Step 1 completed successfully." -ForegroundColor Green
```
