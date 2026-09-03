# Step 4 - Verify the Health Card deployment

[CmdletBinding()]
param(
    [string]$SiteName     = 'HealthCard',
    [int]   $Port         = 80,
    [string]$PhysicalPath = 'C:\inetpub\HealthCard',
    [string]$TaskName     = 'HealthCard-Collector'
)

$results = @()

function Check {
    param([string]$Name, [scriptblock]$Test, [string]$Fix)
    $pass = $false
    try { $pass = [bool](& $Test) } catch { $pass = $false }
    $script:results += [pscustomobject]@{
        Result = if ($pass) { 'PASS' } else { 'FAIL' }
        Check  = $Name
        Fix    = if ($pass) { '' } else { $Fix }
    }
}

# Load WebAdministration once for all IIS checks
$iisLoaded = $false
try { Import-Module WebAdministration -ErrorAction Stop; $iisLoaded = $true } catch {}

# --- Checks ---
Check 'IIS role installed' {
    (Get-WindowsFeature Web-Server).Installed
} 'Run 1-Setup-IIS.ps1'

Check 'W3SVC running' {
    (Get-Service W3SVC -ErrorAction Stop).Status -eq 'Running'
} 'Run: Start-Service W3SVC'

Check "Site '$SiteName' started" {
    $iisLoaded -and (Get-Website -Name $SiteName -ErrorAction Stop).State -eq 'Started'
} 'Run 1-Setup-IIS.ps1'

Check "Site bound to port $Port" {
    $iisLoaded -and [bool](
        (Get-Website -Name $SiteName -ErrorAction Stop).Bindings.Collection |
        Where-Object { $_.bindingInformation -like "*:$Port`:*" }
    )
} "Re-run 1-Setup-IIS.ps1 -Port $Port"

Check 'deployment.json installed and edited' {
    $d = Get-Content 'C:\LabTools\deployment.json' -Raw -ErrorAction Stop | ConvertFrom-Json
    $d.owner -and $d.owner -ne 'your-name-here'
} 'Edit deployment.json and re-run 1-Setup-IIS.ps1'

$statusFile = Join-Path $PhysicalPath 'data\status.json'

Check 'status.json exists' {
    Test-Path $statusFile
} 'Run 2-Collect-Status.ps1'

Check 'status.json fresher than 3 minutes' {
    (Test-Path $statusFile) -and
    ((Get-Date) - (Get-Item $statusFile).LastWriteTime).TotalMinutes -lt 3
} 'Run 3-Schedule-Collector.ps1 and check the scheduled task'

Check 'Site answers HTTP 200 on localhost' {
    (Invoke-WebRequest "http://localhost:$Port/" -UseBasicParsing -TimeoutSec 10).StatusCode -eq 200
} 'Check IIS bindings and make sure port is not used by another site'

Check 'status.json is served over HTTP' {
    (Invoke-WebRequest "http://localhost:$Port/data/status.json" -UseBasicParsing -TimeoutSec 10).StatusCode -eq 200
} 'Check site web.config and JSON MIME type'

# --- Display results ---
Write-Host ""
Write-Host "=============================================" -ForegroundColor Cyan
Write-Host "        HEALTH CARD DEPLOYMENT CHECK" -ForegroundColor Cyan
Write-Host "=============================================" -ForegroundColor Cyan
Write-Host ""
Write-Host "Computer: $env:COMPUTERNAME" -ForegroundColor Cyan
Write-Host ""
$results | Format-Table -AutoSize

$passed = ($results | Where-Object { $_.Result -eq 'PASS' }).Count
$failed = ($results | Where-Object { $_.Result -eq 'FAIL' }).Count

Write-Host ""
Write-Host "Passed: $passed / $($results.Count)" -ForegroundColor Green
Write-Host "Failed: $failed / $($results.Count)" -ForegroundColor Yellow

if ($failed -eq 0) {
    Write-Host ""
    Write-Host "=============================================" -ForegroundColor Green
    Write-Host "             ALL CHECKS PASSED" -ForegroundColor Green
    Write-Host "=============================================" -ForegroundColor Green
    Write-Host ""
    Write-Host "Capture your screenshots and submit." -ForegroundColor Green
} else {
    Write-Host ""
    Write-Host "=============================================" -ForegroundColor Yellow
    Write-Host "          SOME CHECKS FAILED" -ForegroundColor Yellow
    Write-Host "=============================================" -ForegroundColor Yellow
    Write-Host ""
    Write-Host "Fix the failed checks above and run this script again." -ForegroundColor Yellow
}

# --- Show laptop test URL ---
try {
    $ip = (Invoke-RestMethod 'https://api.ipify.org' -TimeoutSec 8).ToString().Trim()
    Write-Host ""
    Write-Host "=============================================" -ForegroundColor Cyan
    Write-Host "             LAPTOP TEST" -ForegroundColor Cyan
    Write-Host "=============================================" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "Test from your own laptop:" -ForegroundColor Cyan
    Write-Host "http://$($ip):$Port/" -ForegroundColor Green
    Write-Host ""
    Write-Host "If the laptop cannot connect, check the AWS Security Group." -ForegroundColor Yellow
    Write-Host "TCP port $Port must allow your public IP only." -ForegroundColor Yellow
} catch {
    Write-Host ""
    Write-Host "Could not determine the public IP using api.ipify.org." -ForegroundColor Yellow
}

Write-Host ""
Write-Host "Verification completed." -ForegroundColor Green