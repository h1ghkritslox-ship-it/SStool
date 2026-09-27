# === Requires Administrator ===
if (-NOT ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Write-Host "Run this script as Administrator!" -ForegroundColor Red
    pause
    exit
}

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

# === Hide taskbar, start menu and block Ctrl+Alt+Del shortcuts where possible ===
# Kill explorer so taskbar/start menu disappear
Stop-Process -Name explorer -Force -ErrorAction SilentlyContinue

# Disable power button actions
powercfg /setacvalueindex SCHEME_CURRENT SUB_BUTTONS PBUTTONACTION 0 2>$null
powercfg /setdcvalueindex SCHEME_CURRENT SUB_BUTTONS PBUTTONACTION 0 2>$null
powercfg /setacvalueindex SCHEME_CURRENT SUB_BUTTONS SBUTTONACTION 0 2>$null
powercfg /setdcvalueindex SCHEME_CURRENT SUB_BUTTONS SBUTTONACTION 0 2>$null
powercfg /setacvalueindex SCHEME_CURRENT SUB_BUTTONS LIDACTION 0 2>$null
powercfg /setactive SCHEME_CURRENT

# Disable shutdown/sleep/hibernate/restart via policy
$regPath = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\Explorer"
if (-not (Test-Path $regPath)) { New-Item -Path $regPath -Force | Out-Null }
Set-ItemProperty -Path $regPath -Name "NoClose"        -Value 1 -Type DWord
Set-ItemProperty -Path $regPath -Name "NoLogoff"       -Value 1 -Type DWord
Set-ItemProperty -Path $regPath -Name "StartMenuLogOff" -Value 1 -Type DWord

# Block Ctrl+Alt+Del options (lock, change password, task manager, sign out)
$sysPath = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System"
if (-not (Test-Path $sysPath)) { New-Item -Path $sysPath -Force | Out-Null }
Set-ItemProperty -Path $sysPath -Name "DisableTaskMgr"        -Value 1 -Type DWord
Set-ItemProperty -Path $sysPath -Name "DisableLockWorkstation" -Value 1 -Type DWord
Set-ItemProperty -Path $sysPath -Name "DisableChangePassword"  -Value 1 -Type DWord
Set-ItemProperty -Path $sysPath -Name "HideFastUserSwitching"  -Value 1 -Type DWord
Set-ItemProperty -Path $sysPath -Name "ShutdownWithoutLogon"   -Value 0 -Type DWord

# Block shutdown from command line by disabling SeShutdownPrivilege for current user
# (best-effort — hardware power button long-press still works)
$privPath = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System"
Set-ItemProperty -Path $privPath -Name "VerboseStatus" -Value 0 -Type DWord

# === Black fullscreen form ===
$form = New-Object System.Windows.Forms.Form
$form.FormBorderStyle   = 'None'
$form.WindowState       = 'Maximized'
$form.BackColor         = [System.Drawing.Color]::Black
$form.TopMost           = $true
$form.ShowInTaskbar     = $false
$form.KeyPreview        = $true
$form.ControlBox        = $false
$form.MinimizeBox       = $false
$form.MaximizeBox       = $false

$script:allowExit = $false

# Block keys and handle F12 exit
$form.Add_KeyDown({
    param($sender, $e)

    # Exit on F12
    if ($e.KeyCode -eq [System.Windows.Forms.Keys]::F12) {
        $script:allowExit = $true
        $form.Close()
        return
    }

    # Block Esc, Alt+F4, Alt+Tab, Win key, Ctrl+Esc, Alt+Esc
    $blocked = @(
        [System.Windows.Forms.Keys]::Escape,
        [System.Windows.Forms.Keys]::LWin,
        [System.Windows.Forms.Keys]::RWin,
        [System.Windows.Forms.Keys]::Tab
    )

    if ($blocked -contains $e.KeyCode) {
        $e.Handled = $true
        $e.SuppressKeyPress = $true
        return
    }

    if ($e.Alt -and ($e.KeyCode -eq [System.Windows.Forms.Keys]::F4 -or
                     $e.KeyCode -eq [System.Windows.Forms.Keys]::Tab)) {
        $e.Handled = $true
        $e.SuppressKeyPress = $true
    }
})

# Prevent form from closing/losing focus
$form.Add_FormClosing({
    param($sender, $e)
    if (-not $script:allowExit) { $e.Cancel = $true }
})

# If form loses focus (e.g. via Win key), bring it back
$form.Add_Deactivate({
    if (-not $script:allowExit) {
        $form.Activate()
        $form.TopMost = $true
    }
})

# === Watchdog timer: re-apply restrictions every second ===
$timer = New-Object System.Windows.Forms.Timer
$timer.Interval = 1000
$timer.Add_Tick({
    # Re-apply power button block
    powercfg /setacvalueindex SCHEME_CURRENT SUB_BUTTONS PBUTTONACTION 0 2>$null
    powercfg /setactive SCHEME_CURRENT

    # Kill explorer if it comes back (Win+E, Ctrl+Shift+Esc attempts)
    $exp = Get-Process -Name explorer -ErrorAction SilentlyContinue
    if ($exp) { Stop-Process -Name explorer -Force -ErrorAction SilentlyContinue }

    # Kill Task Manager if it tries to open
    Get-Process -Name Taskmgr -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue

    # Re-apply policies in case something resets them
    Set-ItemProperty -Path $regPath -Name "NoClose"  -Value 1 -Type DWord -ErrorAction SilentlyContinue
    Set-ItemProperty -Path $sysPath -Name "DisableTaskMgr" -Value 1 -Type DWord -ErrorAction SilentlyContinue

    # Force form to stay on top and focused
    if (-not $script:allowExit) {
        $form.TopMost = $true
        if ($form.WindowState -ne 'Maximized') { $form.WindowState = 'Maximized' }
    }
})
$timer.Start()

Write-Host "Black screen active. Press F12 to exit." -ForegroundColor Yellow

# Show fullscreen black form
[void]$form.ShowDialog()

# === Restore everything on exit ===
$timer.Stop()
$timer.Dispose()

# Restore power button defaults
powercfg /setacvalueindex SCHEME_CURRENT SUB_BUTTONS PBUTTONACTION 1 2>$null
powercfg /setdcvalueindex SCHEME_CURRENT SUB_BUTTONS PBUTTONACTION 1 2>$null
powercfg /setacvalueindex SCHEME_CURRENT SUB_BUTTONS SBUTTONACTION 1 2>$null
powercfg /setacvalueindex SCHEME_CURRENT SUB_BUTTONS LIDACTION 1 2>$null
powercfg /setactive SCHEME_CURRENT

# Restore policies
Remove-ItemProperty -Path $regPath -Name "NoClose"         -ErrorAction SilentlyContinue
Remove-ItemProperty -Path $regPath -Name "NoLogoff"        -ErrorAction SilentlyContinue
Remove-ItemProperty -Path $regPath -Name "StartMenuLogOff" -ErrorAction SilentlyContinue

Remove-ItemProperty -Path $sysPath -Name "DisableTaskMgr"         -ErrorAction SilentlyContinue
Remove-ItemProperty -Path $sysPath -Name "DisableLockWorkstation" -ErrorAction SilentlyContinue
Remove-ItemProperty -Path $sysPath -Name "DisableChangePassword"  -ErrorAction SilentlyContinue
Remove-ItemProperty -Path $sysPath -Name "HideFastUserSwitching"  -ErrorAction SilentlyContinue

# Restart explorer to bring back the taskbar
Start-Process explorer.exe

Write-Host "Black screen disabled. Settings restored." -ForegroundColor Green
