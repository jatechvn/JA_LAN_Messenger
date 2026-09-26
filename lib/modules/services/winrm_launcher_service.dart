import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'windows_secret.dart';

/// Kết quả thực thi lệnh WinRM
class WinrmExecutionResult {
  final bool success;
  final String message;
  final String? rawOutput;
  final int? exitCode;

  const WinrmExecutionResult({
    required this.success,
    required this.message,
    this.rawOutput,
    this.exitCode,
  });

  @override
  String toString() =>
      'WinrmExecutionResult(success: $success, message: $message, exitCode: $exitCode)';
}

/// Dịch vụ quản lý và gửi lệnh khởi động ứng dụng từ xa qua WinRM trên Windows
class WinrmLauncherService {
  final Future<ProcessResult> Function(
    String executable,
    List<String> arguments,
  )?
  processRunner;

  const WinrmLauncherService({this.processRunner});

  static String _passwordExpression(String password) {
    final bytes = Uint8List.fromList(utf8.encode(password));
    if (!Platform.isWindows) {
      return "[System.Text.Encoding]::UTF8.GetString([System.Convert]::FromBase64String('${base64.encode(bytes)}'))";
    }
    final blob = WindowsSecret.transform(bytes, protect: true);
    return "[System.Text.Encoding]::UTF8.GetString([System.Security.Cryptography.ProtectedData]::Unprotect([System.Convert]::FromBase64String('${base64.encode(blob)}'), \$null, [System.Security.Cryptography.DataProtectionScope]::CurrentUser))";
  }

  /// Chuyển đổi chuỗi script PowerShell sang định dạng UTF-16LE Base64 (-EncodedCommand)
  /// để tránh mọi lỗi escaping ký tự đặc biệt trong mật khẩu hoặc đường dẫn
  static String encodePowerShellCommand(String script) {
    final units = <int>[];
    for (final codeUnit in script.codeUnits) {
      units.add(codeUnit & 0xFF);
      units.add((codeUnit >> 8) & 0xFF);
    }
    return base64.encode(units);
  }

  /// Thực thi một script PowerShell bất đồng bộ qua file tạm an toàn để tránh lộ tham số/mật khẩu trên command line
  Future<ProcessResult> _runPowerShell(
    String script, {
    Duration timeout = const Duration(seconds: 15),
  }) async {
    Directory? tempDir;
    File? tempFile;
    Process? process;

    try {
      tempDir = await Directory.systemTemp.createTemp('ja_winrm_');
      tempFile = File('${tempDir.path}\\exec.ps1');
      // BOM is necessary for non-ASCII source on Windows PowerShell 5.1.
      await tempFile.writeAsString('\uFEFF$script', flush: true);

      final args = [
        '-NoProfile',
        '-NonInteractive',
        '-ExecutionPolicy',
        'Bypass',
        '-File',
        tempFile.path,
      ];

      if (processRunner != null) {
        try {
          final future =
              (processRunner
                  is Future<ProcessResult> Function(
                    String,
                    List<String>, {
                    String? stdinScript,
                  }))
              ? (processRunner as dynamic)(
                  'powershell.exe',
                  args,
                  stdinScript: script,
                )
              : (processRunner as dynamic)('powershell.exe', args);
          return await (future as Future<ProcessResult>).timeout(
            timeout,
            onTimeout: () => ProcessResult(
              -1,
              -1,
              '',
              'Timeout: Lệnh WinRM đã vượt quá thời gian chờ ($timeout)',
            ),
          );
        } catch (e) {
          if (e is TimeoutException) {
            return ProcessResult(
              -1,
              -1,
              '',
              'Timeout: Lệnh WinRM đã vượt quá thời gian chờ ($timeout)',
            );
          }
          rethrow;
        }
      }

      process = await Process.start('powershell.exe', args);

      final results = await Future.wait<Object>([
        process.exitCode,
        process.stdout
            .transform(const Utf8Decoder(allowMalformed: true))
            .join(),
        process.stderr
            .transform(const Utf8Decoder(allowMalformed: true))
            .join(),
      ]).timeout(timeout);
      return ProcessResult(
        process.pid,
        results[0] as int,
        results[1],
        results[2],
      );
    } on TimeoutException {
      try {
        process?.kill(ProcessSignal.sigkill);
        await process?.exitCode.timeout(const Duration(seconds: 2));
      } catch (_) {}
      return ProcessResult(
        process?.pid ?? -1,
        -1,
        '',
        'Timeout: Lệnh WinRM đã vượt quá thời gian chờ ($timeout)',
      );
    } catch (e) {
      try {
        process?.kill(ProcessSignal.sigkill);
      } catch (_) {}
      return ProcessResult(-1, -1, '', 'Lỗi khởi chạy tiến trình: $e');
    } finally {
      if (tempDir != null) {
        try {
          if (await tempDir.exists()) {
            await tempDir.delete(recursive: true);
          }
        } catch (_) {}
      }
    }
  }

  /// Kiểm tra kết nối và đăng nhập WinRM tới máy đích
  Future<WinrmExecutionResult> testConnection({
    required String ip,
    required int port,
    required String username,
    required String password,
    Duration timeout = const Duration(seconds: 12),
  }) async {
    if (ip.trim().isEmpty) {
      return const WinrmExecutionResult(
        success: false,
        message: 'Địa chỉ IP máy đích không được để trống.',
      );
    }
    if (username.trim().isEmpty) {
      return const WinrmExecutionResult(
        success: false,
        message: 'Tài khoản WinRM không được để trống.',
      );
    }

    final b64Target = base64.encode(utf8.encode(ip.trim()));
    final b64User = base64.encode(utf8.encode(username.trim()));
    final passwordExpression = _passwordExpression(password);

    final script =
        '''
\$target = [System.Text.Encoding]::UTF8.GetString([System.Convert]::FromBase64String('$b64Target'))
\$user = [System.Text.Encoding]::UTF8.GetString([System.Convert]::FromBase64String('$b64User'))
\$port = $port

Add-Type -AssemblyName System.Security
\$secPass = [System.Net.NetworkCredential]::new('', ($passwordExpression)).SecurePassword
\$cred = New-Object System.Management.Automation.PSCredential (\$user, \$secPass)
\$sessionOpt = New-PSSessionOption -SkipCACheck -SkipCNCheck -SkipRevocationCheck

try {
    \$result = Invoke-Command -ComputerName \$target -Port \$port -Credential \$cred -SessionOption \$sessionOpt -ScriptBlock {
        return "PONG:" + [Environment]::MachineName + ":" + [Environment]::UserName
    } -ErrorAction Stop
    Write-Output "WINRM_TEST_OK:\$result"
} catch {
    Write-Error \$_
    exit 1
}
''';

    try {
      final res = await _runPowerShell(script, timeout: timeout);
      final out = '${res.stdout}'.trim();
      final err = '${res.stderr}'.trim();

      if (res.exitCode == 0 && out.contains('WINRM_TEST_OK')) {
        final details = out.replaceFirst('WINRM_TEST_OK:', '').trim();
        return WinrmExecutionResult(
          success: true,
          message: 'Kết nối WinRM thành công ($details)',
          rawOutput: out,
          exitCode: res.exitCode,
        );
      } else {
        final combinedErr = err.isNotEmpty ? err : out;
        return WinrmExecutionResult(
          success: false,
          message: _humanizeErrorMessage(combinedErr),
          rawOutput: combinedErr,
          exitCode: res.exitCode,
        );
      }
    } catch (e) {
      return WinrmExecutionResult(
        success: false,
        message: 'Lỗi thực thi WinRM: $e',
      );
    }
  }

  /// Gửi lệnh khởi động ứng dụng JA LAN Messenger từ xa trên máy đích
  Future<WinrmExecutionResult> launchRemoteApp({
    required String ip,
    required int port,
    required String username,
    required String password,
    String? customAppPath,
    Duration timeout = const Duration(seconds: 18),
  }) async {
    if (ip.trim().isEmpty) {
      return const WinrmExecutionResult(
        success: false,
        message: 'Địa chỉ IP máy đích không hợp lệ.',
      );
    }
    if (username.trim().isEmpty) {
      return const WinrmExecutionResult(
        success: false,
        message: 'Tài khoản WinRM chưa được thiết lập.',
      );
    }

    final b64Target = base64.encode(utf8.encode(ip.trim()));
    final b64User = base64.encode(utf8.encode(username.trim()));
    final passwordExpression = _passwordExpression(password);
    final b64CustomPath = base64.encode(
      utf8.encode(customAppPath?.trim() ?? ''),
    );

    final script =
        '''
\$target = [System.Text.Encoding]::UTF8.GetString([System.Convert]::FromBase64String('$b64Target'))
\$user = [System.Text.Encoding]::UTF8.GetString([System.Convert]::FromBase64String('$b64User'))
\$port = $port
\$customPath = [System.Text.Encoding]::UTF8.GetString([System.Convert]::FromBase64String('$b64CustomPath'))

Add-Type -AssemblyName System.Security
\$secPass = [System.Net.NetworkCredential]::new('', ($passwordExpression)).SecurePassword
\$cred = New-Object System.Management.Automation.PSCredential (\$user, \$secPass)
\$sessionOpt = New-PSSessionOption -SkipCACheck -SkipCNCheck -SkipRevocationCheck

try {
    \$result = Invoke-Command -ComputerName \$target -Port \$port -Credential \$cred -SessionOption \$sessionOpt -ScriptBlock {
        param(\$customExe)

        # 1. Kiểm tra xem ứng dụng đã đang chạy trong phiên tương tác (SessionId > 0) chưa
        \$interactiveProcs = @(Get-Process ja_lan_messenger -ErrorAction SilentlyContinue | Where-Object { \$_.SessionId -gt 0 })
        if (\$interactiveProcs.Count -gt 0) {
            return "ALREADY_RUNNING"
        }

        # Danh sách các đường dẫn ứng dụng khả thi
        \$paths = @(
            \$customExe,
            "\$env:LOCALAPPDATA\\Programs\\JA_LAN_Messenger\\ja_lan_messenger.exe",
            "C:\\Program Files\\JA_LAN_Messenger\\ja_lan_messenger.exe",
            "\$env:ProgramFiles\\JA_LAN_Messenger\\ja_lan_messenger.exe",
            (Get-ItemProperty 'HKCU:\\Software\\Microsoft\\Windows\\CurrentVersion\\Uninstall\\JA_LAN_Messenger' -ErrorAction SilentlyContinue).InstallLocation + '\\ja_lan_messenger.exe'
        )

        \$exe = \$paths | Where-Object { \$_ -and (Test-Path \$_) } | Select-Object -First 1

        if (-not \$exe) {
            throw "NOT_FOUND: Không tìm thấy file ja_lan_messenger.exe trên máy đích."
        }

        # Thử khởi động vào Desktop tương tác của người dùng qua Scheduled Task (/IT)
        \$tn = 'JA_LAN_Wakeup_' + (Get-Random)
        \$taskCreated = \$false
        try {
            \$taskCreateOut = schtasks /create /tn \$tn /tr "`"\$exe`"" /sc once /st 00:00 /it /f 2>&1
            if (\$LASTEXITCODE -eq 0) {
                \$taskCreated = \$true
                schtasks /run /tn \$tn 2>&1 | Out-Null
            }
        } catch {}

        # Chờ tối đa 3 giây xem tiến trình có xuất hiện trong phiên tương tác (SessionId > 0) không
        \$started = \$false
        for (\$i = 0; \$i -lt 15; \$i++) {
            Start-Sleep -Milliseconds 200
            if (Get-Process ja_lan_messenger -ErrorAction SilentlyContinue | Where-Object { \$_.SessionId -gt 0 }) {
                \$started = \$true
                break
            }
        }

        # Dọn dẹp task nếu đã tạo
        if (\$taskCreated) {
            try { schtasks /delete /tn \$tn /f 2>&1 | Out-Null } catch {}
        }

        # Nếu chưa thấy tiến trình chạy, thử fallback bằng Start-Process
        if (-not \$started) {
            try {
                Start-Process -FilePath \$exe -WindowStyle Normal -ErrorAction SilentlyContinue
                for (\$i = 0; \$i -lt 10; \$i++) {
                    Start-Sleep -Milliseconds 200
                    if (Get-Process ja_lan_messenger -ErrorAction SilentlyContinue | Where-Object { \$_.SessionId -gt 0 }) {
                        \$started = \$true
                        break
                    }
                }
            } catch {}
        }

        # Kiểm tra xác nhận cuối cùng: phải có tiến trình thực sự chạy trong phiên tương tác (SessionId > 0)
        if (Get-Process ja_lan_messenger -ErrorAction SilentlyContinue | Where-Object { \$_.SessionId -gt 0 }) {
            return "LAUNCH_SUCCESS:" + \$exe
        } else {
            throw "LAUNCH_FAILED: Đã gửi lệnh khởi động nhưng không tìm thấy tiến trình ja_lan_messenger chạy trong phiên tương tác người dùng."
        }
    } -ArgumentList \$customPath -ErrorAction Stop

    Write-Output "WINRM_EXEC_OK:\$result"
} catch {
    Write-Error \$_
    exit 1
}
''';

    try {
      final res = await _runPowerShell(script, timeout: timeout);
      final out = '${res.stdout}'.trim();
      final err = '${res.stderr}'.trim();

      if (res.exitCode == 0 && out.contains('WINRM_EXEC_OK')) {
        if (out.contains('ALREADY_RUNNING')) {
          return WinrmExecutionResult(
            success: true,
            message: 'Ứng dụng đã đang chạy trên máy đích.',
            rawOutput: out,
            exitCode: res.exitCode,
          );
        }
        return WinrmExecutionResult(
          success: true,
          message: 'Đã gửi lệnh mở ứng dụng thành công.',
          rawOutput: out,
          exitCode: res.exitCode,
        );
      } else {
        final combinedErr = err.isNotEmpty ? err : out;
        return WinrmExecutionResult(
          success: false,
          message: _humanizeErrorMessage(combinedErr),
          rawOutput: combinedErr,
          exitCode: res.exitCode,
        );
      }
    } catch (e) {
      return WinrmExecutionResult(
        success: false,
        message: 'Lỗi thực thi WinRM: $e',
      );
    }
  }

  /// Diễn giải lỗi WinRM thường gặp sang thông báo thân thiện với người dùng
  static String _humanizeErrorMessage(String error) {
    if (error.trim().isEmpty) {
      return 'Không nhận được phản hồi từ dịch vụ WinRM máy đích.';
    }
    final lower = error.toLowerCase();
    if (lower.contains('access is denied') ||
        lower.contains('unauthorized') ||
        lower.contains('logon failure') ||
        lower.contains('credentials')) {
      return 'Xác thực thất bại: Sai tên đăng nhập hoặc mật khẩu WinRM.';
    }
    if (lower.contains('cannot connect to the destination') ||
        lower.contains('10060') ||
        lower.contains('10061') ||
        lower.contains('connection timed out')) {
      return 'Không thể kết nối tới dịch vụ WinRM trên máy đích (Port bị chặn hoặc dịch vụ chưa bật).';
    }
    if (lower.contains('trustedhosts')) {
      return 'Lỗi TrustedHosts: Cần cấu hình TrustedHosts trên máy gửi hoặc máy nhận.';
    }
    if (lower.contains('not_found')) {
      return 'Không tìm thấy file ja_lan_messenger.exe trong thư mục cài đặt trên máy đích.';
    }
    if (lower.contains('launch_failed')) {
      return 'Không thể khởi động ứng dụng trên máy đích (tiến trình không phản hồi).';
    }
    if (lower.contains('timeout')) {
      return 'Quá thời gian chờ phản hồi từ máy đích.';
    }
    return error.length > 200 ? '${error.substring(0, 197)}...' : error;
  }
}
