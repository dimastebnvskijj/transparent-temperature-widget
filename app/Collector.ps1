param([int]$OwnerPid = 0, [switch]$Once)
$ErrorActionPreference = 'Stop'
Set-Location $PSScriptRoot
$state = Join-Path $PSScriptRoot 'readings.json'
$computer = $null
$problem = $null
try {
    [void][Reflection.Assembly]::LoadFrom((Join-Path $PSScriptRoot 'vendor/lhm/LibreHardwareMonitorLib.dll'))
    $computer = New-Object LibreHardwareMonitor.Hardware.Computer
    $computer.IsCpuEnabled = $true
    $computer.IsGpuEnabled = $true
    $computer.IsMemoryEnabled = $true
    $computer.IsStorageEnabled = $true
    $computer.IsMotherboardEnabled = $true
    $computer.Open()
} catch { $problem = $_.Exception.Message }
function Read-Hardware($hardware) {
    try { $hardware.Update() } catch { return }
    foreach ($sensor in $hardware.Sensors) {
        if ($null -ne $sensor.Value) {
            [pscustomobject]@{ hardware=$hardware.Name; kind=[string]$hardware.HardwareType; name=$sensor.Name; type=[string]$sensor.SensorType; value=[double]$sensor.Value }
        }
    }
    foreach ($sub in $hardware.SubHardware) { Read-Hardware $sub }
}
try {
    do {
        if ($OwnerPid -gt 0 -and -not (Get-Process -Id $OwnerPid -ErrorAction SilentlyContinue)) { break }
        $sensors = @()
        if ($computer) { $sensors = @(foreach ($hw in $computer.Hardware) { Read-Hardware $hw }) }
        $gpu = $null
        $gpuSensors=@($sensors | Where-Object { $_.kind -match '^Gpu' })
        if ($gpuSensors.Count) { $gpuSensors=@($gpuSensors | Where-Object hardware -eq $gpuSensors[0].hardware) }
        if ($gpuSensors.Count) {
            $gpu=@{ name=$gpuSensors[0].hardware; temperature=$null; load=$null; used=$null; total=$null }
            $mapping=@{ temperature='GPU Core'; load='GPU Core'; used='GPU Memory Used'; total='GPU Memory Total' }
            foreach ($key in @('temperature','load','used','total')) {
                $type=if ($key -eq 'temperature') { 'Temperature' } elseif ($key -eq 'load') { 'Load' } else { 'SmallData' }
                $sensor=@($gpuSensors | Where-Object { $_.name -eq $mapping[$key] -and $_.type -eq $type })
                if ($sensor.Count) { $gpu[$key]=$sensor[0].value }
            }
        }
        if (-not $gpu) { try {
            $line = & "$env:WINDIR\System32\nvidia-smi.exe" --query-gpu=name,temperature.gpu,utilization.gpu,memory.used,memory.total --format=csv,noheader,nounits 2>$null | Select-Object -First 1
            if ($LASTEXITCODE -eq 0 -and $line) {
                $parts = $line.Split(',')
                $gpu = @{ name=$parts[0].Trim(); temperature=$null; load=$null; used=$null; total=$null }
                $keys = @('temperature','load','used','total')
                for ($i=1; $i -lt 5; $i++) {
                    $number = 0.0
                    if ([double]::TryParse($parts[$i].Trim(), [Globalization.NumberStyles]::Float, [Globalization.CultureInfo]::InvariantCulture, [ref]$number)) { $gpu[$keys[$i-1]] = $number }
                }
            }
        } catch { } }
        $memory = $null; $cpuLoad = $null
        try {
            $os = Get-CimInstance Win32_OperatingSystem
            $memory = @{ used=($os.TotalVisibleMemorySize-$os.FreePhysicalMemory)/1MB; total=$os.TotalVisibleMemorySize/1MB }
            $cpuLoad = (Get-CimInstance Win32_PerfFormattedData_PerfOS_Processor -Filter "Name='_Total'").PercentProcessorTime
        } catch { }
        $admin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
        $pawn = $false
        try { $pawn = [LibreHardwareMonitor.PawnIo.PawnIo]::IsInstalled } catch { }
        $data = @{ timestamp=[DateTime]::UtcNow.ToString('o'); sensors=$sensors; gpu=$gpu; memory=$memory; cpuLoad=$cpuLoad; admin=$admin; pawnInstalled=$pawn; error=$problem }
        $json = $data | ConvertTo-Json -Depth 6
        [IO.File]::WriteAllText("$state.tmp", $json, [Text.UTF8Encoding]::new($false))
        Move-Item -LiteralPath "$state.tmp" -Destination $state -Force
        if ($Once) { break }
        Start-Sleep -Seconds 2
    } while ($true)
} catch {
    $_ | Out-String | Set-Content (Join-Path $PSScriptRoot 'collector-error.log')
} finally { if ($computer) { $computer.Close() } }
