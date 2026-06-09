param(
    [Parameter(Mandatory = $true)]
    [string]$ExePath
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
Write-Host "Launching $resolvedExe"
$process = Start-Process -FilePath $resolvedExe -PassThru

Start-Sleep -Seconds 12

$configRoots = @(
    (Join-Path $env:APPDATA "OneCloudDesk"),
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
    (Join-Path $env:APPDATA "OneCloudDesk\config\OneCloudDesk.toml")
)

foreach ($file in $interestingFiles) {
    if (Test-Path -LiteralPath $file) {
        Write-Host "===== $file ====="
        Get-Content -LiteralPath $file -ErrorAction SilentlyContinue |
            Select-String -Pattern "rendezvous|relay|api|key|register|server|confirmed|disable-settings" -CaseSensitive:$false
    }
}

Write-Host "Logs:"
Get-ChildItem -Path $env:APPDATA, $env:LOCALAPPDATA -Recurse -File -ErrorAction SilentlyContinue |
    Where-Object {
        $_.FullName -match "OneCloudDesk|rustdesk|RustDesk" -and
        $_.Extension -eq ".log"
    } |
    Sort-Object LastWriteTime -Descending |
    Select-Object -First 6 |
    ForEach-Object {
        Write-Host "===== $($_.FullName) ====="
        Get-Content -LiteralPath $_.FullName -Tail 80 -ErrorAction SilentlyContinue |
            Select-String -Pattern "start udp|start tcp|rendezvous|hbbs|relay|api|21114|21116|not ready|ready|error|fail|key" -CaseSensitive:$false
    }

Get-Process -Name "rustdesk", "RustDesk", "OneCloudDesk", "OneCloudDesk2" -ErrorAction SilentlyContinue |
    Select-Object ProcessName, Id, Path |
    Format-Table -AutoSize
