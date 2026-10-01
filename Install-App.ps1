param(
    [string]$PackageRoot = $PSScriptRoot,
    [string]$Destination = (Join-Path $env:LOCALAPPDATA 'TransparentTemperatureWidget'),
    [switch]$NoSensors,
    [switch]$NoLaunch,
    [switch]$NoShortcut
)
$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSHOME 'Modules/Microsoft.PowerShell.Security/Microsoft.PowerShell.Security.psd1') -ErrorAction Stop
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
$Destination = [IO.Path]::GetFullPath($Destination)
$stage = Join-Path ([IO.Path]::GetTempPath()) ('TemperatureWidget-Stage-' + [Guid]::NewGuid().ToString('N'))
function Get-VerifiedDownload($url, $path, $hash) {
    Invoke-WebRequest -UseBasicParsing $url -OutFile $path
    if ((Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash -ne $hash) { throw ('Checksum mismatch: ' + $url) }
}
try {
    [void][IO.Directory]::CreateDirectory((Join-Path $stage 'vendor/lhm'))
    Write-Host 'Downloading verified LibreHardwareMonitor 0.9.6 and PawnIO 2.2.0...'
    $lhm = Join-Path $stage 'lhm.zip'
    Get-VerifiedDownload 'https://github.com/LibreHardwareMonitor/LibreHardwareMonitor/releases/download/v0.9.6/LibreHardwareMonitor.zip' $lhm '086D9F1B5A99E643EDC2CFAAAC16051685B551E4C5AC0B32A57C58C0E529C001'
    Expand-Archive -LiteralPath $lhm -DestinationPath (Join-Path $stage 'vendor/lhm')
    $pawn = Join-Path $stage 'vendor/PawnIO_setup.exe'
    Get-VerifiedDownload 'https://github.com/namazso/PawnIO.Setup/releases/download/2.2.0/PawnIO_setup.exe' $pawn '1F519A22E47187F70A1379A48CA604981C4FCF694F4E65B734AAA74A9FBA3032'
    if ((Get-AuthenticodeSignature -LiteralPath $pawn).Status -ne 'Valid') { throw 'PawnIO signature is invalid.' }
    $files = @('Collector.ps1','Widget.ps1','Setup-Sensors.ps1','Launch.ps1','Start.vbs')
    foreach ($file in $files) {
        $source = Join-Path $PackageRoot "app/$file"
        if (-not (Test-Path -LiteralPath $source)) { throw ('Missing package file: ' + $file) }
        Copy-Item -LiteralPath $source -Destination (Join-Path $stage $file)
    }
    # Stop only processes executing this installation's scripts before updating.
    $escaped = [Regex]::Escape($Destination)
    $running = @(Get-CimInstance Win32_Process | Where-Object { $_.Name -eq 'powershell.exe' -and $_.CommandLine -match ($escaped + '\\(?:Widget|Collector)\.ps1"') })
    foreach ($process in $running) { Stop-Process -Id $process.ProcessId -ErrorAction Stop }
    [void][IO.Directory]::CreateDirectory($Destination)
    foreach ($file in $files) { Copy-Item -LiteralPath (Join-Path $stage $file) -Destination (Join-Path $Destination $file) -Force }
    Copy-Item -LiteralPath (Join-Path $stage 'vendor') -Destination $Destination -Recurse -Force
    foreach ($file in @('README.md','LICENSE')) { Copy-Item -LiteralPath (Join-Path $PackageRoot $file) -Destination (Join-Path $Destination $file) -Force }
    if (-not $NoShortcut) {
        $shell = New-Object -ComObject WScript.Shell
        $link = $shell.CreateShortcut((Join-Path ([Environment]::GetFolderPath('Desktop')) 'Температуры ПК.lnk'))
        $link.TargetPath = Join-Path $env:WINDIR 'System32/wscript.exe'
        $link.Arguments = '"' + (Join-Path $Destination 'Start.vbs') + '"'
        $link.WorkingDirectory = $Destination
        $link.IconLocation = "$env:WINDIR\System32\perfmon.exe,0"
        $link.Description = 'Прозрачный виджет температур ПК'
        $link.Save()
    }
    $sensorsReady = Test-Path 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\PawnIO'
    if (-not $NoSensors -and -not $sensorsReady) {
        Write-Host 'Confirm the Windows UAC prompt to install the sensor driver.'
        try {
            $process = Start-Process -FilePath (Join-Path $Destination 'vendor/PawnIO_setup.exe') -Verb RunAs -ArgumentList '-install -silent' -PassThru
            $process.WaitForExit()
            if ($process.ExitCode -notin @(0,3010)) { throw ('PawnIO exit code: ' + $process.ExitCode) }
            $sensorsReady = Test-Path 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\PawnIO'
            if ($process.ExitCode -eq 3010) { Write-Warning 'Windows restart is needed for the sensor driver.' }
        } catch { Write-Warning ('Sensor setup not completed. Use the widget menu later. ' + $_.Exception.Message) }
    }
    if (-not $NoLaunch) {
        $powershell = Join-Path $env:WINDIR 'System32/WindowsPowerShell/v1.0/powershell.exe'
        $args = '-NoProfile -ExecutionPolicy Bypass -STA -File "' + (Join-Path $Destination 'Widget.ps1') + '" -WaitForPrevious'
        try {
            if ($sensorsReady -and -not $NoSensors) { Start-Process $powershell -Verb RunAs -WindowStyle Hidden -ArgumentList $args }
            else { Start-Process $powershell -WindowStyle Hidden -ArgumentList $args }
        } catch {
            Write-Warning 'Administrator launch cancelled. Starting without CPU sensor access.'
            Start-Process $powershell -WindowStyle Hidden -ArgumentList $args
        }
    }
    Write-Host ('Installed: ' + $Destination) -ForegroundColor Green
} catch { Write-Error $_; exit 1 }
finally {
    $resolved = [IO.Path]::GetFullPath($stage)
    $tempRoot = [IO.Path]::GetFullPath([IO.Path]::GetTempPath()).TrimEnd('\') + '\'
    if ($resolved.StartsWith($tempRoot,[StringComparison]::OrdinalIgnoreCase) -and (Split-Path $resolved -Leaf) -like 'TemperatureWidget-Stage-*') {
        Remove-Item -LiteralPath $resolved -Recurse -Force -ErrorAction SilentlyContinue
    }
}
