param([switch]$Preview, [switch]$WaitForPrevious)
$ErrorActionPreference = 'Stop'
Set-Location $PSScriptRoot
Add-Type -AssemblyName PresentationFramework,PresentationCore,WindowsBase
$mutex = New-Object Threading.Mutex($false, 'Local\StebnTemperatureWidget')
if (-not $Preview -and -not $mutex.WaitOne($(if ($WaitForPrevious) { 10000 } else { 0 }))) { exit }
$configPath = Join-Path $PSScriptRoot 'settings.json'
$config = @{ left=$null; top=80; opacity=0.55; topmost=$false }
if (Test-Path $configPath) { try { $saved = Get-Content $configPath -Raw | ConvertFrom-Json; foreach ($key in @('left','top','opacity','topmost')) { if ($null -ne $saved.$key) { $config[$key]=$saved.$key } } } catch {} }
[xml]$xaml = @'
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation" xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml" Title="Температуры ПК" Width="300" SizeToContent="Height" WindowStyle="None" ResizeMode="NoResize" AllowsTransparency="True" Background="Transparent" ShowInTaskbar="False" FontFamily="Segoe UI" Foreground="#F2F5FC">
 <Border x:Name="Panel" CornerRadius="20" Padding="22,18,22,16" BorderBrush="#35FFFFFF" BorderThickness="1">
  <StackPanel>
   <Grid Margin="0,0,0,18"><TextBlock Text="МОЙ КОМПЬЮТЕР" FontSize="11" FontWeight="SemiBold" Foreground="#B9C7DC"/><TextBlock x:Name="Live" Text="●" HorizontalAlignment="Right" Foreground="#68E4B2"/></Grid>
   <TextBlock Text="ПРОЦЕССОР" FontSize="10" Foreground="#A5B8D2"/>
   <Grid Margin="0,3,0,0"><TextBlock x:Name="CpuTemp" Text="— °C" FontSize="35" FontWeight="Light"/><TextBlock x:Name="CpuLoad" Text="— %" HorizontalAlignment="Right" VerticalAlignment="Center" FontSize="18"/></Grid>
   <TextBlock x:Name="CpuName" Text="Процессор" FontSize="11" Foreground="#B9C7DC" TextTrimming="CharacterEllipsis"/>
   <ProgressBar x:Name="CpuBar" Height="3" Margin="0,10,0,18" Maximum="100" BorderThickness="0" Background="#25FFFFFF" Foreground="#7DB4FF"/>
   <TextBlock Text="ВИДЕОКАРТА" FontSize="10" Foreground="#A5B8D2"/>
   <Grid Margin="0,3,0,0"><TextBlock x:Name="GpuTemp" Text="— °C" FontSize="35" FontWeight="Light"/><TextBlock x:Name="GpuLoad" Text="— %" HorizontalAlignment="Right" VerticalAlignment="Center" FontSize="18"/></Grid>
   <TextBlock x:Name="GpuName" Text="Видеокарта" FontSize="11" Foreground="#B9C7DC" TextTrimming="CharacterEllipsis"/>
   <ProgressBar x:Name="GpuBar" Height="3" Margin="0,10,0,18" Maximum="100" BorderThickness="0" Background="#25FFFFFF" Foreground="#68E4B2"/>
   <Grid Margin="0,0,0,9"><TextBlock Text="Оперативная память" FontSize="12" Foreground="#B9C7DC"/><TextBlock x:Name="Ram" Text="—" HorizontalAlignment="Right" FontSize="12"/></Grid>
   <Grid Margin="0,0,0,9"><TextBlock Text="Видеопамять" FontSize="12" Foreground="#B9C7DC"/><TextBlock x:Name="Vram" Text="—" HorizontalAlignment="Right" FontSize="12"/></Grid>
   <TextBlock x:Name="Disks" FontSize="11" Foreground="#B9C7DC" TextWrapping="Wrap" Margin="0,2,0,4"/>
   <TextBlock x:Name="Fans" FontSize="11" Foreground="#B9C7DC" TextWrapping="Wrap" Margin="0,2,0,4"/>
   <TextBlock x:Name="Status" Text="Получаю показания…" FontSize="10" Foreground="#AAC0DD" TextWrapping="Wrap" Margin="0,10,0,0"/>
  </StackPanel>
 </Border>
</Window>
'@
$window = [Windows.Markup.XamlReader]::Load([Xml.XmlNodeReader]::new($xaml))
$ui = @{}
foreach ($name in @('Panel','Live','CpuName','CpuTemp','CpuLoad','CpuBar','GpuTemp','GpuLoad','GpuBar','GpuName','Ram','Vram','Disks','Fans','Status')) { $ui[$name]=$window.FindName($name) }
function Set-Background {
    $alpha = [byte]([Math]::Max(0.1,[Math]::Min(0.95,[double]$config.opacity))*255)
    $ui.Panel.Background = [Windows.Media.SolidColorBrush]::new([Windows.Media.Color]::FromArgb($alpha,12,20,34))
}
function Save-Settings {
    $config.left=$window.Left; $config.top=$window.Top; $config.topmost=$window.Topmost
    $config | ConvertTo-Json | Set-Content $configPath -Encoding UTF8
}
function Format-Value($value, $suffix, $digits=0) {
    if ($null -eq $value) { return "— $suffix" }
    return (([double]$value).ToString("F$digits", [Globalization.CultureInfo]::CurrentCulture) + " $suffix")
}
function Set-Temperature($control, $value) {
    $control.Text = Format-Value $value '°C'
    $color='#F2F5FC'
    if ($null -ne $value -and $value -ge 85) { $color='#FF8B83' } elseif ($null -ne $value -and $value -ge 70) { $color='#FFD28A' }
    $control.Foreground = [Windows.Media.BrushConverter]::new().ConvertFromString($color)
}
function Update-Readings {
    $path = Join-Path $PSScriptRoot 'readings.json'
    if (-not (Test-Path $path)) { return }
    try {
        $d=Get-Content $path -Raw | ConvertFrom-Json
        $cpuHardware=@($d.sensors | Where-Object kind -eq 'Cpu' | Select-Object -First 1)
        if ($cpuHardware.Count) { $ui.CpuName.Text=$cpuHardware[0].hardware }
        if (([DateTime]::UtcNow-[DateTime]::Parse($d.timestamp).ToUniversalTime()).TotalSeconds -gt 15) {
            foreach ($name in @('CpuTemp','GpuTemp','CpuLoad','GpuLoad','Ram','Vram')) { $ui[$name].Text='—' }
            $ui.CpuBar.Value=0; $ui.GpuBar.Value=0; $ui.Disks.Text=''; $ui.Fans.Text=''
            $ui.Status.Text='Нет свежих показаний. Перезапустите виджет.'; $ui.Live.Foreground=[Windows.Media.Brushes]::Orange; return
        }
        $cpu=@($d.sensors | Where-Object { $_.kind -eq 'Cpu' -and $_.type -eq 'Temperature' -and $_.value -gt 0 -and $_.value -lt 125 })
        $preferred=@($cpu | Where-Object { $_.name -match 'Tctl/Tdie|Package|Core \(Tdie\)' })
        $cpuTemp=$null
        if ($preferred.Count) { $cpuTemp=$preferred[0].value } elseif ($cpu.Count) { $cpuTemp=($cpu | Measure-Object value -Maximum).Maximum }
        Set-Temperature $ui.CpuTemp $cpuTemp
        $load=$d.cpuLoad
        $lhLoad=@($d.sensors | Where-Object { $_.kind -eq 'Cpu' -and $_.type -eq 'Load' -and $_.name -eq 'CPU Total' })
        if ($lhLoad.Count) { $load=$lhLoad[0].value }
        $ui.CpuLoad.Text=Format-Value $load '%'; $ui.CpuBar.Value=0
        if ($null -ne $load) { $ui.CpuBar.Value=[Math]::Min(100,[Math]::Max(0,$load)) }
        $gpuTemp=$d.gpu.temperature; $gpuLoad=$d.gpu.load
        if ($null -eq $gpuTemp) {
            $gs=@($d.sensors | Where-Object { $_.kind -match '^Gpu' -and $_.type -eq 'Temperature' -and $_.name -match 'Core' })
            if ($gs.Count) { $gpuTemp=$gs[0].value }
        }
        Set-Temperature $ui.GpuTemp $gpuTemp
        $ui.GpuLoad.Text=Format-Value $gpuLoad '%'; $ui.GpuBar.Value=0
        if ($null -ne $gpuLoad) { $ui.GpuBar.Value=$gpuLoad }
        if ($d.gpu.name) { $ui.GpuName.Text=$d.gpu.name }
        $ui.Ram.Text='—'; $ui.Vram.Text='—'
        if ($d.memory) { $ui.Ram.Text=('{0:F1} / {1:F0} ГБ' -f $d.memory.used,$d.memory.total) }
        if ($null -ne $d.gpu.used -and $null -ne $d.gpu.total) { $ui.Vram.Text=('{0:F1} / {1:F0} ГБ' -f ($d.gpu.used/1024),($d.gpu.total/1024)) }
        $disks=@($d.sensors | Where-Object { $_.kind -eq 'Storage' -and $_.type -eq 'Temperature' } | Group-Object hardware | ForEach-Object { $s=$_.Group | Sort-Object value -Descending | Select-Object -First 1; '{0}: {1:F0} °C' -f $_.Name,$s.value })
        $ui.Disks.Text=$disks -join "`n"
        $fans=@($d.sensors | Where-Object { $_.type -eq 'Fan' } | Select-Object -First 3 | ForEach-Object { '{0}: {1:F0} об/мин' -f $_.name,$_.value })
        $ui.Fans.Text=$fans -join "`n"
        $ui.Live.Foreground=[Windows.Media.BrushConverter]::new().ConvertFromString('#68E4B2')
        if ($null -eq $cpuTemp) {
            if (-not $d.pawnInstalled) { $ui.Status.Text='Температура CPU: нужен PawnIO. ПКМ → Настроить датчики.' }
            elseif (-not $d.admin) { $ui.Status.Text='Температура CPU: ПКМ → Запуск от администратора.' }
            else { $ui.Status.Text='Датчик температуры CPU пока недоступен.' }
        } else { $ui.Status.Text='Обновление каждые 2 с · ПКМ — настройки' }
        if ($d.error) { $ui.Status.ToolTip=$d.error }
    } catch { $ui.Status.Text='Ожидаю показания датчиков…' }
}
Set-Background
$area=[Windows.SystemParameters]::WorkArea
$window.Left=$area.Right-$window.Width-30
if ($null -ne $config.left) { $window.Left=[double]$config.left }
$window.Top=[double]$config.top
$window.Left=[Math]::Max([Windows.SystemParameters]::VirtualScreenLeft,[Math]::Min($window.Left,[Windows.SystemParameters]::VirtualScreenLeft+[Windows.SystemParameters]::VirtualScreenWidth-$window.Width))
$window.Top=[Math]::Max([Windows.SystemParameters]::VirtualScreenTop,[Math]::Min($window.Top,[Windows.SystemParameters]::VirtualScreenTop+[Windows.SystemParameters]::VirtualScreenHeight-450))
$window.Topmost=[bool]$config.topmost
$window.Add_MouseLeftButtonDown({ if ($_.ChangedButton -eq 'Left') { $window.DragMove(); Save-Settings } })
$menu=[Windows.Controls.ContextMenu]::new()
function Add-Menu($label, $handler) { $item=[Windows.Controls.MenuItem]::new(); $item.Header=$label; $item.Add_Click($handler); [void]$menu.Items.Add($item); return $item }
$topItem=Add-Menu 'Поверх всех окон' { $window.Topmost=-not $window.Topmost; $topItem.IsChecked=$window.Topmost; Save-Settings }
$topItem.IsCheckable=$true; $topItem.IsChecked=$window.Topmost
[void](Add-Menu 'Фон: почти прозрачный' { $config.opacity=0.2; Set-Background; Save-Settings })
[void](Add-Menu 'Фон: полупрозрачный' { $config.opacity=0.55; Set-Background; Save-Settings })
[void](Add-Menu 'Фон: тёмный' { $config.opacity=0.85; Set-Background; Save-Settings })
[void](Add-Menu 'Настроить датчики CPU (PawnIO)' { Start-Process "$env:WINDIR\System32\WindowsPowerShell\v1.0\powershell.exe" -WindowStyle Hidden -ArgumentList ('-NoProfile -ExecutionPolicy Bypass -File "{0}\Setup-Sensors.ps1"' -f $PSScriptRoot) })
[void](Add-Menu 'Запуск от администратора' {
    try {
        Start-Process "$env:WINDIR\System32\WindowsPowerShell\v1.0\powershell.exe" -Verb RunAs -WindowStyle Hidden -ArgumentList ('-NoProfile -ExecutionPolicy Bypass -STA -File "{0}\Widget.ps1" -WaitForPrevious' -f $PSScriptRoot)
        $window.Close()
    } catch { $ui.Status.Text='Запуск с правами администратора отменён.' }
})
[void](Add-Menu 'Закрыть виджет' { $window.Close() })
$window.ContextMenu=$menu
$worker=$null
$timer=[Windows.Threading.DispatcherTimer]::new(); $timer.Interval=[TimeSpan]::FromSeconds(2)
$timer.Add_Tick({ Update-Readings })
$window.Add_Closed({ $timer.Stop(); Save-Settings; if ($worker) { Stop-Process -Id $worker.Id -ErrorAction SilentlyContinue }; if (-not $Preview) { $mutex.ReleaseMutex() }; $mutex.Dispose() })
if ($Preview) {
    Update-Readings
    $panel=$ui.Panel
    $panel.Measure([Windows.Size]::new(300,1000)); $panel.Arrange([Windows.Rect]::new(0,0,300,$panel.DesiredSize.Height)); $panel.UpdateLayout()
    $bitmap=[Windows.Media.Imaging.RenderTargetBitmap]::new(300,[int][Math]::Ceiling($panel.ActualHeight),96,96,[Windows.Media.PixelFormats]::Pbgra32)
    $bitmap.Render($panel)
    $encoder=[Windows.Media.Imaging.PngBitmapEncoder]::new(); $encoder.Frames.Add([Windows.Media.Imaging.BitmapFrame]::Create($bitmap))
    $stream=[IO.File]::Create((Join-Path $PSScriptRoot 'preview.png')); $encoder.Save($stream); $stream.Dispose(); $mutex.Dispose(); exit
}
try {
    $worker=Start-Process "$env:WINDIR\System32\WindowsPowerShell\v1.0\powershell.exe" -WindowStyle Hidden -PassThru -ArgumentList ('-NoProfile -ExecutionPolicy Bypass -File "{0}\Collector.ps1" -OwnerPid {1}' -f $PSScriptRoot,$PID)
    $timer.Start(); Update-Readings
    [void]$window.ShowDialog()
} catch { $_ | Out-String | Set-Content (Join-Path $PSScriptRoot 'widget-error.log'); throw }
