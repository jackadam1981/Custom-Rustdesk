param(
    [Parameter(Mandatory = $true)]
    [string]$ExePath,

    [ValidateSet("StartProcess", "Explorer")]
    [string]$LaunchMode = "StartProcess",

    [int]$WaitSeconds = 30,

    [string]$ExpectedRendezvousServer = "",

    [switch]$StopAfter
)

$ErrorActionPreference = "Continue"

$processNames = @("rustdesk", "RustDesk", "OneCloudDesk", "OneCloudDesk2")
foreach ($name in $processNames) {
    Get-Process -Name $name -ErrorAction SilentlyContinue |
        Stop-Process -Force -ErrorAction SilentlyContinue
}

Start-Sleep -Milliseconds 500

$paths = @(
    (Join-Path $env:APPDATA "RustDesk"),
    (Join-Path $env:APPDATA "OneCloudDesk"),
    (Join-Path $env:LOCALAPPDATA "rustdesk"),
    (Join-Path $env:LOCALAPPDATA "RustDesk"),
    (Join-Path $env:LOCALAPPDATA "OneCloudDesk"),
    (Join-Path $env:PROGRAMDATA "RustDesk"),
    (Join-Path $env:PROGRAMDATA "OneCloudDesk")
)

foreach ($path in $paths) {
    if (Test-Path -LiteralPath $path) {
        Remove-Item -LiteralPath $path -Recurse -Force -ErrorAction SilentlyContinue
    }
}

Write-Host "Cleaned paths:"
$paths | ForEach-Object {
    [pscustomobject]@{ Path = $_; Exists = (Test-Path -LiteralPath $_) }
} | Format-Table -AutoSize

$resolvedExe = Resolve-Path -LiteralPath $ExePath
$startTime = Get-Date
Write-Host "Launching $resolvedExe using $LaunchMode"
if ($LaunchMode -eq "Explorer") {
    & explorer.exe $resolvedExe
} else {
    $process = Start-Process -FilePath $resolvedExe -PassThru
}

Start-Sleep -Seconds $WaitSeconds

Write-Host "Processes:"
$runningProcesses = @(Get-Process -Name "rustdesk", "RustDesk", "OneCloudDesk", "OneCloudDesk2" -ErrorAction SilentlyContinue)
$runningProcesses |
    Select-Object ProcessName, Id, MainWindowTitle, Responding, Path |
    Format-Table -AutoSize

Write-Host "Windows crash events since launch:"
$crashEvents = @(Get-WinEvent -FilterHashtable @{ LogName = "Application"; StartTime = $startTime } -ErrorAction SilentlyContinue |
    Where-Object {
        $_.ProviderName -in @("Application Error", "Windows Error Reporting") -and
        $_.Message -match "rustdesk|RustDesk|OneCloudDesk"
    })
$crashEvents |
    Select-Object TimeCreated, ProviderName, Id,
        @{ Name = "Code"; Expression = {
            if ($_.Message -match "异常代码：\s*(\S+)") { $matches[1] }
            elseif ($_.Message -match "P8:\s*(\S+)") { $matches[1] }
        }},
        @{ Name = "Offset"; Expression = {
            if ($_.Message -match "错误偏移：\s*(\S+)") { $matches[1] }
            elseif ($_.Message -match "P7:\s*(\S+)") { $matches[1] }
        }},
        @{ Name = "Summary"; Expression = { ($_.Message -split "`r?`n")[0] } } |
    Format-Table -AutoSize

$configRoots = @(
    (Join-Path $env:APPDATA "OneCloudDesk"),
    (Join-Path $env:APPDATA "RustDesk"),
    (Join-Path $env:LOCALAPPDATA "rustdesk")
)

Write-Host "Config files:"
foreach ($root in $configRoots) {
    if (Test-Path -LiteralPath $root) {
        Get-ChildItem -LiteralPath $root -Recurse -File -ErrorAction SilentlyContinue |
            Where-Object { $_.Name -match '\.(toml|log)$' } |
            Select-Object FullName, Length, LastWriteTime |
            Format-Table -AutoSize
    }
}

$interestingFiles = @(
    (Join-Path $env:APPDATA "OneCloudDesk\config\OneCloudDesk2.toml"),
    (Join-Path $env:APPDATA "OneCloudDesk\config\OneCloudDesk.toml"),
    (Join-Path $env:APPDATA "RustDesk\config\RustDesk2.toml"),
    (Join-Path $env:APPDATA "RustDesk\config\RustDesk.toml")
)

$matchedExpectedServer = [string]::IsNullOrWhiteSpace($ExpectedRendezvousServer)
foreach ($file in $interestingFiles) {
    if (Test-Path -LiteralPath $file) {
        Write-Host "===== $file ====="
        $matches = Get-Content -LiteralPath $file -ErrorAction SilentlyContinue |
            Select-String -Pattern "rendezvous|relay|api|key|register|server|confirmed|disable-settings" -CaseSensitive:$false
        $matches
        if (-not [string]::IsNullOrWhiteSpace($ExpectedRendezvousServer) -and
            ($matches | Select-String -SimpleMatch $ExpectedRendezvousServer -Quiet)) {
            $matchedExpectedServer = $true
        }
    }
}

Write-Host "Logs:"
foreach ($root in $configRoots) {
    if (-not (Test-Path -LiteralPath $root)) {
        continue
    }
    Get-ChildItem -LiteralPath $root -Recurse -File -ErrorAction SilentlyContinue |
    Where-Object {
        $_.Extension -eq ".log"
    } |
    Sort-Object LastWriteTime -Descending |
    Select-Object -First 3 |
    ForEach-Object {
        Write-Host "===== $($_.FullName) ====="
        Get-Content -LiteralPath $_.FullName -Tail 80 -ErrorAction SilentlyContinue |
            Select-String -Pattern "start udp|start tcp|rendezvous|hbbs|relay|api|21114|21116|not ready|ready|error|fail|key" -CaseSensitive:$false
    }
}

$failed = $false
if ($runningProcesses.Count -eq 0) {
    Write-Error "No RustDesk/OneCloudDesk process survived after $WaitSeconds seconds."
    $failed = $true
}
if ($crashEvents.Count -gt 0) {
    Write-Error "Crash events were recorded after launch."
    $failed = $true
}
if (-not $matchedExpectedServer) {
    Write-Error "Expected rendezvous server was not found: $ExpectedRendezvousServer"
    $failed = $true
}

if ($StopAfter) {
    foreach ($name in $processNames) {
        Get-Process -Name $name -ErrorAction SilentlyContinue |
            Stop-Process -Force -ErrorAction SilentlyContinue
    }
}

if ($failed) {
    exit 1
}
