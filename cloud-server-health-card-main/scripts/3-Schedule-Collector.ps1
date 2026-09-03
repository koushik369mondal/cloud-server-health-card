<#
.SYNOPSIS
    Registers the collector as a scheduled task that runs every minute.

.DESCRIPTION
    Step 3. Without this the page shows one frozen snapshot. With it the page has
    a heartbeat and the pulse strip fills in.

    The task runs as SYSTEM: no stored password to leak or rotate, it keeps
    running after you log off, and an at-startup trigger means the page recovers
    on its own after a reboot.

.EXAMPLE
    .\3-Schedule-Collector.ps1
    .\3-Schedule-Collector.ps1 -IntervalMinutes 5
#>

[CmdletBinding()]
param(
    [string]$TaskName        = 'HealthCard-Collector',
    [int]   $IntervalMinutes = 1,
    [string]$OutputPath      = 'C:\inetpub\HealthCard\data\status.json',
    [string]$SiteName        = 'HealthCard'
)

$ErrorActionPreference = 'Stop'

$id = [Security.Principal.WindowsIdentity]::GetCurrent()
if (-not (New-Object Security.Principal.WindowsPrincipal($id)).IsInRole(
        [Security.Principal.WindowsBuiltInRole]::Administrator)) {
    throw "Run this script from an elevated PowerShell window."
}

$collector = Join-Path $PSScriptRoot '2-Collect-Status.ps1'
if (-not (Test-Path $collector)) { throw "Collector not found at $collector" }

# Copy it somewhere stable. A task pointing at someone's Downloads folder breaks
# the first time that folder is cleaned up.
New-Item -Path 'C:\LabTools' -ItemType Directory -Force | Out-Null
Copy-Item $collector -Destination 'C:\LabTools' -Force
$installed = 'C:\LabTools\2-Collect-Status.ps1'
Write-Host "    [ok] Collector installed to $installed" -ForegroundColor Green

Write-Host "`n==> Registering scheduled task '$TaskName'" -ForegroundColor Cyan
if (Get-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue) {
    Unregister-ScheduledTask -TaskName $TaskName -Confirm:$false
}

$action = New-ScheduledTaskAction -Execute 'powershell.exe' -Argument (
    "-NoProfile -NonInteractive -ExecutionPolicy Bypass -File `"$installed`" " +
    "-OutputPath `"$OutputPath`" -SiteName `"$SiteName`"")

$triggers = @(
    (New-ScheduledTaskTrigger -AtStartup),
    (New-ScheduledTaskTrigger -Once -At (Get-Date).AddSeconds(30) `
        -RepetitionInterval (New-TimeSpan -Minutes $IntervalMinutes))
)

$principal = New-ScheduledTaskPrincipal -UserId 'SYSTEM' -LogonType ServiceAccount -RunLevel Highest
$settings  = New-ScheduledTaskSettingsSet -StartWhenAvailable -MultipleInstances IgnoreNew `
             -ExecutionTimeLimit (New-TimeSpan -Minutes 2)

Register-ScheduledTask -TaskName $TaskName -Action $action -Trigger $triggers `
    -Principal $principal -Settings $settings `
    -Description 'Writes host status to the IIS web root for the health card lab.' | Out-Null

Write-Host "    [ok] Runs every $IntervalMinutes minute(s) as SYSTEM" -ForegroundColor Green

Write-Host "`n==> Running it once now" -ForegroundColor Cyan
Start-ScheduledTask -TaskName $TaskName
Start-Sleep -Seconds 10

$info = Get-ScheduledTaskInfo -TaskName $TaskName
Write-Host "    Last run    : $($info.LastRunTime)"
Write-Host "    Last result : $($info.LastTaskResult)   (0 means success)"
Write-Host "    Next run    : $($info.NextRunTime)"

if (Test-Path $OutputPath) {
    $age = [int]((Get-Date) - (Get-Item $OutputPath).LastWriteTime).TotalSeconds
    Write-Host "    [ok] status.json written $age seconds ago" -ForegroundColor Green
    Write-Host "`nReload the page and watch the pulse strip." -ForegroundColor Green
} else {
    Write-Host "    [!!] $OutputPath was not created. Run the collector by hand with -Verbose." -ForegroundColor Yellow
}
