<#
.SYNOPSIS
  Remove RustDesk/OneCloudDesk test installs, services, user data, and portable self-extract folders.

.EXAMPLE
  powershell -ExecutionPolicy Bypass -File .\scripts\clean-rustdesk-windows.ps1 -Force

.EXAMPLE
  powershell -ExecutionPolicy Bypass -File .\scripts\clean-rustdesk-windows.ps1 `
    -PortableDirs "$env:TEMP\rustdesk-test","D:\tmp\OneCloudDesk-portable" -Force
#>
[CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = "High")]
param(
    [string[]]$ProductNames = @("RustDesk", "OneCloudDesk"),
    [string[]]$InstallDirs = @(),
    [string[]]$PortableDirs = @(),
    [switch]$KeepUserConfig,
    [switch]$SkipMsiUninstall,
    [switch]$Force
)

$ErrorActionPreference = "Continue"

function Test-IsAdmin {
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = [Security.Principal.WindowsPrincipal]::new($identity)
    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Resolve-ExistingPath {
    param([string]$Path)
    if ([string]::IsNullOrWhiteSpace($Path)) {
        return $null
    }
    try {
        return (Resolve-Path -LiteralPath $Path -ErrorAction Stop).Path
    } catch {
        return $null
    }
}

function Invoke-Step {
    param(
        [string]$Target,
        [string]$Action,
        [scriptblock]$Script
    )
    $shouldRun = $true
    if ($null -ne $PSCmdlet) {
        $shouldRun = $PSCmdlet.ShouldProcess($Target, $Action)
    }
    if ($shouldRun) {
        try {
            & $Script
        } catch {
            Write-Warning "$Action failed for '$Target': $($_.Exception.Message)"
        }
    }
}

function Stop-MatchingProcesses {
    $patterns = $ProductNames + @("rustdesk")
    Get-Process -ErrorAction SilentlyContinue | Where-Object {
        $processName = $_.ProcessName
        $path = $null
        try { $path = $_.Path } catch {}
        foreach ($pattern in $patterns) {
            if ($processName -like "*$pattern*" -or ($path -and $path -like "*$pattern*")) {
                return $true
            }
        }
        return $false
    } | Sort-Object Id -Unique | ForEach-Object {
        $p = $_
        Invoke-Step "PID $($p.Id) $($p.ProcessName)" "Stop process" {
            Stop-Process -Id $p.Id -Force:$Force -ErrorAction Stop
        }
    }
}

function Remove-MatchingServices {
    $services = Get-Service -ErrorAction SilentlyContinue | Where-Object {
        $name = $_.Name
        $display = $_.DisplayName
        foreach ($product in $ProductNames) {
            if ($name -like "*$product*" -or $display -like "*$product*") {
                return $true
            }
        }
        return ($name -like "*rustdesk*" -or $display -like "*rustdesk*")
    }

    foreach ($service in $services) {
        Invoke-Step $service.Name "Stop service" {
            if ($service.Status -ne "Stopped") {
                Stop-Service -Name $service.Name -Force:$Force -ErrorAction Stop
            }
        }
        Invoke-Step $service.Name "Delete service" {
            sc.exe delete $service.Name | Out-Null
        }
    }
}

function Invoke-MsiUninstall {
    if ($SkipMsiUninstall) {
        Write-Host "Skipping MSI uninstall registry scan."
        return
    }

    $uninstallRoots = @(
        "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall",
        "HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall",
        "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall"
    )

    foreach ($root in $uninstallRoots) {
        if (-not (Test-Path -LiteralPath $root)) {
            continue
        }
        Get-ChildItem -LiteralPath $root -ErrorAction SilentlyContinue | ForEach-Object {
            $item = Get-ItemProperty -LiteralPath $_.PSPath -ErrorAction SilentlyContinue
            if (-not $item.DisplayName) {
                return
            }

            $matched = $false
            foreach ($product in $ProductNames) {
                if ($item.DisplayName -like "*$product*") {
                    $matched = $true
                }
            }
            if (-not $matched) {
                return
            }

            $productCode = $_.PSChildName
            $target = "$($item.DisplayName) ($productCode)"
            Invoke-Step $target "MSI uninstall" {
                if ($productCode -match "^\{[0-9A-Fa-f-]{36}\}$") {
                    Start-Process -FilePath "msiexec.exe" -ArgumentList "/x", $productCode, "/qn", "/norestart" -Wait -NoNewWindow
                } elseif ($item.QuietUninstallString) {
                    Start-Process -FilePath "cmd.exe" -ArgumentList "/c", $item.QuietUninstallString -Wait -NoNewWindow
                } elseif ($item.UninstallString) {
                    Start-Process -FilePath "cmd.exe" -ArgumentList "/c", $item.UninstallString -Wait -NoNewWindow
                }
            }
        }
    }
}

function Get-DefaultInstallDirs {
    $roots = @(
        ${env:ProgramFiles},
        ${env:ProgramFiles(x86)},
        ${env:ProgramData},
        ${env:LOCALAPPDATA}
    ) | Where-Object { -not [string]::IsNullOrWhiteSpace($_) }

    foreach ($root in $roots) {
        foreach ($product in $ProductNames) {
            Join-Path $root $product
            Join-Path $root "RustDesk"
            Join-Path $root "OneCloudDesk"
        }
    }
}

function Get-DefaultUserDirs {
    if ($KeepUserConfig) {
        return @()
    }

    $baseDirs = @(
        $env:APPDATA,
        $env:LOCALAPPDATA,
        $env:PROGRAMDATA
    ) | Where-Object { -not [string]::IsNullOrWhiteSpace($_) }

    foreach ($base in $baseDirs) {
        foreach ($product in $ProductNames) {
            Join-Path $base $product
            Join-Path $base "RustDesk"
            Join-Path $base "OneCloudDesk"
        }
    }
}

function Get-DefaultPortableDirs {
    $desktop = [Environment]::GetFolderPath("Desktop")
    $downloads = Join-Path $env:USERPROFILE "Downloads"
    $documents = [Environment]::GetFolderPath("MyDocuments")

    $scanRoots = @(
        $env:TEMP,
        $env:TMP,
        (Join-Path $env:LOCALAPPDATA "Temp"),
        $desktop,
        $downloads,
        $documents,
        (Join-Path $env:USERPROFILE "Desktop"),
        (Join-Path $env:USERPROFILE "Downloads")
    ) |
        Where-Object { -not [string]::IsNullOrWhiteSpace($_) } |
        Sort-Object -Unique

    $namePatterns = @()
    foreach ($name in @("RustDesk", "rustdesk", "OneCloudDesk", "oneclouddesk")) {
        $namePatterns += @(
            $name,
            "$name-*",
            "${name}_*",
            ".$name",
            "$name-client-*",
            "$name-portable-*",
            "${name}_portable_*"
        )
    }

    foreach ($root in $scanRoots) {
        if (-not (Test-Path -LiteralPath $root)) {
            continue
        }
        foreach ($pattern in ($namePatterns | Sort-Object -Unique)) {
            Join-Path $root $pattern
        }
    }

    # Some self-extract builds create a random-looking directory that contains a RustDesk binary.
    # Keep this scan shallow and directory-only so downloads like .exe/.msi are not removed.
    foreach ($root in $scanRoots) {
        if (-not (Test-Path -LiteralPath $root)) {
            continue
        }
        Get-ChildItem -LiteralPath $root -Directory -Force -ErrorAction SilentlyContinue |
            Where-Object {
                $dir = $_
                foreach ($product in $ProductNames) {
                    if ($dir.Name -like "*$product*" -or $dir.Name -like "*rustdesk*") {
                        return $true
                    }
                }

                $candidateBins = @(
                    (Join-Path $dir.FullName "rustdesk.exe"),
                    (Join-Path $dir.FullName "RustDesk.exe"),
                    (Join-Path $dir.FullName "OneCloudDesk.exe")
                )
                foreach ($candidate in $candidateBins) {
                    if (Test-Path -LiteralPath $candidate) {
                        return $true
                    }
                }
                return $false
            } |
            ForEach-Object { $_.FullName }
    }
}

function Remove-Paths {
    param([string[]]$Paths, [string]$Reason)

    $expanded = foreach ($path in $Paths) {
        if ([string]::IsNullOrWhiteSpace($path)) {
            continue
        }
        if ($path.Contains("*")) {
            Get-ChildItem -Path $path -Directory -Force -ErrorAction SilentlyContinue | ForEach-Object { $_.FullName }
        } else {
            $resolved = Resolve-ExistingPath $path
            if ($resolved) {
                $resolved
            }
        }
    }

    $expanded | Sort-Object -Unique | ForEach-Object {
        $path = $_
        Invoke-Step $path $Reason {
            Remove-Item -LiteralPath $path -Recurse -Force:$Force -ErrorAction Stop
        }
    }
}

function Remove-Shortcuts {
    $shortcutRoots = @(
        [Environment]::GetFolderPath("Desktop"),
        [Environment]::GetFolderPath("CommonDesktopDirectory"),
        [Environment]::GetFolderPath("StartMenu"),
        [Environment]::GetFolderPath("CommonStartMenu"),
        [Environment]::GetFolderPath("Startup"),
        [Environment]::GetFolderPath("CommonStartup")
    ) | Where-Object { -not [string]::IsNullOrWhiteSpace($_) -and (Test-Path -LiteralPath $_) }

    foreach ($root in $shortcutRoots) {
        Get-ChildItem -LiteralPath $root -Recurse -Force -ErrorAction SilentlyContinue |
            Where-Object {
                if ($_.Extension -notin @(".lnk", ".url")) {
                    return $false
                }
                $name = $_.Name
                foreach ($product in $ProductNames) {
                    if ($name -like "*$product*") {
                        return $true
                    }
                }
                return ($name -like "*RustDesk*")
            } |
            ForEach-Object {
                $shortcut = $_.FullName
                Invoke-Step $shortcut "Remove shortcut" {
                    Remove-Item -LiteralPath $shortcut -Force:$Force -ErrorAction Stop
                }
            }
    }
}

Write-Host "Cleaning products: $($ProductNames -join ', ')"
if (-not (Test-IsAdmin)) {
    Write-Warning "Not running as Administrator. Services, Program Files, and HKLM uninstall cleanup may be incomplete."
}

Stop-MatchingProcesses
Remove-MatchingServices
Invoke-MsiUninstall
Start-Sleep -Seconds 2
Stop-MatchingProcesses

$pathsToRemove = @()
$pathsToRemove += Get-DefaultInstallDirs
$pathsToRemove += Get-DefaultUserDirs
$pathsToRemove += Get-DefaultPortableDirs
$pathsToRemove += $InstallDirs
$pathsToRemove += $PortableDirs

Remove-Paths -Paths $pathsToRemove -Reason "Remove RustDesk test path"
Remove-Shortcuts

Write-Host "Cleanup finished."
