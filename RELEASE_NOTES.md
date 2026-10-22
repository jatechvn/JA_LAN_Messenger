TAG=v1.11.0
TITLE=JA LAN Messenger v1.11.0 — Persistent Device Identity, DHCP IP Churn Protection & Hostname Auto-Recovery
BODY=
## JA LAN Messenger v1.11.0 — Persistent Device Identity, DHCP IP Churn Protection & Hostname Auto-Recovery

- **Nhận diện Định danh Bền vững khi Nhảy IP (DHCP IP Churn Protection)**:
  - Tự động nhận diện lại đồng nghiệp cũ theo định danh thiết bị (`account@hostname` hoặc `host@host`) khi họ online trở lại ở địa chỉ IP mới sau thời gian dài ngoại tuyến, giữ nguyên toàn bộ lịch sử trò chuyện, biệt danh và nhóm chat.
- **Thu hồi IP Cũ Tức thì & Cách ly Tuyệt đối Khi DHCP Cấp lại IP**:
  - Khi địa chỉ IP cũ của một máy đang offline được DHCP cấp cho người dùng khác, hệ thống lập tức thu hồi IP cũ đó khỏi liên hệ cũ (trong cả bộ nhớ RAM và `known_devices.json`), ngăn chặn hoàn toàn việc trộn lẫn cuộc trò chuyện, hàng đợi Outbox, tệp đính kèm hoặc gọi nhầm lệnh Buzz/WinRM.
- **Chủ động Dò tìm IP Mới qua Hostname (DNS / LLMNR / NetBIOS)**:
  - Khi gửi tin nhắn, bấm Thử lại hoặc gửi Rung chuông (Buzz) tới đồng nghiệp bị nhảy IP, ứng dụng tự động phân giải `hostname` để tìm và kết nối trực tiếp tới IP mới.
- **Củng cố Hàng đợi Tin nhắn Ngoại tuyến (Outbox Auto-Retry Hardening)**:
  - Tự động xả (flush) tin nhắn chờ sang địa chỉ IP mới ngay khi xác thực đúng định danh người nhận, chống gửi trùng lặp và bảo toàn hàng đợi qua các lần khởi động lại ứng dụng.
- **Đồng bộ Toàn diện Phiên bản**: Cập nhật `v1.11.0+21` vào toàn bộ mã nguồn, metadata Windows Runner, tài liệu hướng dẫn và bộ cài đặt.

### Cài đặt
Chạy file `install.bat` để cài đặt ứng dụng vào Windows (có shortcut Desktop & Start Menu, đăng ký Control Panel), hoặc chạy trực tiếp `ja_lan_messenger.exe` để sử dụng dạng portable. Xem file `USERGUIDE.md` đính kèm để biết thêm chi tiết.
