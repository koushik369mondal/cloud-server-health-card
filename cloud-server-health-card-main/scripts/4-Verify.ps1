<#
.SYNOPSIS
    Runs nine checks against your deployment and prints a pass/fail report.

.DESCRIPTION
    Run this before you submit. It checks the same things the instructor will,
    and every failure line tells you which step to go back to.

.EXAMPLE
    .\4-Verify.ps1
    .\4-Verify.ps1 -Port 8080
#>

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
    try { $pass = [bool](& $Test) } catch { }
    $script:results += [pscustomobject]@{
        Result = if ($pass) { 'PASS' } else { 'FAIL' }
        Check  = $Name
        Fix    = if ($pass) { '' } else { $Fix }
    }
}

Check 'IIS role installed' {
    (Get-WindowsFeature Web-Server).Installed
} 'Run 1-Setup-IIS.ps1'

Check 'W3SVC running' {
    (Get-Service W3SVC -ErrorAction Stop).Status -eq 'Running'
} 'Run: Start-Service W3SVC'

Check "Site '$SiteName' started" {
    Import-Module WebAdministration
    (Get-Website -Name $SiteName -ErrorAction Stop).State -eq 'Started'
} 'Run 1-Setup-IIS.ps1'

Check "Site bound to port $Port" {
    Import-Module WebAdministration
    [bool]((Get-Website -Name $SiteName).bindings.Collection |
        Where-Object { $_.bindingInformation -like "*:$Port`:*" })
} "Re-run 1-Setup-IIS.ps1 -Port $Port"

Check 'deployment.json installed and edited' {
    $d = Get-Content 'C:\LabTools\deployment.json' -Raw -ErrorAction Stop | ConvertFrom-Json
    $d.owner -and $d.owner -ne 'your-name-here'
} 'Edit deployment.json with your real details, then re-run 1-Setup-IIS.ps1'

Check 'status.json exists' {
    Test-Path (Join-Path $PhysicalPath 'data\status.json')
} 'Run 2-Collect-Status.ps1'

Check 'status.json fresher than 3 minutes' {
    ((Get-Date) - (Get-Item (Join-Path $PhysicalPath 'data\status.json') -ErrorAction Stop).LastWriteTime).TotalMinutes -lt 3
} 'The scheduled task is not firing. Run 3-Schedule-Collector.ps1'

Check 'Site answers HTTP 200 on localhost' {
    (Invoke-WebRequest "http://localhost:$Port/" -UseBasicParsing -TimeoutSec 10).StatusCode -eq 200
} 'Check bindings, and that no other site holds the port'

Check 'status.json is served over HTTP' {
    (Invoke-WebRequest "http://localhost:$Port/data/status.json" -UseBasicParsing -TimeoutSec 10).StatusCode -eq 200
} 'A 404.3 here means the .json MIME type is missing. Check site\web.config'

Write-Host "`n  Deployment check — $env:COMPUTERNAME`n" -ForegroundColor Cyan
$results | Format-Table -AutoSize

$failed = ($results | Where-Object Result -eq 'FAIL').Count
if ($failed -eq 0) {
    Write-Host "All checks passed. Capture your screenshots and submit." -ForegroundColor Green
} else {
    Write-Host "$failed check(s) failed. Fix them and run this again." -ForegroundColor Yellow
}

try {
    $ip = (Invoke-RestMethod 'https://api.ipify.org' -TimeoutSec 8).ToString().Trim()
    Write-Host "`nTest from your own laptop: http://$($ip):$Port/" -ForegroundColor Cyan
    Write-Host "If that times out, your cloud firewall is blocking port $Port." -ForegroundColor Gray
} catch { }
