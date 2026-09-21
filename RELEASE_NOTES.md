TAG=v1.2.2
TITLE=JA LAN Messenger v1.2.2 — OTA Parameter Formatting Fix & Locale Stability
BODY=
## JA LAN Messenger v1.2.2 — OTA Parameter Formatting Fix & Locale Stability

- **Định dạng tham số thông báo cập nhật OTA (Toast & Badge Tooltip)**: Khắc phục triệt để lỗi hiển thị chuỗi `%s` chưa được thay thế trong thông báo Toast và Tooltip huy hiệu OTA trên thanh tiêu đề khi có bản cập nhật mới (`updateAvailable`). Chuẩn hóa tiền tố phiên bản `v` đồng nhất trên cả 3 ngôn ngữ (Tiếng Việt, English, 简体中文).
- **Kiểm thử tự động & Nghiệm thu kỹ thuật**: Bổ sung kiểm thử tự động chuỗi nội suy `%s` và cập nhật biên bản kỹ thuật `docs/AI_HANDOFF.md`.
- **Đồng bộ toàn diện phiên bản**: Cập nhật `v1.2.2+5` vào toàn bộ mã nguồn, metadata Windows Runner, tài liệu hướng dẫn và bộ cài đặt.

### Cài đặt
Chạy file `install.bat` để cài đặt ứng dụng vào Windows (có shortcut Desktop & Start Menu, đăng ký Control Panel), hoặc chạy trực tiếp `ja_lan_messenger.exe` để sử dụng dạng portable. Xem file `USERGUIDE.md` đính kèm để biết thêm chi tiết.
