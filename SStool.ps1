# === Требуется запуск от администратора ===
if (-NOT ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Write-Host "Запустите скрипт от имени администратора!" -ForegroundColor Red
    pause
    exit
}

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

# === Блокировка выключения/перезагрузки/сна через системный API ===
$signature = @"
using System;
using System.Runtime.InteropServices;
public class PowerBlock {
    [DllImport("user32.dll")]
    public static extern bool BlockInput(bool fBlockIt);
    [DllImport("advapi32.dll", SetLastError=true)]
    public static extern bool InitiateSystemShutdown(string lpMachineName, string lpMessage, uint dwTimeout, bool bForceAppsClosed, bool bRebootAfterShutdown);
}
"@
Add-Type -TypeDefinition $signature

# Отключаем реакцию системы на кнопку питания через powercfg
powercfg /setacvalueindex SCHEME_CURRENT SUB_BUTTONS PBUTTONACTION 0 2>$null
powercfg /setdcvalueindex SCHEME_CURRENT SUB_BUTTONS PBUTTONACTION 0 2>$null
powercfg /setacvalueindex SCHEME_CURRENT SUB_BUTTONS SBUTTONACTION 0 2>$null
powercfg /setdcvalueindex SCHEME_CURRENT SUB_BUTTONS SBUTTONACTION 0 2>$null
powercfg /setacvalueindex SCHEME_CURRENT SUB_BUTTONS LIDACTION 0 2>$null
powercfg /setactive SCHEME_CURRENT

# Также отключаем завершение работы через меню "Пуск" (через политику)
$regPath = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\Explorer"
if (-not (Test-Path $regPath)) { New-Item -Path $regPath -Force | Out-Null }
Set-ItemProperty -Path $regPath -Name "NoClose" -Value 1 -Type DWord

# === Создаём чёрную форму на весь экран ===
$form = New-Object System.Windows.Forms.Form
$form.FormBorderStyle = 'None'
$form.WindowState = 'Maximized'
$form.BackColor = [System.Drawing.Color]::Black
$form.TopMost = $true
$form.ShowInTaskbar = $false
$form.KeyPreview = $true

# Блокируем Esc и Alt+F4
$form.Add_KeyDown({
    param($sender, $e)
    if ($e.KeyCode -eq [System.Windows.Forms.Keys]::Escape -or 
        ($e.Alt -and $e.KeyCode -eq [System.Windows.Forms.Keys]::F4)) {
        $e.Handled = $true
        $e.SuppressKeyPress = $true
    }
})

# Перехватываем закрытие формы (Alt+F4, крестик и т.д.)
$form.Add_FormClosing({
    param($sender, $e)
    if (-not $script:allowExit) { $e.Cancel = $true }
})

# Секретный выход: Ctrl+Shift+Q
$form.Add_KeyDown({
    param($sender, $e)
    if ($e.Control -and $e.Shift -and $e.KeyCode -eq [System.Windows.Forms.Keys]::Q) {
        $script:allowExit = $true
        $form.Close()
    }
})

# === Таймер для постоянной блокировки выключения ===
$timer = New-Object System.Windows.Forms.Timer
$timer.Interval = 1000
$timer.Add_Tick({
    # Повторно применяем powercfg на случай сброса
    powercfg /setacvalueindex SCHEME_CURRENT SUB_BUTTONS PBUTTONACTION 0 2>$null
    powercfg /setactive SCHEME_CURRENT
})
$timer.Start()

Write-Host "Чёрный экран активирован. Для выхода нажмите Ctrl+Shift+Q" -ForegroundColor Yellow

# Показываем форму
[void]$form.ShowDialog()

# === Восстановление при выходе ===
$timer.Stop()
$timer.Dispose()

# Возвращаем стандартное поведение кнопки питания (1 = выключение)
powercfg /setacvalueindex SCHEME_CURRENT SUB_BUTTONS PBUTTONACTION 1 2>$null
powercfg /setdcvalueindex SCHEME_CURRENT SUB_BUTTONS PBUTTONACTION 1 2>$null
powercfg /setacvalueindex SCHEME_CURRENT SUB_BUTTONS SBUTTONACTION 1 2>$null
powercfg /setacvalueindex SCHEME_CURRENT SUB_BUTTONS LIDACTION 1 2>$null
powercfg /setactive SCHEME_CURRENT

# Убираем запрет на завершение работы
Remove-ItemProperty -Path $regPath -Name "NoClose" -ErrorAction SilentlyContinue

Write-Host "Чёрный экран отключён. Настройки восстановлены." -ForegroundColor Green
