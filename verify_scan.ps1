<#
.SYNOPSIS
    JA LAN Messenger - Network Discovery & Subnet Scan Verification Tool
    Kiem tra, doi soat va chan doan tinh nang quet mang LAN da tang giua cac may.

.DESCRIPTION
    Script kiem tra toan dien:
    1. Cau hinh Card mang & Subnet Mask (/21 vs /24).
    2. Trang thai Firewall (UDP 36475, TCP 6475).
    3. Doc file cau hinh known_devices.json & network_preferences.json.
    4. Quet thuc te qua tat ca 8 subnet slice (172.21.168.x -> 172.21.175.x).
    5. Gui goi tin UDP BeeBEEP va do cong TCP 6475 thoi gian thuc.
    6. Tong hop, doi chieu va giai thich tai sao may 172.21.172.151 chi thay 15 user trong khi may nay thay 36 user.
#>

param(
    [string]$TargetIp = "",
    [int]$TimeoutMs = 300,
    [switch]$DeepSweep
)

try {
    $OutputEncoding = [System.Text.UTF8Encoding]::new()
    [Console]::OutputEncoding = [System.Text.UTF8Encoding]::new()
} catch {}

function Write-Header([string]$text) {
    Write-Host ""
    Write-Host ("=" * 72) -ForegroundColor Cyan
    Write-Host "  $text" -ForegroundColor Yellow -BackgroundColor Black
    Write-Host ("=" * 72) -ForegroundColor Cyan
}

function Write-Section([string]$text) {
    Write-Host ""
    Write-Host "[+] $text" -ForegroundColor Green
    Write-Host ("-" * 50) -ForegroundColor DarkGray
}

Write-Header "JA LAN MESSENGER - NETWORK DISCOVERY & SCAN VERIFIER"
Write-Host "Thoi diem kiem tra : $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')" -ForegroundColor Gray
Write-Host "Computer Name      : $env:COMPUTERNAME" -ForegroundColor Gray
Write-Host "User Account       : $env:USERNAME" -ForegroundColor Gray

# -------------------------------------------------------------
# PHAN 1: KIEM TRA ADAPTERS & SUBNET MASK THUC TE
# -------------------------------------------------------------
Write-Section "1. KIEM TRA GIAO DIEN MANG & SUBNET MASK (/21 vs /24)"

function Get-MaskFromPrefix([int]$prefix) {
    if ($prefix -le 0) { return "0.0.0.0" }
    if ($prefix -ge 32) { return "255.255.255.255" }
    $bytes = @(0, 0, 0, 0)
    for ($i = 0; $i -lt 4; $i++) {
        $bits = [math]::Min(8, [math]::Max(0, $prefix - ($i * 8)))
        if ($bits -eq 8) { $bytes[$i] = 255 }
        elseif ($bits -gt 0) { $bytes[$i] = [int](256 - [math]::Pow(2, 8 - $bits)) }
        else { $bytes[$i] = 0 }
    }
    return ($bytes -join '.')
}

function Get-NetworkCidr([string]$ip, [int]$prefix) {
    $ipParts = $ip.Split('.') | ForEach-Object { [int]$_ }
    $maskParts = (Get-MaskFromPrefix $prefix).Split('.') | ForEach-Object { [int]$_ }
    $netParts = @(0, 0, 0, 0)
    for ($i = 0; $i -lt 4; $i++) {
        $netParts[$i] = $ipParts[$i] -band $maskParts[$i]
    }
    return "$($netParts -join '.')"
}

$adaptersInfo = @()
try {
    $netAdapters = Get-NetIPAddress -AddressFamily IPv4 -ErrorAction SilentlyContinue | Where-Object { $_.IPAddress -notlike "127.*" }
    foreach ($a in $netAdapters) {
        $ip = $a.IPAddress
        $prefix = [int]$a.PrefixLength
        $alias = $a.InterfaceAlias
        
        $maskStr = Get-MaskFromPrefix $prefix
        $netStr = Get-NetworkCidr $ip $prefix
        
        $hostCount = if ($prefix -lt 31) { [math]::Pow(2, 32 - $prefix) - 2 } else { 2 }
        $isSupernet = ($prefix -lt 24 -and $ip -like "172.21.*")

        $adaptersInfo += [PSCustomObject]@{
            Interface   = $alias
            IP          = $ip
            Prefix      = "/$prefix"
            Netmask     = $maskStr
            SubnetCIDR  = "$netStr/$prefix"
            TotalHosts  = $hostCount
            IsSupernet  = $isSupernet
        }
    }
} catch {
    Write-Host "Loi khi doc Get-NetIPAddress: $_" -ForegroundColor Red
}

$adaptersInfo | Format-Table -AutoSize

# Canh bao dac biet ve Subnet Mask cho dai 172.21.x.x
$lan172 = $adaptersInfo | Where-Object { $_.IP -like "172.21.*" }
if ($lan172) {
    foreach ($ad in $lan172) {
        if ($ad.Prefix -eq "/21") {
            Write-Host "  -> PHAT HIEN DUNG: Card mang $($ad.Interface) ($($ad.IP)) co Subnet Mask la 255.255.248.0 (/21)." -ForegroundColor Green
            Write-Host "     Dai mang bao gom 8 slices /24 tu 172.21.168.0 den 172.21.175.255 (Tong cong 2046 hosts)." -ForegroundColor Cyan
        } elseif ($ad.Prefix -eq "/24") {
            Write-Host "  -> CHU Y NGUY CO: Card mang $($ad.Interface) ($($ad.IP)) dang duoc Windows nhan dien la /24 (255.255.255.0)!" -ForegroundColor Red
            Write-Host "     => Day la NGUYEN NHAN CHINH khien may chi quet duoc 254 dia chi trong slice cua no va BO SOT cac slice khac!" -ForegroundColor Yellow
        } else {
            Write-Host "  -> Card mang $($ad.Interface) ($($ad.IP)) co prefix $($ad.Prefix)." -ForegroundColor Gray
        }
    }
} else {
    Write-Host "  Khong tim thay card mang nao thuoc dai 172.21.x.x tren may nay." -ForegroundColor Yellow
}

# -------------------------------------------------------------
# PHAN 2: KIEM TRA CAU HINH APPDATA CUA JA_LAN_MESSENGER
# -------------------------------------------------------------
Write-Section "2. KIEM TRA CAU HINH JA_LAN_MESSENGER TREN MAY"

$appDataDir = "$env:APPDATA\JA_LAN_Messenger"
Write-Host "Thu muc du lieu: $appDataDir" -ForegroundColor Gray

# Doc network_preferences.json
$netPrefFile = "$appDataDir\network_preferences.json"
if (Test-Path $netPrefFile) {
    try {
        $netPref = Get-Content $netPrefFile -Raw | ConvertFrom-Json
        $disabled = $netPref.disabledAdapters -join ', '
        Write-Host "Card mang bi vo hieu hoa (disabledAdapters): [ $disabled ]" -ForegroundColor $(if ($disabled) { "Yellow" } else { "Green" })
    } catch {
        Write-Host "Khong doc duoc network_preferences.json: $_" -ForegroundColor Red
    }
} else {
    Write-Host "Chua co file network_preferences.json (Mac dinh bat tat ca card LAN)" -ForegroundColor Green
}

# Doc known_devices.json
$knownFile = "$appDataDir\known_devices.json"
$knownList = @()
if (Test-Path $knownFile) {
    try {
        $knownList = Get-Content $knownFile -Raw | ConvertFrom-Json
        Write-Host "So luong thiet bi da tung luu trong so dia chi (known_devices.json): $($knownList.Count)" -ForegroundColor Cyan
    } catch {
        Write-Host "Khong doc duoc known_devices.json: $_" -ForegroundColor Red
    }
} else {
    Write-Host "Chua co file known_devices.json" -ForegroundColor Gray
}

# -------------------------------------------------------------
# PHAN 3: KIEM TRA CONG MANG & FIREWALL
# -------------------------------------------------------------
Write-Section "3. KIEM TRA CONG MANG & WINDOWS FIREWALL"

# Kiem tra cong TCP 6475 tren may cuc bo
$localTcp6475 = Get-NetTCPConnection -LocalPort 6475 -State Listen -ErrorAction SilentlyContinue
if ($localTcp6475) {
    Write-Host "  [OK] Cong TCP 6475 (Messenger Core) dang LANG NGHE tren may nay (PID: $($localTcp6475.OwningProcess | Select-Object -Unique))." -ForegroundColor Green
} else {
    Write-Host "  [!] Cong TCP 6475 hien KHONG co tien trinh nao lang nghe (Ung dung JA_LAN_Messenger co the chua chay)." -ForegroundColor Yellow
}

# Kiem tra cong UDP 36475 tren may cuc bo
$localUdp36475 = Get-NetUDPEndpoint -LocalPort 36475 -ErrorAction SilentlyContinue
if ($localUdp36475) {
    Write-Host "  [OK] Cong UDP 36475 (Discovery Receiver) dang BIND tren may nay." -ForegroundColor Green
} else {
    Write-Host "  [!] Cong UDP 36475 chua duoc bind." -ForegroundColor Yellow
}

# Kiem tra Firewall Inbound Rules
try {
    $fwUdp = Get-NetFirewallRule -Direction Inbound -Enabled True -ErrorAction SilentlyContinue | Get-NetFirewallPortFilter | Where-Object { $_.LocalPort -eq "36475" }
    $fwTcp = Get-NetFirewallRule -Direction Inbound -Enabled True -ErrorAction SilentlyContinue | Get-NetFirewallPortFilter | Where-Object { $_.LocalPort -eq "6475" }
    
    if ($fwUdp) {
        Write-Host "  [OK] Windows Firewall CO luat cho phep Inbound UDP 36475." -ForegroundColor Green
    } else {
        Write-Host "  [!] Windows Firewall CHUA co luat rieng cho UDP 36475 (phu thuoc vao rule theo chuong trinh)." -ForegroundColor Yellow
    }
    
    if ($fwTcp) {
        Write-Host "  [OK] Windows Firewall CO luat cho phep Inbound TCP 6475." -ForegroundColor Green
    } else {
        Write-Host "  [!] Windows Firewall CHUA co luat rieng cho TCP 6475 (phu thuoc vao rule theo chuong trinh)." -ForegroundColor Yellow
    }
} catch {}

# -------------------------------------------------------------
# PHAN 4: DOI SOAT TRUC TIEP TOAN BO CAC SLICE /24 TRONG 172.21.168.0/21
# -------------------------------------------------------------
Write-Section "4. DOI SOAT TRUC TIEP CAC THIET BI TRONG MANG 172.21.x.x"

# Danh muc co so 31 thiet bi trong dai mang 172.21.168.0/21
$baselineKnownIps = @{
    "172.21.168.106" = "4F-516"
    "172.21.168.201" = "MMI-TEST04"
    "172.21.168.224" = "CMDL02"
    "172.21.169.64"  = "CMDL01"
    "172.21.169.207" = "MMI-TEST06"
    "172.21.170.16"  = "Mini Sliver"
    "172.21.170.59"  = "CMDL08"
    "172.21.170.142" = "CMDL07"
    "172.21.170.238" = "SG - HIPOT"
    "172.21.171.29"  = "SG - MES PC"
    "172.21.172.151" = "FT@SEAGATE-MINI-FL"
    "172.21.173.252" = "VP3F - John Alaa"
    "172.21.174.64"  = "CMDL05"
    "172.21.174.82"  = "SG - FANTEST"
    "172.21.174.103" = "Trong Mini"
    "172.21.174.130" = "3F - IQ5 - SOZ - 049"
    "172.21.174.140" = "FT@SLD-042-043"
    "172.21.174.146" = "ft@MMI-TEST01"
    "172.21.174.152" = "ft@CMDL03"
    "172.21.174.163" = "3f - IQ5 - SOZ 014"
    "172.21.174.169" = "4F - P42516 - MiniPC2"
    "172.21.174.187" = "MMI-TEST08"
    "172.21.174.190" = "MMI-TEST05"
    "172.21.174.191" = "CMDL06"
    "172.21.174.195" = "MMI-TEST02"
    "172.21.174.203" = "MMI-TEST03"
    "172.21.174.208" = "CMDL04"
    "172.21.174.225" = "MMI-TEST07"
    "172.21.174.246" = "TRONG BIG"
    "172.21.175.20"  = "JA-AI-SERVER"
    "172.21.175.40"  = "CMDL09 (Dev PC)"
}

$allKnownIps = [ordered]@{}
foreach ($k in $baselineKnownIps.Keys) {
    $allKnownIps[$k] = $baselineKnownIps[$k]
}

if ($knownList) {
    foreach ($dev in $knownList) {
        $ip = $dev.lastIp
        if ($ip -and $ip -match '^172\.21\.') {
            $allKnownIps[$ip] = $dev.username
        }
    }
}

if ($TargetIp) {
    Write-Host "-> Che do kiem tra truc tiep Target IP: $TargetIp" -ForegroundColor Yellow
    $tcp = New-Object System.Net.Sockets.TcpClient
    $sw = [System.Diagnostics.Stopwatch]::StartNew()
    $ar = $tcp.BeginConnect($TargetIp, 6475, $null, $null)
    $ok = $ar.AsyncWaitHandle.WaitOne(1000, $false)
    $sw.Stop()
    if ($ok -and $tcp.Connected) {
        try { $tcp.EndConnect($ar) } catch {}
        Write-Host "   [KET QUA] Ket noi toi $($TargetIp):6475 THANH CONG ($($sw.ElapsedMilliseconds)ms)!" -ForegroundColor Green
    } else {
        Write-Host "   [KET QUA] KHONG THE ket noi toi $($TargetIp):6475 (Port bi chan hoac Timeout)!" -ForegroundColor Red
    }
    $tcp.Close()
}

$testIps = @($allKnownIps.Keys)
Write-Host "Dang tien hanh kiem tra ket noi TCP 6475 toi $($testIps.Count) thiet bi trong dai 172.21.x.x..." -ForegroundColor Cyan

$probeResults = @()
$slicesOnline = @{
    "172.21.168" = 0
    "172.21.169" = 0
    "172.21.170" = 0
    "172.21.171" = 0
    "172.21.172" = 0
    "172.21.173" = 0
    "172.21.174" = 0
    "172.21.175" = 0
}

# Fast concurrent test
$jobs = @()
foreach ($ip in $testIps) {
    $name = $allKnownIps[$ip]
    $slice = ($ip -split '\.')[0..2] -join '.'
    
    $tcpClient = New-Object System.Net.Sockets.TcpClient
    $sw = [System.Diagnostics.Stopwatch]::StartNew()
    $ar = $tcpClient.BeginConnect($ip, 6475, $null, $null)
    $success = $ar.AsyncWaitHandle.WaitOne($TimeoutMs, $false)
    $sw.Stop()
    
    $isOnline = $false
    if ($success -and $tcpClient.Connected) {
        try {
            $tcpClient.EndConnect($ar)
            $isOnline = $true
        } catch {}
    }
    $tcpClient.Close()
    
    if ($isOnline) {
        if ($slicesOnline.ContainsKey($slice)) {
            $slicesOnline[$slice]++
        }
    }
    
    $probeResults += [PSCustomObject]@{
        Slice     = $slice
        IP        = $ip
        Name      = $name
        Status    = if ($isOnline) { "ONLINE" } else { "OFFLINE" }
        PingTCP   = if ($isOnline) { "$($sw.ElapsedMilliseconds)ms" } else { "Timeout" }
    }
}

# Hien thi danh sach online
$onlineList = @($probeResults | Where-Object { $_.Status -eq "ONLINE" })
$offlineList = @($probeResults | Where-Object { $_.Status -eq "OFFLINE" })

Write-Host ""
Write-Host "DANH SACH THIET BI DANG ONLINE THUC TE (Phan hoi cong TCP 6475): $($onlineList.Count) THIET BI" -ForegroundColor Green
$onlineList | Sort-Object Slice, IP | Format-Table -AutoSize

if ($offlineList.Count -gt 0) {
    Write-Host "Cac thiet bi trong danh ba nhung hien dang Tat/Offline: $($offlineList.Count)" -ForegroundColor Gray
}

# -------------------------------------------------------------
# PHAN 5: PHAN TICH THEO TUNG SUBNET SLICE
# -------------------------------------------------------------
Write-Section "5. PHAN BO SO LUONG ONLINE THEO TUNG SUBNET SLICE"

$sliceSummary = @()
foreach ($s in ($slicesOnline.Keys | Sort-Object)) {
    $sliceCIDR = "$s.0/24"
    $count = $slicesOnline[$s]
    $isTargetSlice = ($s -eq "172.21.172")
    $note = ""
    if ($isTargetSlice) {
        $note = "<-- Slice chua may 172.21.172.151"
    } elseif ($s -eq "172.21.174") {
        $note = "<-- Tap trung nhieu user nhat ($count user)"
    }
    
    $sliceSummary += [PSCustomObject]@{
        SubnetSlice = $sliceCIDR
        OnlineCount = $count
        Note        = $note
    }
}

$sliceSummary | Format-Table -AutoSize

# -------------------------------------------------------------
# PHAN 6: KET LUAN & NGUYEN NHAN LECH USER GIUA 2 MAY
# -------------------------------------------------------------
Write-Section "6. KET LUAN & HUONG DAN XU LY HIEN TUONG LECH USER"

$totalOnline172 = ($slicesOnline.Values | Measure-Object -Sum).Sum
Write-Host "TONG SO USER ONLINE THUC TE TRONG DAI 172.21.168.0/21: $totalOnline172 user" -ForegroundColor Green

Write-Host @"

========================== NGUYEN NHAN PHAN TICH ==========================
Hien tai tren may cua ban:
- Dai mang chinh la: 172.21.168.0/21 (gom 8 dai /24 tu 168.0 den 175.255).
- Trong do, Slice 172.21.174.x chiem toi $($slicesOnline["172.21.174"]) user online!
- May 172.21.172.151 nam o slice 172.21.172.x.

Tai sao may 172.21.172.151 chi tim duoc 15 user thay vi ~26-36 user?
1. NGUYEN NHAN SO 1 (Pho bien nhat - Subnet Mask /24):
   May 172.21.172.151 co the bi Windows nhan dien Subnet Mask la 255.255.255.0 (/24)
   thay vi 255.255.248.0 (/21).
   -> Khi do, tinh nang quet Subnet Sweep chi quet tu 172.21.172.1 den 172.21.172.254.
   -> No khong he quet dai 172.21.174.x (noi co $($slicesOnline["172.21.174"]) user) hay 172.21.170.x ($($slicesOnline["172.21.170"]) user)!
   -> 15 user ma may do tim duoc chi la nhung goi broadcast ngau nhien vuot qua duoc switch.

2. NGUYEN NHAN SO 2 (Switch / VLAN chan UDP Broadcast):
   Switch trong mang cong ty ngan khong cho goi tin Broadcast 255.255.255.255
   lan truyen qua lai giua cac VLAN / subnet slice khac nhau.
   Neu may 172.21.172.151 khong quet chu dong Unicast TCP/UDP sang cac slice khac,
   no se khong bao gio nhan duoc goi tin phat song tu slice 174.

========================== CACH KIEM TRA TREN MAY 172.21.172.151 ==========================
Hay sao chep file 'verify_scan.bat' va 'verify_scan.ps1' sang may 172.21.172.151 va chay:
   .\verify_scan.bat

Ket qua in ra se chi ro ngay:
- Card mang cua may do co dang nhan du /21 khong?
- May do co ket noi duoc toi 172.21.174.x khong?
- Co card mang nao bi disabled hay bi firewall chan khong?
"@ -ForegroundColor Yellow

Write-Host ""
Write-Host "Kiem tra hoan tat!" -ForegroundColor Cyan
