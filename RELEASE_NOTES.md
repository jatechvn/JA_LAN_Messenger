TAG=v1.5.0
TITLE=JA LAN Messenger v1.5.0 — Remote WinRM App Launch from Buzz & Quick Selection OTA
BODY=
## JA LAN Messenger v1.5.0 — Remote WinRM App Launch from Buzz & Quick Selection OTA

- **Kích hoạt Ứng dụng từ xa qua WinRM khi Rung chuông (Remote WinRM App Launch on Buzz)**:
  - Khi đối phương đang offline (tắt ứng dụng hoặc chưa mở), nút Buzz (Rung chuông) tự động thực hiện kích hoạt ứng dụng trên máy đối phương thông qua Windows Remote Management (WinRM).
  - Tự động tạo phiên tương tác thực (`SessionId > 0`) trên desktop người dùng từ xa, tránh trường hợp mở nhầm tiến trình headless trong Session 0.
  - Sau khi WinRM mở app đối phương thành công, ngay khi máy đối phương hoàn tất khởi động và bắt tay mạng LAN, hệ thống tự động gửi rung chuông (`Auto-Buzz`) đến đúng người nhận.
  - **Tối ưu hóa Buzz khi đối phương Online**: Nếu đối phương đang online (hoặc thăm dò TCP port 6475 thành công ngay lập tức), hệ thống chỉ gửi rung chuông thông thường và không kích hoạt hay hiển thị thông báo WinRM không cần thiết.
- **Bảo mật Thông tin Đăng nhập WinRM bằng AES-256**:
  - Mã hóa mật khẩu lưu trữ an toàn bằng chuẩn **AES-256-CBC (`enc:v2:`)** kết hợp IV ngẫu nhiên và khóa liên kết thiết bị (`USERNAME`, `COMPUTERNAME`, `USERPROFILE`).
  - Hỗ trợ cấu hình WinRM mặc định toàn cục (`FT` / `123`) trong Cài đặt và cấu hình riêng lẻ cho từng người dùng qua hộp thoại hồ sơ liên hệ.
  - Cơ chế thực thi kịch bản an toàn qua file script tạm thời trong `%TEMP%` (`powershell.exe -File`), bảo vệ tuyệt đối mật khẩu và mã script khỏi việc bị lộ trong Command Line Arguments của Task Manager / Process Explorer.
- **Nút Chọn Nhanh Chu kỳ Cập nhật OTA (Quick Selection Chips)**:
  - Thay thế droplist chọn chu kỳ cập nhật bằng các **Nút chọn nhanh trực quan 1-chạm** (`Hàng ngày`, `Hàng tuần`, `Hàng tháng`, `Tắt`) kèm icon và highlight trạng thái đang chọn, giúp thao tác mượt mà và trực quan hơn.
- **Đồng bộ Múi giờ Bong bóng Chat (UTC to Local Time)**: Chuẩn hóa toàn bộ thời gian tin nhắn nhận qua giao thức BeeBEEP sang giờ địa phương máy tính (`.toLocal()`), khắc phục triệt để hiện tượng lệch giờ.
- **Ổn định Chấm Xanh Trạng thái Online/Offline**: Tối ưu hóa logic gộp danh bạ (`peers` deduplication) và đồng bộ trực tiếp trạng thái online vào đối tượng đang chọn, loại bỏ hoàn toàn hiện tượng chấm xanh bị nhấp nháy hoặc kẹt ở trạng thái offline khi có dữ liệu mạng mới.
- **Xác minh Thiết bị Chặt chẽ (`PendingBuzzTarget`)**: Đảm bảo yêu cầu rung chuông tự động chỉ gửi tới đúng máy tính đích, ngăn ngừa trường hợp nhầm lẫn khi địa chỉ IP bị DHCP cấp phát lại.
- **Đồng bộ toàn diện phiên bản**: Cập nhật `v1.5.0+10` vào toàn bộ mã nguồn, metadata Windows Runner, tài liệu hướng dẫn và bộ cài đặt.

### Cài đặt
Chạy file `install.bat` để cài đặt ứng dụng vào Windows (có shortcut Desktop & Start Menu, đăng ký Control Panel), hoặc chạy trực tiếp `ja_lan_messenger.exe` để sử dụng dạng portable. Xem file `USERGUIDE.md` đính kèm để biết thêm chi tiết.
