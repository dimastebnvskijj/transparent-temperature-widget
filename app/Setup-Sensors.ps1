$ErrorActionPreference='Stop'
Add-Type -AssemblyName PresentationFramework
try {
    Import-Module (Join-Path $PSHOME 'Modules/Microsoft.PowerShell.Security/Microsoft.PowerShell.Security.psd1') -ErrorAction Stop
    $installer=Join-Path $PSScriptRoot 'vendor/PawnIO_setup.exe'
    if (-not (Test-Path $installer)) { throw 'Установщик PawnIO отсутствует в папке vendor.' }
    $signature=Get-AuthenticodeSignature -LiteralPath $installer
    if ($signature.Status -ne 'Valid') { throw 'Не удалось проверить цифровую подпись установщика PawnIO.' }
    $process=Start-Process -FilePath $installer -Verb RunAs -PassThru
    $process.WaitForExit()
    if ($process.ExitCode -ne 0) { throw ('Установщик завершился с кодом ' + $process.ExitCode) }
    [void][Windows.MessageBox]::Show('После установки выберите в меню виджета «Запуск от администратора», чтобы получить температуру процессора.', 'Датчики температуры')
} catch { [void][Windows.MessageBox]::Show($_.Exception.Message,'Настройка датчиков') }
