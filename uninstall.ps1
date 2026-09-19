param([string]$Mode = '')
$ErrorActionPreference = 'Stop'
$silent = $Mode -in @('/silent', '/s', '-silent', '-s')
function Confirm-Yes([string]$prompt) {
    return ((Read-Host $prompt).Trim() -match '^(?i:y|yes)$')
}
try {
    $target = [IO.Path]::GetFullPath((Join-Path $env:LOCALAPPDATA 'Programs\JA_LAN_Messenger')).TrimEnd('\')
    $origin = [IO.Path]::GetFullPath($env:UNINSTALL_ORIGIN).TrimEnd('\')
    $key = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Uninstall\JA_LAN_Messenger'
    $registered = (Get-ItemProperty -LiteralPath $key -ErrorAction Stop).InstallLocation
    if ($origin -ne $target -or $registered -ne $target) {
        throw 'Run the uninstaller from the registered installation, not a portable/source folder.'
    }
    function Assert-PlainDirectory([string]$path) {
        $item = Get-Item -LiteralPath $path -Force
        for ($parent = $item; $null -ne $parent; $parent = $parent.Parent) {
            if ($parent.Attributes -band [IO.FileAttributes]::ReparsePoint) { throw 'Linked directory refused.' }
        }
        if (Get-ChildItem -LiteralPath $path -Force -Recurse | Where-Object { $_.Attributes -band [IO.FileAttributes]::ReparsePoint }) {
            throw 'Linked content refused.'
        }
    }
    if (Test-Path -LiteralPath $target) { Assert-PlainDirectory $target }
    $purge = $false
    if (-not $silent) {
        if (-not (Confirm-Yes 'Uninstall JA LAN Messenger? (Yes/No)')) {
            Write-Host 'Uninstall cancelled.'
            exit 0
        }
        $purge = Confirm-Yes 'Delete chat history and preferences too? (Yes/No; default No)'
    }
    $exe = Join-Path $target 'ja_lan_messenger.exe'
    $running = @(Get-Process ja_lan_messenger -ErrorAction SilentlyContinue | Where-Object { $_.Path -eq $exe })
    if ($running.Count) {
        if ($silent) { throw 'App is running. Interactive uninstall is required to confirm termination.' }
        if (-not (Confirm-Yes 'App is running. Kill the installed app and continue uninstalling? Unsaved changes may be lost. (Yes/No)')) {
            Write-Host 'Uninstall cancelled. Application was not stopped.'
            exit 0
        }
        foreach ($app in $running) {
            $current = Get-Process -Id $app.Id -ErrorAction SilentlyContinue
            if ($current -and $current.Path -eq $exe) {
                Stop-Process -InputObject $current -Force
                if (-not $current.WaitForExit(5000)) { throw 'Application did not exit.' }
            }
        }
    }
    $dataDirs = @((Join-Path $env:APPDATA 'JA_LAN_Messenger'), (Join-Path $env:LOCALAPPDATA 'JA_LAN_Messenger'))
    if ($purge) {
        foreach ($dir in $dataDirs) { if (Test-Path -LiteralPath $dir) { Assert-PlainDirectory $dir } }
    }
    Set-Location -LiteralPath $env:TEMP
    if (Test-Path -LiteralPath $target) { Remove-Item -LiteralPath $target -Recurse -Force }
    if ($purge) {
        foreach ($dir in $dataDirs) { if (Test-Path -LiteralPath $dir) { Remove-Item -LiteralPath $dir -Recurse -Force } }
    }
    $desktop = Join-Path ([Environment]::GetFolderPath('Desktop')) 'JA LAN Messenger.lnk'
    $menu = Join-Path $env:APPDATA 'Microsoft\Windows\Start Menu\Programs\JA LAN Messenger'
    $shell = New-Object -ComObject WScript.Shell
    foreach ($link in @($desktop, (Join-Path $menu 'JA LAN Messenger.lnk'), (Join-Path $menu 'Uninstall JA LAN Messenger.lnk'))) {
        if (Test-Path -LiteralPath $link) {
            $shortcut = $shell.CreateShortcut($link)
            if ($shortcut.TargetPath -eq $exe -or $shortcut.Arguments.Contains((Join-Path $target 'uninstall.bat'))) {
                Remove-Item -LiteralPath $link -Force
            }
        }
    }
    if ((Test-Path -LiteralPath $menu) -and -not (Get-ChildItem -LiteralPath $menu -Force)) { Remove-Item -LiteralPath $menu }
    $runKey = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Run'
    foreach ($name in @('JA LAN Messenger', 'JA_LAN_Messenger')) {
        $properties = Get-ItemProperty -LiteralPath $runKey -ErrorAction SilentlyContinue
        $value = if ($properties) { $properties.PSObject.Properties[$name].Value } else { $null }
        if ($value -and $value.Contains($exe)) { Remove-ItemProperty -LiteralPath $runKey -Name $name }
    }
    Remove-Item -LiteralPath $key
    Write-Host 'Uninstall completed.'
    exit 0
} catch {
    Write-Host ('Uninstall failed: ' + $_.Exception.Message)
    if (-not $silent) { Read-Host 'Press Enter to close' | Out-Null }
    exit 1
}
