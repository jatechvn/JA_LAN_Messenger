# Refresh only pinned shortcuts targeting this exact executable; never clear the
# global Windows icon cache or restart Explorer. Backups are retained for rollback.
[CmdletBinding(SupportsShouldProcess)]
param(
    [string]$ExecutablePath = (Join-Path $PSScriptRoot '../build/windows/x64/runner/Release/ja_lan_messenger.exe'),
    [string]$IconPath = (Join-Path $PSScriptRoot '../assets/app_icon.ico')
)

$ErrorActionPreference = 'Stop'
$targetExe = (Resolve-Path -LiteralPath $ExecutablePath).Path
$sourceIcon = (Resolve-Path -LiteralPath $IconPath).Path
$pinnedDirectory = Join-Path $env:APPDATA 'Microsoft/Internet Explorer/Quick Launch/User Pinned/TaskBar'
$shell = New-Object -ComObject WScript.Shell
$matches = @()
try {
    foreach ($file in Get-ChildItem -LiteralPath $pinnedDirectory -Filter '*.lnk' -ErrorAction SilentlyContinue) {
        $link = $shell.CreateShortcut($file.FullName)
        if ([string]::Equals($link.TargetPath, $targetExe, [StringComparison]::OrdinalIgnoreCase)) {
            $matches += $file.FullName
        }
        [void][Runtime.InteropServices.Marshal]::FinalReleaseComObject($link)
    }
    if ($matches.Count -eq 0) {
        Write-Output 'No pinned shortcut targets this executable. No changes made.'
        return
    }

    $hash = (Get-FileHash -LiteralPath $sourceIcon -Algorithm SHA256).Hash.ToLowerInvariant()
    $cacheDirectory = Join-Path $env:LOCALAPPDATA 'JA_LAN_Messenger/taskbar-icons'
    $cachedIcon = Join-Path $cacheDirectory "$hash.ico"
    foreach ($path in $matches) {
        if (!$PSCmdlet.ShouldProcess($path, 'Back up shortcut and refresh its icon')) { continue }
        [void][IO.Directory]::CreateDirectory($cacheDirectory)
        if (!(Test-Path -LiteralPath $cachedIcon)) {
            Copy-Item -LiteralPath $sourceIcon -Destination $cachedIcon
        }
        if ((Get-FileHash -LiteralPath $cachedIcon -Algorithm SHA256).Hash.ToLowerInvariant() -ne $hash) {
            throw "Cached icon hash mismatch: $cachedIcon"
        }
        $backup = Join-Path $cacheDirectory (([guid]::NewGuid().ToString()) + '.lnk.backup')
        Copy-Item -LiteralPath $path -Destination $backup
        $link = $shell.CreateShortcut($path)
        try {
            $link.IconLocation = "$cachedIcon,0"
            $link.Save()
        } finally {
            [void][Runtime.InteropServices.Marshal]::FinalReleaseComObject($link)
        }
        $check = $shell.CreateShortcut($path)
        try {
            if ($check.IconLocation -ne "$cachedIcon,0" -or $check.TargetPath -ne $targetExe) {
                throw "Shortcut verification failed; original backup: $backup"
            }
        } finally {
            [void][Runtime.InteropServices.Marshal]::FinalReleaseComObject($check)
        }
        if (-not ('JaTaskbarIconRefresh' -as [type])) {
            Add-Type @'
using System;
using System.Runtime.InteropServices;
public static class JaTaskbarIconRefresh {
    [DllImport("shell32.dll", CharSet = CharSet.Unicode)]
    public static extern void SHChangeNotify(uint eventId, uint flags, string item1, IntPtr item2);
}
'@
        }
        # SHCNE_UPDATEITEM + SHCNF_PATHW + SHCNF_FLUSH: refresh this item only.
        [JaTaskbarIconRefresh]::SHChangeNotify(0x2000, 0x1005, $path, [IntPtr]::Zero)
        Write-Output "Updated: $path"
        Write-Output "Backup: $backup"
        Write-Output "Icon: $cachedIcon"
    }
} finally {
    [void][Runtime.InteropServices.Marshal]::FinalReleaseComObject($shell)
}
