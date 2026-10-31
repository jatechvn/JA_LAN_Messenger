TAG=v1.12.0
TITLE=JA LAN Messenger v1.12.0 — Automatic OTA Update Popup & Instant Peer Presence Recovery
BODY=
## JA LAN Messenger v1.12.0 — Automatic OTA Update Popup & Instant Peer Presence Recovery

- **Tự động Hiện Popup Thông báo Phiên bản Mới (`GlassUpdateDialog`)**:
  - Tự động bật hộp thoại cập nhật `GlassUpdateDialog` ngay khi phát hiện phiên bản mới trên máy chủ LAN hoặc GitHub Releases (kèm huy hiệu thông báo trên cả giao diện Chuẩn và Compact Mode).
  - Tự động kiểm tra bản cập nhật mới ngay khi khởi động ứng dụng (`isStartup: true`) và định kỳ mỗi 30 phút chạy nền, đi kèm khóa chống mở chồng hộp thoại (`isGlassUpdateDialogShowing`).
- **Khôi phục Trạng thái Online Tức thì Sau Khi Tắt/Mở Lại Ứng dụng**:
  - Sửa triệt để lỗi ~50% đồng nghiệp đang Online bị báo Offline khi tắt/mở lại App phải bấm Chuông (Buzz) mới nhận lại: phân biệt chính xác kết nối lại sau khi khởi động lại App (`session_replaced`) với kết nối mở đồng thời (`simultaneous open`) trong `LanTcpServer._attach`.
  - Chủ động thăm dò TCP trực tiếp (`_probeKnownAndRestoredPeers`) tới danh bạ đã biết ngay khi khởi động và khi quét mạng; bảo toàn trạng thái Online khi nạp lịch sử (`_consolidateLoadedPeersAndConversations`); phát thông báo `Offline` tức thì khi đóng ứng dụng và giảm rate-limit phản hồi UDP Unicast xuống 2 giây.
- **Củng cố Chính sách Card Mạng (NIC Policy) & Đa Tài khoản Cùng IP**:
  - Bảo toàn các phiên độc lập trên những cổng khác nhau cùng một địa chỉ IP, thực thi chính sách lọc Card mạng trên toàn bộ luồng kết nối TCP, và truyền trực tiếp gói tin `UserStatus` khi đổi trạng thái mà không ngắt kết nối hiện tại.
- **Đồng bộ Toàn diện Phiên bản**: Cập nhật `v1.12.0+22` vào toàn bộ mã nguồn, metadata Windows Runner, tài liệu hướng dẫn và bộ cài đặt.

### Cài đặt
Chạy file `install.bat` để cài đặt ứng dụng vào Windows (có shortcut Desktop & Start Menu, đăng ký Control Panel), hoặc chạy trực tiếp `ja_lan_messenger.exe` để sử dụng dạng portable. Xem file `USERGUIDE.md` đính kèm để biết thêm chi tiết.
