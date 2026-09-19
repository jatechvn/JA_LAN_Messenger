$ErrorActionPreference = 'Stop'
$repo = Split-Path $PSScriptRoot -Parent
$testId = [guid]::NewGuid().ToString()
$root = Join-Path ([IO.Path]::GetTempPath()) ('ja-installer-' + $testId)
$package = Join-Path $root 'package with spaces'
$local = Join-Path $root 'local'
$roaming = Join-Path $root 'roaming'
$desktop = Join-Path $root 'desktop'
$temp = Join-Path $root 'temp'
$regBase = 'HKCU\Software\JA-Tech\InstallerTests\' + $testId
$regProvider = $regBase.Replace('HKCU\', 'HKCU:\')
$target = Join-Path $local 'Programs\JA_LAN_Messenger'
New-Item -ItemType Directory -Path $package,$local,$roaming,$desktop,$temp -Force | Out-Null
function Assert([bool]$condition, [string]$message) { if (-not $condition) { throw $message } }
function Run-Batch([string]$file, [string]$arguments, [string]$inputText = '', [string]$command = '') {
    $info = New-Object Diagnostics.ProcessStartInfo
    $info.FileName = $env:ComSpec
    $info.Arguments = '/d /c ""' + $file + '" ' + $arguments + '"'
    if ($command) { $info.Arguments = $command }
    $info.WorkingDirectory = $temp
    $info.UseShellExecute = $false
    $info.CreateNoWindow = $true
    $info.RedirectStandardInput = $true
    $info.RedirectStandardOutput = $true
    $info.RedirectStandardError = $true
    $info.EnvironmentVariables['LOCALAPPDATA'] = $local
    $info.EnvironmentVariables['APPDATA'] = $roaming
    $info.EnvironmentVariables['TEMP'] = $temp
    $info.EnvironmentVariables['TMP'] = $temp
    $info.EnvironmentVariables['JA_TEST_DESKTOP'] = $desktop
    $process = [Diagnostics.Process]::Start($info)
    $stdout = $process.StandardOutput.ReadToEndAsync()
    $stderr = $process.StandardError.ReadToEndAsync()
    $process.StandardInput.Write($inputText)
    $process.StandardInput.Close()
    if (-not $process.WaitForExit(45000)) { $process.Kill(); throw 'Installer timed out' }
    $result = @{ exit=$process.ExitCode; output=$stdout.Result; error=$stderr.Result }
    $result | ConvertTo-Json | Add-Content -LiteralPath (Join-Path $root 'commands.log')
    return $result
}
try {
    foreach ($name in @('install.bat','uninstall.bat','uninstall.ps1')) {
        $text = [IO.File]::ReadAllText((Join-Path $repo $name))
        $text = $text.Replace('HKCU\Software\Microsoft\Windows\CurrentVersion', $regBase).Replace('HKCU:\Software\Microsoft\Windows\CurrentVersion', $regProvider)
        $text = $text.Replace("[Environment]::GetFolderPath('Desktop')", '$env:JA_TEST_DESKTOP')
        [IO.File]::WriteAllText((Join-Path $package $name), $text, [Text.UTF8Encoding]::new($name.EndsWith('.ps1')))
    }
    $install = Join-Path $package 'install.bat'
    Assert ((Run-Batch $install '/silent').exit -ne 0) 'Missing payload must fail without blocking'
    New-Item -ItemType Directory -Path (Join-Path $package 'data') | Out-Null
    foreach ($name in @('ja_lan_messenger.exe','flutter_windows.dll','data\app.so','data\icudtl.dat')) { [IO.File]::WriteAllText((Join-Path $package $name), 'fixture only') }
    $result = Run-Batch $install '/silent'
    Assert ($result.exit -eq 0) ('Install failed: ' + $result.output + $result.error)
    $key = $regProvider + '\Uninstall\JA_LAN_Messenger'
    Assert ((Get-ItemProperty -LiteralPath $key).InstallLocation -eq $target) 'Wrong registration'
    $shell = New-Object -ComObject WScript.Shell
    Assert ($shell.CreateShortcut((Join-Path $desktop 'JA LAN Messenger.lnk')).TargetPath -eq (Join-Path $target 'ja_lan_messenger.exe')) 'Wrong desktop shortcut'
    $data = Join-Path $roaming 'JA_LAN_Messenger'
    New-Item -ItemType Directory -Path $data | Out-Null
    [IO.File]::WriteAllText((Join-Path $data 'history.json'), 'private fixture')
    [IO.File]::WriteAllText((Join-Path $target 'user_preferences.json'), 'keep fixture')
    [IO.File]::WriteAllText((Join-Path $package 'user_preferences.json'), 'must not replace')
    Assert ((Run-Batch $install '/silent').exit -eq 0) 'Reinstall failed'
    Assert ([IO.File]::ReadAllText((Join-Path $target 'user_preferences.json')) -eq 'keep fixture') 'Reinstall replaced preferences'
    Assert ((Run-Batch (Join-Path $package 'uninstall.bat') '/silent').exit -ne 0) 'Portable uninstall must be refused'
    Assert (Test-Path -LiteralPath $target) 'Portable uninstall removed installed app'
    $uninstall = Join-Path $target 'uninstall.bat'
    Assert ((Run-Batch $uninstall '' "n`r`n").exit -eq 0) 'Cancel failed'
    Assert (Test-Path -LiteralPath $target) 'Cancel removed app'
    $registeredCommand = (Get-ItemProperty -LiteralPath $key).QuietUninstallString
    # Real machines normally have Run, but not necessarily either app value.
    New-Item -Path ($regProvider + '\Run') -Force | Out-Null
    New-ItemProperty -LiteralPath ($regProvider + '\Run') -Name 'OtherApp' -Value 'keep' | Out-Null
    Assert ($registeredCommand.StartsWith('cmd.exe /c ')) 'Unexpected registry command'
    $result = Run-Batch '' '' '' $registeredCommand.Substring(8)
    Assert ($result.exit -eq 0) ('Silent uninstall failed: ' + $result.output + $result.error)
    Assert (-not (Test-Path -LiteralPath $target)) 'Installed directory remains'
    Assert (Test-Path -LiteralPath (Join-Path $data 'history.json')) 'Silent uninstall deleted history'
    Assert (-not (Test-Path -LiteralPath $key)) 'Registration remains'
    Assert ((Get-ItemProperty -LiteralPath ($regProvider + '\Run')).OtherApp -eq 'keep') 'Other startup entry changed'
    Assert (-not (Test-Path -LiteralPath (Join-Path $desktop 'JA LAN Messenger.lnk'))) 'Desktop shortcut remains'
    Assert ((Run-Batch $install '/silent').exit -eq 0) 'Install for purge test failed'
    $menuLink = Join-Path $roaming 'Microsoft\Windows\Start Menu\Programs\JA LAN Messenger\Uninstall JA LAN Messenger.lnk'
    $shortcut = $shell.CreateShortcut($menuLink)
    Assert ($shortcut.TargetPath.EndsWith('cmd.exe')) 'Uninstall shortcut target is wrong'
    # Exercise a running app without starting the real messenger or LAN services.
    $fixtureExe = Join-Path $root 'ja_lan_messenger.exe'
    Add-Type -TypeDefinition 'public class InstallerFixture { public static void Main() { System.Threading.Thread.Sleep(120000); } }' -OutputAssembly $fixtureExe -OutputType WindowsApplication
    Copy-Item -LiteralPath $fixtureExe -Destination (Join-Path $target 'ja_lan_messenger.exe') -Force
    $installedProcess = Start-Process -FilePath (Join-Path $target 'ja_lan_messenger.exe') -WindowStyle Hidden -PassThru
    $portableProcess = Start-Process -FilePath $fixtureExe -WindowStyle Hidden -PassThru
    try {
        $cancel = Run-Batch '' '' "yes`r`nno`r`nno`r`n" $shortcut.Arguments
        Assert ($cancel.exit -eq 0 -and -not $installedProcess.HasExited) 'Declining kill must keep app running'
        Assert (Test-Path -LiteralPath $key) 'Declining kill removed registration'
        $result = Run-Batch '' '' "yes`r`nyes`r`nyes`r`n" $shortcut.Arguments
        Assert ($installedProcess.WaitForExit(5000)) 'Installed process was not stopped'
        Assert (-not $portableProcess.HasExited) 'Uninstaller stopped unrelated portable app'
    } finally {
        foreach ($fixture in @($installedProcess, $portableProcess)) {
            if (-not $fixture.HasExited) { Stop-Process -Id $fixture.Id -Force }
        }
    }
    Assert ($result.exit -eq 0) ('Interactive purge failed: ' + $result.output + $result.error)
    Assert (-not (Test-Path -LiteralPath $data)) 'Confirmed purge did not remove data'
    Write-Output "PASS: isolated install, reinstall, shortcuts, registry, portable refusal, cancel, silent keep, interactive purge. Evidence: $root"
} finally {
    # This key is generated above for this run; never touches app registration.
    if ($regProvider -match '^HKCU:\\Software\\JA-Tech\\InstallerTests\\[0-9a-f-]{36}$' -and (Test-Path -LiteralPath $regProvider)) {
        Remove-Item -LiteralPath $regProvider -Recurse -Force
    }
}
