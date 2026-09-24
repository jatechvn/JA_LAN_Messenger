TAG=v1.4.0
TITLE=JA LAN Messenger v1.4.0 — Offline Outbox Queue & Auto-Retry on Reconnect
BODY=
## JA LAN Messenger v1.4.0 — Offline Outbox Queue & Auto-Retry on Reconnect

- **Hàng đợi Ngoại tuyến & Tự động gửi lại (Offline Outbox Queue & Auto-Retry)**: Giải quyết triệt để vấn đề tin nhắn bị thất lạc khi người nhận đang tắt máy/ngoại tuyến trong mạng LAN P2P. Tin nhắn gửi lỗi tự động chuyển sang trạng thái `failed` và được xếp vào hàng đợi Outbox.
- **Tự động gửi bù khi Reconnect (`flushPendingOutgoingMessagesForPeer`)**: Ngay khi máy người nhận online trở lại và hoàn tất bắt tay LAN, hệ thống tự động kích hoạt gửi bù toàn bộ tin nhắn tồn đọng theo đúng thứ tự thời gian.
- **Hỗ trợ Chat nhóm Toàn diện**: Tự động theo dõi các thành viên nhóm đang offline tại thời điểm gửi tin và gửi bù tin nhắn nhóm cho từng thành viên khi họ kết nối lại.
- **Giao diện Trực quan & Thao tác Thử lại (UI/UX Retry Controls)**:
  - Hiển thị biểu tượng lỗi `Icons.error_outline_rounded` màu đỏ cam (`#F87171`) kèm chữ **"Thử lại"** trên cả bong bóng tin nhắn và thẻ tệp đính kèm.
  - Bấm 1 chạm trực tiếp vào icon lỗi để kích hoạt gửi lại (`retrySendMessage`).
  - Thêm tùy chọn **"Thử lại"** (`retrySend`) trực tiếp vào Menu chuột phải (Context menu) của tin nhắn.
  - Tooltip giải thích: *"Chưa gửi được (Người nhận ngoại tuyến). Nhấn để thử lại."*
- **Độ bền dữ liệu qua các phiên khởi động**: Tự động phục hồi trạng thái tin nhắn và chuẩn hóa các tin dở dang (`sending`) khi tắt máy thành `failed`, nạp vào Outbox để sẵn sàng gửi lại khi mở app.
- **Đa ngôn ngữ Trọn vẹn**: Bổ sung đầy đủ chuỗi giao diện cho cả 3 ngôn ngữ: Tiếng Việt, Tiếng Anh và Tiếng Trung.
- **Đồng bộ toàn diện phiên bản**: Cập nhật `v1.4.0+8` vào toàn bộ mã nguồn, metadata Windows Runner, tài liệu hướng dẫn và bộ cài đặt.

### Cài đặt
Chạy file `install.bat` để cài đặt ứng dụng vào Windows (có shortcut Desktop & Start Menu, đăng ký Control Panel), hoặc chạy trực tiếp `ja_lan_messenger.exe` để sử dụng dạng portable. Xem file `USERGUIDE.md` đính kèm để biết thêm chi tiết.
