<#
.SYNOPSIS
    Collects host telemetry and writes data\status.json for the health card.

.DESCRIPTION
    Step 2. Runs identically on AWS, Azure and GCP — it uses no cloud API and no
    cloud SDK.

    The interesting part is how it finds the public IP address. The server cannot
    see that address on any of its own adapters: run ipconfig and you will only
    find a private one like 10.x or 172.x or 192.168.x. The public address belongs
    to the cloud provider's network layer, which rewrites packets on the way in
    and out. So the script asks an outside service "what address did this request
    appear to come from?" and that answer is the public IP.

    Note what that means for firewalls: the outbound call works with no rule
    changes at all, while the inbound request from your laptop needed two rules.
    Cloud networks are asymmetric by default.

.EXAMPLE
    .\2-Collect-Status.ps1 -Verbose
#>

[CmdletBinding()]
param(
    [string]$OutputPath     = 'C:\inetpub\HealthCard\data\status.json',
    [string]$DeploymentFile = 'C:\LabTools\deployment.json',
    [string]$SiteName       = 'HealthCard'
)

$ErrorActionPreference = 'Stop'
$collectorVersion = '1.0.0'
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

# --- 1. Deployment facts the machine cannot know about itself --------------------
$deployment = [ordered]@{
    cloud = 'not set'; region = 'not set'; zone = 'not set'
    machineSize = 'not set'; owner = 'not set'; notes = ''
}
if (Test-Path $DeploymentFile) {
    try {
        $d = Get-Content $DeploymentFile -Raw | ConvertFrom-Json
        foreach ($k in @('cloud','region','zone','machineSize','owner','notes')) {
            if ($d.$k) { $deployment[$k] = $d.$k }
        }
        Write-Verbose "Loaded deployment facts from $DeploymentFile"
    } catch {
        Write-Warning "Could not parse $DeploymentFile : $($_.Exception.Message)"
    }
} else {
    Write-Warning "$DeploymentFile not found. Re-run 1-Setup-IIS.ps1."
}

# --- 2. Private IPv4 -------------------------------------------------------------
$privateIp = (Get-NetIPAddress -AddressFamily IPv4 |
    Where-Object { $_.IPAddress -notlike '127.*' -and
                   $_.IPAddress -notlike '169.254.*' -and
                   $_.InterfaceAlias -notlike '*Loopback*' } |
    Select-Object -First 1).IPAddress

# --- 3. Public IPv4, asked of an outside service ---------------------------------
$publicIp = $null
$publicIpSource = 'unreachable'
$lookups = @(
    @{ Name = 'api.ipify.org';        Url = 'https://api.ipify.org' },
    @{ Name = 'checkip.amazonaws.com'; Url = 'https://checkip.amazonaws.com' },
    @{ Name = 'ifconfig.me';          Url = 'https://ifconfig.me/ip' }
)
foreach ($l in $lookups) {
    try {
        $answer = (Invoke-RestMethod -Uri $l.Url -TimeoutSec 8).ToString().Trim()
        if ($answer -match '^\d{1,3}(\.\d{1,3}){3}$') {
            $publicIp = $answer
            $publicIpSource = $l.Name
            Write-Verbose "Public IP $publicIp reported by $($l.Name)"
            break
        }
    } catch {
        Write-Verbose "$($l.Name) did not answer: $($_.Exception.Message)"
    }
}
if (-not $publicIp) {
    Write-Warning "No lookup service answered. Either outbound internet is blocked, or this VM has no public address."
}

# --- 4. Host telemetry -----------------------------------------------------------
$os     = Get-CimInstance Win32_OperatingSystem
$cpu    = Get-CimInstance Win32_Processor | Measure-Object -Property LoadPercentage -Average
$disk   = Get-CimInstance Win32_LogicalDisk -Filter "DeviceID='C:'"
$upSpan = (Get-Date) - $os.LastBootUpTime

$memTotal = [math]::Round($os.TotalVisibleMemorySize / 1MB, 1)
$memFree  = [math]::Round($os.FreePhysicalMemory     / 1MB, 1)
$memUsed  = [math]::Round($memTotal - $memFree, 1)
$dTotal   = [math]::Round($disk.Size      / 1GB, 1)
$dFree    = [math]::Round($disk.FreeSpace / 1GB, 1)

$siteState = 'IIS module not available'
try {
    Import-Module WebAdministration -ErrorAction Stop
    $site = Get-Website -Name $SiteName -ErrorAction SilentlyContinue
    $siteState = if ($site) { "$($site.State)" } else { "site '$SiteName' not found" }
} catch { Write-Verbose "WebAdministration not loaded: $($_.Exception.Message)" }

# --- 5. Pulse history ------------------------------------------------------------
$pulses = @()
if (Test-Path $OutputPath) {
    try {
        $prev = Get-Content $OutputPath -Raw | ConvertFrom-Json
        if ($prev.pulses) { $pulses = @($prev.pulses) }
    } catch { Write-Verbose "Existing JSON unreadable; starting a fresh history." }
}
$pulses += [pscustomobject]@{
    t  = (Get-Date).ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ssZ')
    ok = [bool]$privateIp
}
if ($pulses.Count -gt 40) { $pulses = $pulses[-40..-1] }

# --- 6. Write the file -----------------------------------------------------------
$payload = [ordered]@{
    generatedAtUtc   = (Get-Date).ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ssZ')
    collectorVersion = $collectorVersion
    deployment       = $deployment
    network          = [ordered]@{
        privateIpv4    = $privateIp
        publicIpv4     = $publicIp
        publicIpSource = $publicIpSource
    }
    host             = [ordered]@{
        computerName   = $env:COMPUTERNAME
        osCaption      = $os.Caption.Trim()
        uptime         = '{0} d {1:00} h {2:00} m' -f $upSpan.Days, $upSpan.Hours, $upSpan.Minutes
        cpuLoadPercent = [int][math]::Round($cpu.Average, 0)
        memoryUsedGb   = $memUsed
        memoryTotalGb  = $memTotal
        memoryLabel    = "$memUsed / $memTotal GB"
        diskCFreeGb    = $dFree
        diskCTotalGb   = $dTotal
        diskLabel      = "$([math]::Round($dTotal - $dFree, 1)) / $dTotal GB"
        iisSiteName    = $SiteName
        iisSiteState   = $siteState
    }
    pulses           = $pulses
}

$dir = Split-Path -Parent $OutputPath
if (-not (Test-Path $dir)) { New-Item -Path $dir -ItemType Directory -Force | Out-Null }

# UTF-8 without a BOM. A BOM makes some browsers fail JSON.parse().
[System.IO.File]::WriteAllText(
    $OutputPath,
    ($payload | ConvertTo-Json -Depth 6),
    (New-Object System.Text.UTF8Encoding($false))
)

Write-Host "Wrote $OutputPath" -ForegroundColor Green
Write-Host "  $($env:COMPUTERNAME) · private $privateIp · public $publicIp (via $publicIpSource)" -ForegroundColor Gray
Write-Host "  $($deployment.cloud) / $($deployment.region) / $($deployment.zone)" -ForegroundColor Gray
