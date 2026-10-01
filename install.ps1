# Transparent Temperature Widget - one-line bootstrap (Windows PowerShell 5.1+).
param([string]$Destination = (Join-Path $env:LOCALAPPDATA 'TransparentTemperatureWidget'), [switch]$NoSensors, [switch]$NoLaunch, [switch]$NoShortcut)
$ErrorActionPreference = 'Stop'
$repository = 'dimastebnvskijj/transparent-temperature-widget'
$version = 'v1.0.0'
$expectedHash = '5164A65BC4B46C2B58C821544B29A0789E2D8F8A6CA815E48556AFCF4F16FCDC'
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
$bootstrapDir = Join-Path ([IO.Path]::GetTempPath()) ('TemperatureWidget-' + [Guid]::NewGuid().ToString('N'))
[void][IO.Directory]::CreateDirectory($bootstrapDir)
$archive = Join-Path $bootstrapDir 'widget.zip'
try {
    Write-Host 'Downloading Transparent Temperature Widget...'
    Invoke-WebRequest -UseBasicParsing "https://github.com/$repository/releases/download/$version/widget.zip" -OutFile $archive
    $sha = [Security.Cryptography.SHA256]::Create()
    $stream = [IO.File]::OpenRead($archive)
    try { $actualHash = ([BitConverter]::ToString($sha.ComputeHash($stream))).Replace('-','') } finally { $stream.Dispose(); $sha.Dispose() }
    if ($actualHash -ne $expectedHash) { throw 'Widget archive checksum mismatch. Installation stopped.' }
    Expand-Archive -LiteralPath $archive -DestinationPath $bootstrapDir
    $installer = Join-Path $bootstrapDir 'Install-App.ps1'
    $powershell = Join-Path $env:WINDIR 'System32/WindowsPowerShell/v1.0/powershell.exe'
    $installArguments = @('-NoProfile','-ExecutionPolicy','Bypass','-File',$installer,'-PackageRoot',$bootstrapDir,'-Destination',$Destination)
    if ($NoSensors) { $installArguments += '-NoSensors' }
    if ($NoLaunch) { $installArguments += '-NoLaunch' }
    if ($NoShortcut) { $installArguments += '-NoShortcut' }
    & $powershell @installArguments
    if ($LASTEXITCODE -ne 0) { throw 'Installation failed. See the message above.' }
} finally {
    $resolved = [IO.Path]::GetFullPath($bootstrapDir)
    $tempRoot = [IO.Path]::GetFullPath([IO.Path]::GetTempPath()).TrimEnd('\') + '\'
    if ($resolved.StartsWith($tempRoot,[StringComparison]::OrdinalIgnoreCase) -and (Split-Path $resolved -Leaf) -like 'TemperatureWidget-*') {
        Remove-Item -LiteralPath $resolved -Recurse -Force -ErrorAction SilentlyContinue
    }
}
