TAG=v1.13.0
TITLE=JA LAN Messenger v1.13.0 — IPv4:Port Bridge Support, Installer Directory Unlock & CLI Separation
BODY=
## JA LAN Messenger v1.13.0 — IPv4:Port Bridge Support, Installer Directory Unlock & CLI Separation

- **Hỗ trợ Điểm cuối IPv4:port (Bridge & Multi-Host)**: Cho phép nhập địa chỉ dạng `IPv4` hoặc `IPv4:cổng` (1–65535) trong hộp thoại Thêm bạn IP, hỗ trợ kết nối đồng thời nhiều máy trạm được bắc cầu qua loopback từ CLI bridge độc lập (`JA_LanMes_Cli`).
- **Mở khóa Thư mục Bộ cài đặt Tức thì (CWD Unlock)**: Tự động neo thư mục làm việc về thư mục chứa file thực thi và bàn giao tiến trình qua script độc lập, đảm bảo thư mục giải nén bộ cài đặt có thể xóa hoặc di chuyển ngay sau khi cài đặt.
- **Tách biệt Kiến trúc Python CLI**: Mã nguồn và bộ công cụ CLI được duy trì tại repository độc lập `JA_LanMes_Cli`, bộ cài và file nén GUI được tinh gọn tối đa.
- **Tối ưu hóa OTA Update**: Bỏ qua hậu tố build metadata khi so sánh phiên bản cập nhật và làm sạch định dạng release notes markdown.
- **Đồng bộ Toàn diện Phiên bản**: Cập nhật `v1.13.0+23` vào toàn bộ mã nguồn, metadata Windows Runner, tài liệu hướng dẫn và bộ cài đặt.

### Cài đặt
Chạy file `install.bat` để cài đặt ứng dụng vào Windows (có shortcut Desktop & Start Menu, đăng ký Control Panel), hoặc chạy trực tiếp `ja_lan_messenger.exe` để sử dụng dạng portable. Xem file `USERGUIDE.md` đính kèm để biết thêm chi tiết.
