TAG=v1.3.1
TITLE=JA LAN Messenger v1.3.1 — Fast Netsh Subnet Detection, Circular Translucent Avatars & Group Permissions
BODY=
## JA LAN Messenger v1.3.1 — Fast Netsh Subnet Detection, Circular Translucent Avatars & Group Permissions

- **Tăng tốc & Ổn định hóa Nhận diện Subnet Mask (`netsh`)**: Chuyển đổi truy vấn Subnet Mask từ PowerShell sang lệnh native `netsh interface ipv4 show addresses`, giảm thời gian xuống ~5ms, không bị ảnh hưởng bởi chính sách bảo mật PowerShell hay độ trễ khởi động của Mini PC. Nhận diện hoàn hảo dải Supernet /21 (255.255.248.0) và quét đủ 2046 hosts trên toàn bộ 8 dải con.
- **Bộ công cụ Kiểm tra & Chẩn đoán Mạng Độc lập (`verify_scan.bat` & `verify_scan.ps1`)**: Cung cấp công cụ chạy 1-click độc lập, tự động chẩn đoán cấu hình card mạng, Subnet Mask, cổng tường lửa (TCP 6475, UDP 36475) và đo đạc kết nối thời gian thực tới toàn bộ các subnet slice.
- **Phân quyền Quản trị Nhóm chuẩn Zalo/Telegram**: Chỉ Trưởng nhóm (Creator/Admin) mới có quyền giải tán nhóm chat; thành viên thông thường chỉ có tùy chọn rời nhóm, ngăn chặn việc thành viên thường vô tình xóa nhóm chung.
- **Khôi phục Kiểu dáng Avatar Tròn Mặc định & Màu Nền Mờ**: Đưa `isCircle: true` làm mặc định trên toàn bộ ứng dụng; khôi phục màu nền mờ `avatarColor.withValues(alpha: 0.2)` kèm viền màu đồng bộ và chữ cái đầu (Initials) / preset icon trang nhã.
- **Đồng bộ Avatar Danh bạ & Cố định Ảnh Đại diện JA AI**: Sử dụng `AppAvatar` thống nhất cho toàn bộ danh bạ; cố định ảnh gốc `assets/ai_avatar.png` trong khung trò chuyện JA AI.
- **Đồng bộ toàn diện phiên bản**: Cập nhật `v1.3.1+7` vào toàn bộ mã nguồn, metadata Windows Runner, tài liệu hướng dẫn và bộ cài đặt.

### Cài đặt
Chạy file `install.bat` để cài đặt ứng dụng vào Windows (có shortcut Desktop & Start Menu, đăng ký Control Panel), hoặc chạy trực tiếp `ja_lan_messenger.exe` để sử dụng dạng portable. Xem file `USERGUIDE.md` đính kèm để biết thêm chi tiết.
