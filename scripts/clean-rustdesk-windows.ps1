<#
.SYNOPSIS
  Remove RustDesk test installs, services, user data, and portable self-extract folders.

.EXAMPLE
  powershell -ExecutionPolicy Bypass -File .\scripts\clean-rustdesk-windows.ps1 -Force

  Use -Force to skip confirmation prompts (same as -Confirm:$false).

.EXAMPLE
  powershell -ExecutionPolicy Bypass -File .\scripts\clean-rustdesk-windows.ps1 `
    -PortableDirs "$env:TEMP\rustdesk-test","D:\tmp\rustdesk-portable" -Force
#>
[CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = "High")]
param(
    [string[]]$ProductNames = @("RustDesk"),
    [string[]]$InstallDirs = @(),
    [string[]]$PortableDirs = @(),
    [switch]$KeepUserConfig,
    [switch]$SkipMsiUninstall,
    [switch]$Force
)

$ErrorActionPreference = "Continue"
$Script:DiscoveredEntries = @()
$Script:DiscoveredAppNames = @()
$Script:DiscoveredInstallPaths = @()

function Write-Step {
    param([string]$Message)
    Write-Host $Message
    [Console]::Out.Flush()
}

function Test-LocalFixedPath {
    param([string]$Path)
    if ([string]::IsNullOrWhiteSpace($Path)) {
        return $false
    }
    try {
        $root = [System.IO.Path]::GetPathRoot($Path)
        if ([string]::IsNullOrWhiteSpace($root)) {
            return $false
        }
        $driveName = $root.TrimEnd('\')
        if ($driveName.Length -ne 2) {
            return $false
        }
        $drive = [System.IO.DriveInfo]::new($driveName)
        return $drive.IsReady -and ($drive.DriveType -eq [System.IO.DriveType]::Fixed)
    } catch {
        return $false
    }
}

function Get-CleanupMatchNames {
    @(
        $ProductNames
        "rustdesk"
        $Script:DiscoveredAppNames
    ) | ForEach-Object { "$_".Trim() } | Where-Object { $_ } | Select-Object -Unique
}

function Test-RustDeskText {
    param([string]$Text)
    if ([string]::IsNullOrWhiteSpace($Text)) {
        return $false
    }
    return $Text -match '(?i)rustdesk'
}

function Test-RustDeskUninstallEntry {
    param(
        $Item,
        [string]$KeyName = ""
    )
    if (Test-RustDeskText $Item.DisplayName) { return $true }
    if (Test-RustDeskText $Item.UninstallString) { return $true }
    if (Test-RustDeskText $Item.QuietUninstallString) { return $true }
    if (Test-RustDeskText $Item.InstallLocation) { return $true }
    if (Test-RustDeskText $Item.DisplayIcon) { return $true }
    if (Test-RustDeskText $KeyName) { return $true }
    return $false
}

function Test-HasPortableUninstallCommand {
    param($Item)
    if (-not $Item.UninstallString) {
        return $false
    }
    if ($Item.UninstallString -notmatch '--uninstall') {
        return $false
    }
    if ($Item.UninstallString -match '(?i)msiexec') {
        return $false
    }
    return $true
}

function Test-IsPortableSelfInstallEntry {
    param($Item)
    if (Test-HasPortableUninstallCommand -Item $Item) {
        return $true
    }
    if ($Item.PSObject.Properties.Name -contains "WindowsInstaller" -and [int]$Item.WindowsInstaller -eq 0) {
        if ($Item.UninstallString -and $Item.UninstallString -notmatch '(?i)msiexec') {
            return $true
        }
    }
    return $false
}

function Get-UninstallExePath {
    param($Item)
    if (-not $Item.UninstallString) {
        return $null
    }
    if ($Item.UninstallString -match '(?i)msiexec') {
        return $null
    }
    if ($Item.UninstallString -match '"([^"]+\.exe)"') {
        return $Matches[1]
    }
    if ($Item.UninstallString -match '(\S+\.exe)') {
        return $Matches[1]
    }
    return $null
}

function Test-ExeLooksLikeRustDesk {
    param([string]$ExePath)
    if ([string]::IsNullOrWhiteSpace($ExePath)) {
        return $false
    }
    if (-not (Test-LocalFixedPath $ExePath)) {
        return $false
    }
    if (-not (Test-Path -LiteralPath $ExePath -PathType Leaf)) {
        return $false
    }
    try {
        $vi = (Get-Item -LiteralPath $ExePath).VersionInfo
        if ($vi.ProductName -match '(?i)rustdesk') {
            return $true
        }
        if ($vi.FileDescription -match '(?i)remote desktop') {
            return $true
        }
        if ($vi.ProductName -match '(?i)remote desktop') {
            return $true
        }
    } catch {
        return $false
    }
    return $false
}

function Test-RustDeskPortableInstallFingerprint {
    param(
        $Item,
        [string]$KeyName = ""
    )
    if (-not (Test-IsPortableSelfInstallEntry -Item $Item)) {
        return $false
    }
    if (Test-RustDeskUninstallEntry -Item $Item -KeyName $KeyName) {
        return $true
    }

    # RustDesk install_me writes BuildDate for portable installs.
    if ($Item.PSObject.Properties.Name -contains "BuildDate" -and -not [string]::IsNullOrWhiteSpace($Item.BuildDate)) {
        return $true
    }

    $exePath = Get-UninstallExePath -Item $Item
    if ($exePath) {
        $exeName = [System.IO.Path]::GetFileNameWithoutExtension($exePath)
        $installDir = if ($Item.InstallLocation) {
            $Item.InstallLocation.TrimEnd('\')
        } else {
            [System.IO.Path]::GetDirectoryName($exePath)
        }
        if ($installDir -and $exeName) {
            $dirName = [System.IO.Path]::GetFileName($installDir)
            if ($exeName -eq $dirName -and $installDir -match '(?i)\\Program Files') {
                return Test-ExeLooksLikeRustDesk -ExePath $exePath
            }
        }
        if ($KeyName -and $KeyName -notmatch '^\{[0-9A-Fa-f-]{36}\}$' -and $exeName -eq $KeyName) {
            return Test-ExeLooksLikeRustDesk -ExePath $exePath
        }
    }

    return $false
}

function Test-RustDeskMsiInstallFingerprint {
    param(
        $Item,
        [string]$KeyName = ""
    )
    if (Test-RustDeskUninstallEntry -Item $Item -KeyName $KeyName) {
        return $true
    }
    if ($KeyName -notmatch '^\{[0-9A-Fa-f-]{36}\}$') {
        return $false
    }
    if ($Item.UninstallString -notmatch '(?i)msiexec') {
        return $false
    }
    $loc = $Item.InstallLocation
    if ([string]::IsNullOrWhiteSpace($loc)) {
        return $false
    }
    if ($loc -notmatch '(?i)\\Program Files') {
        return $false
    }
    $dirName = [System.IO.Path]::GetFileName($loc.TrimEnd('\'))
    if ([string]::IsNullOrWhiteSpace($Item.DisplayName) -or $Item.DisplayName -ne $dirName) {
        return $false
    }
    $exePath = Join-Path $loc.TrimEnd('\') "$dirName.exe"
    return Test-ExeLooksLikeRustDesk -ExePath $exePath
}

function Test-RustDeskRelatedUninstallEntry {
    param(
        $Item,
        [string]$KeyName = ""
    )
    if (Test-RustDeskUninstallEntry -Item $Item -KeyName $KeyName) {
        return $true
    }
    if (Test-RustDeskPortableInstallFingerprint -Item $Item -KeyName $KeyName) {
        return $true
    }
    if ($KeyName -match '^\{[0-9A-Fa-f-]{36}\}$' -and $Item.UninstallString -match '(?i)msiexec') {
        return (Test-RustDeskMsiInstallFingerprint -Item $Item -KeyName $KeyName)
    }
    return $false
}

function Get-RustDeskRelatedUninstallEntries {
    $uninstallRoots = @(
        "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall",
        "HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall",
        "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall"
    )

    $entries = @()
    $checked = 0
    foreach ($root in $uninstallRoots) {
        if (-not (Test-Path -LiteralPath $root)) {
            continue
        }
        Get-ChildItem -LiteralPath $root -ErrorAction SilentlyContinue | ForEach-Object {
            $key = $_
            $checked++
            if ($checked % 100 -eq 0) {
                Write-Host "  ...checked $checked uninstall entries"
                [Console]::Out.Flush()
            }
            $item = Get-ItemProperty -LiteralPath $key.PSPath -ErrorAction SilentlyContinue
            if (-not $item) {
                return
            }
            if (-not (Test-RustDeskRelatedUninstallEntry -Item $item -KeyName $key.PSChildName)) {
                return
            }
            $entries += [pscustomobject]@{
                KeyName = $key.PSChildName
                Item    = $item
                KeyPath = $key.PSPath
            }
        }
    }
    Write-Step "  found $($entries.Count) related uninstall entries (scanned $checked total)"
    return $entries
}

function Get-DiscoveredAppNames {
    param($Entries)
    $names = @()
    foreach ($entry in $Entries) {
        $item = $entry.Item
        if ($item.DisplayName) {
            $names += $item.DisplayName
        }
        if ($entry.KeyName -notmatch '^\{[0-9A-Fa-f-]{36}\}$') {
            $names += $entry.KeyName
        }
        $exePath = Get-UninstallExePath -Item $item
        if ($exePath) {
            $names += [System.IO.Path]::GetFileNameWithoutExtension($exePath)
        }
        if ($item.InstallLocation) {
            $names += [System.IO.Path]::GetFileName($item.InstallLocation.TrimEnd('\'))
        }
    }
    $names |
        ForEach-Object { "$_".Trim() } |
        Where-Object { $_ -and -not (Test-RustDeskText $_) } |
        Select-Object -Unique
}

function Get-DiscoveredInstallPaths {
    param($Entries)
    $paths = @()
    foreach ($entry in $Entries) {
        $item = $entry.Item
        if (-not [string]::IsNullOrWhiteSpace($item.InstallLocation)) {
            $paths += $item.InstallLocation.TrimEnd('\')
            continue
        }

        $name = $null
        if ($item.DisplayName) {
            $name = $item.DisplayName.Trim()
        } elseif ($entry.KeyName -notmatch '^\{[0-9A-Fa-f-]{36}\}$') {
            $name = $entry.KeyName.Trim()
        }
        if ($name) {
            foreach ($root in @(${env:ProgramFiles}, ${env:ProgramFiles(x86)})) {
                if (-not [string]::IsNullOrWhiteSpace($root)) {
                    $paths += Join-Path $root $name
                }
            }
        }
    }
    return $paths | Select-Object -Unique
}

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

function Test-ShouldRun {
    param(
        [string]$Target,
        [string]$Action
    )
    if ($Force) {
        return $true
    }
    if ($null -eq $PSCmdlet) {
        return $true
    }
    try {
        return $PSCmdlet.ShouldProcess($Target, $Action)
    } catch {
        return $true
    }
}

function Invoke-Step {
    param(
        [string]$Target,
        [string]$Action,
        [scriptblock]$Script
    )
    if (-not (Test-ShouldRun -Target $Target -Action $Action)) {
        return
    }
    Write-Host "  -> $Action`: $Target"
    [Console]::Out.Flush()
    try {
        & $Script
    } catch {
        Write-Warning "$Action failed for '$Target': $($_.Exception.Message)"
    }
}

function Start-ProcessWithTimeout {
    param(
        [string]$FilePath,
        [string[]]$ArgumentList,
        [int]$TimeoutSeconds = 120,
        [string]$Label = "process"
    )
    $commandLine = "$FilePath $($ArgumentList -join ' ')"
    Write-Host "    running $Label"
    Write-Host "    command: $commandLine"
    [Console]::Out.Flush()

    $process = Start-Process -FilePath $FilePath -ArgumentList $ArgumentList -PassThru -NoNewWindow
    Write-Host "    pid $($process.Id), timeout ${TimeoutSeconds}s"
    [Console]::Out.Flush()

    $started = [datetime]::UtcNow
    $deadline = $started.AddSeconds($TimeoutSeconds)
    $lastTick = [datetime]::MinValue

    while (-not $process.HasExited) {
        if ([datetime]::UtcNow -gt $deadline) {
            Write-Warning "    timed out after ${TimeoutSeconds}s, stopping pid $($process.Id)..."
            [Console]::Out.Flush()
            try {
                Stop-Process -Id $process.Id -Force -ErrorAction Stop
            } catch {
                Write-Warning "    could not stop pid $($process.Id): $($_.Exception.Message)"
            }
            return $false
        }
        if (([datetime]::UtcNow - $lastTick).TotalSeconds -ge 5) {
            $elapsed = [int](([datetime]::UtcNow - $started).TotalSeconds)
            Write-Host "    ...still running (${elapsed}s / ${TimeoutSeconds}s, pid $($process.Id))"
            [Console]::Out.Flush()
            $lastTick = [datetime]::UtcNow
        }
        Start-Sleep -Milliseconds 500
    }

    $exitCodeText = if ($null -ne $process.ExitCode) { "$($process.ExitCode)" } else { "n/a" }
    Write-Host "    finished $Label (exit code $exitCodeText, $([int](([datetime]::UtcNow - $started).TotalSeconds))s)"
    [Console]::Out.Flush()
    return ($process.ExitCode -eq 0)
}

function Split-UninstallCommand {
    param([string]$UninstallString)
    if ([string]::IsNullOrWhiteSpace($UninstallString)) {
        return $null
    }

    $text = $UninstallString.Trim()
    $filePath = $null
    $argText = ""

    if ($text -match '^"([^"]+)"\s*(.*)$') {
        $filePath = $Matches[1]
        $argText = $Matches[2].Trim()
    } elseif ($text -match '(?i)^((?:[A-Za-z]:\\)?[^\s]+\.exe)\s*(.*)$') {
        $filePath = $Matches[1]
        $argText = $Matches[2].Trim()
    } elseif ($text -match '(?i)^msiexec(?:\.exe)?(?:\s+(.*))?$') {
        $filePath = Join-Path $env:SystemRoot "System32\msiexec.exe"
        $argText = $Matches[1]
    } else {
        return $null
    }

    $argumentList = @()
    if (-not [string]::IsNullOrWhiteSpace($argText)) {
        $argumentList = [regex]::Split($argText, '\s+(?=(?:/|--|-))') |
            ForEach-Object { $_.Trim() } |
            Where-Object { $_ }
    }

    return [pscustomobject]@{
        FilePath     = $filePath
        ArgumentList = $argumentList
    }
}

function Invoke-UninstallCommand {
    param(
        [string]$UninstallString,
        [int]$TimeoutSeconds = 120,
        [string]$Label = "uninstall"
    )
    if ([string]::IsNullOrWhiteSpace($UninstallString)) {
        return $false
    }

    $command = Split-UninstallCommand -UninstallString $UninstallString
    if (-not $command) {
        Write-Warning "    could not parse uninstall command, using cmd wrapper"
        return Start-ProcessWithTimeout `
            -FilePath "cmd.exe" `
            -ArgumentList @("/c", "`"$UninstallString`"") `
            -TimeoutSeconds $TimeoutSeconds `
            -Label $Label
    }

    if (-not (Test-Path -LiteralPath $command.FilePath -PathType Leaf)) {
        Write-Warning "    uninstall executable not found: $($command.FilePath)"
        return $false
    }

    return Start-ProcessWithTimeout `
        -FilePath $command.FilePath `
        -ArgumentList $command.ArgumentList `
        -TimeoutSeconds $TimeoutSeconds `
        -Label $Label
}

function Test-RelatedProcess {
    param(
        [string]$ProcessName,
        [string]$Path
    )
    if (Test-RustDeskText $ProcessName) {
        return $true
    }
    if ($Path -and (Test-RustDeskText $Path)) {
        return $true
    }
    foreach ($name in $Script:DiscoveredAppNames) {
        if ($ProcessName -eq $name) {
            return $true
        }
        if ($Path -and $Path -like "*\$name\*") {
            return $true
        }
    }
    return $false
}

function Stop-MatchingProcesses {
    Get-Process -ErrorAction SilentlyContinue | Where-Object {
        $processName = $_.ProcessName
        $path = $null
        try { $path = $_.Path } catch {}
        Test-RelatedProcess -ProcessName $processName -Path $path
    } | Sort-Object Id -Unique | ForEach-Object {
        $p = $_
        Invoke-Step "PID $($p.Id) $($p.ProcessName)" "Stop process" {
            Stop-Process -Id $p.Id -Force:$Force -ErrorAction Stop
        }
    }
}

function Remove-MatchingServices {
    $services = Get-Service -ErrorAction SilentlyContinue | Where-Object {
        if (Test-RustDeskText $_.Name) {
            return $true
        }
        if (Test-RustDeskText $_.DisplayName) {
            return $true
        }
        foreach ($name in $Script:DiscoveredAppNames) {
            if ($_.Name -eq $name) {
                return $true
            }
            if ($_.DisplayName -eq $name -or $_.DisplayName -eq "$name Service") {
                return $true
            }
        }
        return $false
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

function Invoke-PortableUninstall {
    $portableEntries = @($Script:DiscoveredEntries | Where-Object { Test-IsPortableSelfInstallEntry -Item $_.Item })
    if ($portableEntries.Count -eq 0) {
        Write-Step "  no portable self-install entries to remove"
        return
    }

    Write-Step "  found $($portableEntries.Count) portable self-install entries"
    $index = 0
    foreach ($entry in $portableEntries) {
        $index++
        $item = $entry.Item
        $displayName = if ($item.DisplayName) { $item.DisplayName } else { $entry.KeyName }
        $target = "$displayName [$($entry.KeyName)]"
        Write-Step "  [$index/$($portableEntries.Count)] $target"

        if (-not (Test-ShouldRun -Target $target -Action "Portable self-install uninstall")) {
            Write-Host "    skipped (confirmation declined)"
            [Console]::Out.Flush()
            continue
        }

        if ($item.UninstallString) {
            $ok = Invoke-UninstallCommand `
                -UninstallString $item.UninstallString `
                -TimeoutSeconds 120 `
                -Label "portable uninstall for $displayName"
            if (-not $ok) {
                Write-Warning "    portable uninstall may be incomplete for '$displayName'"
            }
        } else {
            Write-Host "    no UninstallString, skipping uninstall command"
            [Console]::Out.Flush()
        }

        Write-Host "    removing registry key: $($entry.KeyPath)"
        [Console]::Out.Flush()
        try {
            Remove-Item -LiteralPath $entry.KeyPath -Recurse -Force:$Force -ErrorAction Stop
            Write-Host "    registry key removed"
        } catch {
            Write-Warning "    failed to remove registry key: $($_.Exception.Message)"
        }
        [Console]::Out.Flush()
    }
    Write-Step "  portable self-install cleanup done"
}

function Invoke-MsiUninstall {
    if ($SkipMsiUninstall) {
        Write-Step "Skipping MSI uninstall registry scan."
        return
    }

    $msiEntries = @(
        $Script:DiscoveredEntries | Where-Object {
            $item = $_.Item
            if (Test-IsPortableSelfInstallEntry -Item $item) {
                return $false
            }
            if ($_.KeyName -match '^\{[0-9A-Fa-f-]{36}\}$') {
                return $true
            }
            return ($item.UninstallString -match '(?i)msiexec')
        }
    )
    if ($msiEntries.Count -eq 0) {
        Write-Step "  no MSI entries to remove"
        return
    }

    foreach ($entry in $msiEntries) {
        $item = $entry.Item
        $productCode = $entry.KeyName
        $displayName = if ($item.DisplayName) { $item.DisplayName } else { $productCode }
        $target = "$displayName ($productCode)"
        Invoke-Step $target "MSI uninstall" {
            if ($productCode -match '^\{[0-9A-Fa-f-]{36}\}$') {
                Start-ProcessWithTimeout -FilePath "msiexec.exe" -ArgumentList @("/x", $productCode, "/qn", "/norestart") -TimeoutSeconds 300 | Out-Null
            } elseif ($item.QuietUninstallString) {
                Invoke-UninstallCommand -UninstallString $item.QuietUninstallString -TimeoutSeconds 300 -Label "MSI quiet uninstall for $displayName" | Out-Null
            } elseif ($item.UninstallString) {
                Invoke-UninstallCommand -UninstallString $item.UninstallString -TimeoutSeconds 300 -Label "MSI uninstall for $displayName" | Out-Null
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
        foreach ($product in (Get-CleanupMatchNames)) {
            Join-Path $root $product
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
        foreach ($product in (Get-CleanupMatchNames)) {
            Join-Path $base $product
        }
    }
}

function Get-DefaultPortableDirs {
    Write-Host "  scanning common folders for portable RustDesk directories..."
    [Console]::Out.Flush()

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
    foreach ($name in (Get-CleanupMatchNames)) {
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

    foreach ($root in $scanRoots) {
        if (-not (Test-Path -LiteralPath $root)) {
            continue
        }
        Get-ChildItem -LiteralPath $root -Directory -Force -ErrorAction SilentlyContinue |
            Where-Object {
                $dir = $_
                if (Test-RustDeskText $dir.Name) {
                    return $true
                }
                foreach ($name in (Get-CleanupMatchNames)) {
                    if ($dir.Name -eq $name) {
                        return $true
                    }
                }

                $candidateBins = @(
                    (Join-Path $dir.FullName "rustdesk.exe"),
                    (Join-Path $dir.FullName "RustDesk.exe")
                )
                foreach ($name in (Get-CleanupMatchNames)) {
                    $candidateBins += Join-Path $dir.FullName "$name.exe"
                }
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
                if (Test-RustDeskText $name) {
                    return $true
                }
                foreach ($product in (Get-CleanupMatchNames)) {
                    if ($name -like "*$product*") {
                        return $true
                    }
                }
                return $false
            } |
            ForEach-Object {
                $shortcut = $_.FullName
                Invoke-Step $shortcut "Remove shortcut" {
                    Remove-Item -LiteralPath $shortcut -Force:$Force -ErrorAction Stop
                }
            }
    }
}

Write-Step "Cleaning products: RustDesk"
if (-not (Test-IsAdmin)) {
    Write-Warning "Not running as Administrator. Services, Program Files, and HKLM uninstall cleanup may be incomplete."
}

Write-Step "[1/7] Scanning uninstall registry..."
$Script:DiscoveredEntries = Get-RustDeskRelatedUninstallEntries
$Script:DiscoveredAppNames = Get-DiscoveredAppNames -Entries $Script:DiscoveredEntries
$Script:DiscoveredInstallPaths = @(Get-DiscoveredInstallPaths -Entries $Script:DiscoveredEntries)
if ($Script:DiscoveredAppNames.Count -gt 0) {
    Write-Step "Detected custom-name RustDesk installs: $($Script:DiscoveredAppNames -join ', ')"
}
if ($Script:DiscoveredInstallPaths.Count -gt 0) {
    Write-Step "Detected install locations: $($Script:DiscoveredInstallPaths -join ', ')"
}

Write-Step "[2/7] Stopping processes..."
Stop-MatchingProcesses
Write-Step "[3/7] Removing services..."
Remove-MatchingServices
Write-Step "[4/7] Uninstalling portable self-install entries..."
Invoke-PortableUninstall
Write-Step "[5/7] Uninstalling MSI entries..."
Invoke-MsiUninstall
Start-Sleep -Seconds 2
Stop-MatchingProcesses

Write-Step "[6/7] Removing install/user/portable paths..."
$pathsToRemove = @()
$pathsToRemove += Get-DefaultInstallDirs
$pathsToRemove += Get-DefaultUserDirs
$pathsToRemove += Get-DefaultPortableDirs
$pathsToRemove += $Script:DiscoveredInstallPaths
$pathsToRemove += $InstallDirs
$pathsToRemove += $PortableDirs
Write-Step "  $($pathsToRemove.Count) path patterns queued"
Remove-Paths -Paths $pathsToRemove -Reason "Remove RustDesk test path"

Write-Step "[7/7] Removing shortcuts..."
Remove-Shortcuts

Write-Step "Cleanup finished."
