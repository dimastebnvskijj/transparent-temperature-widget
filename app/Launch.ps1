$ErrorActionPreference = 'Stop'
$powershell = Join-Path $env:WINDIR 'System32/WindowsPowerShell/v1.0/powershell.exe'
$arguments = '-NoProfile -ExecutionPolicy Bypass -STA -File "' + (Join-Path $PSScriptRoot 'Widget.ps1') + '" -WaitForPrevious'
if (Test-Path 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\PawnIO') {
    try { Start-Process $powershell -Verb RunAs -WindowStyle Hidden -ArgumentList $arguments; exit } catch { }
}
Start-Process $powershell -WindowStyle Hidden -ArgumentList $arguments
