TAG=v1.7.0
TITLE=JA LAN Messenger v1.7.0 — Conversation Scroll Restoration, Visible-Based Read Receipts & Packaging Auto-Cleanup
BODY=
## JA LAN Messenger v1.7.0 — Conversation Scroll Restoration, Visible-Based Read Receipts & Packaging Auto-Cleanup

- **Khôi phục vị trí cuộn & ý định xem tin nhắn (Conversation Scroll Restoration)**:
  - Bổ sung `ConversationScrollStore` lưu trạng thái vị trí cuộn chat vào `conversation_scroll.json`.
  - Tự động ghi nhớ vị trí pixel cuộn và ý định bám đáy (bottom intent) riêng biệt cho từng người dùng/nhóm qua các lần khởi động lại app.
  - Khi mở lại app hoặc chuyển cuộc trò chuyện, khung chat tự động khôi phục đúng vị trí người dùng đang đọc, không nhảy bừa xuống đáy.
- **Cơ chế xác nhận đã đọc dựa trên khả năng nhìn thấy thực tế (Visible-Message Read Receipts)**:
  - Tin nhắn nhận được chỉ được đánh dấu là "đã đọc" (`read`) khi cửa sổ ứng dụng đang active/focused, tin nhắn nằm trong vùng hiển thị và lưu lại trên màn hình tối thiểu 500ms.
  - Loại bỏ hoàn toàn cơ chế đọc vội vàng chỉ bằng thao tác chọn người liên hệ hoặc gửi tin nhắn.
- **Dịch vụ chú ý tin nhắn chưa đọc & Nhấp nháy Taskbar Windows (Persistent Unread Attention)**:
  - Tích hợp `UnreadAttentionService` và native Windows runner MethodChannel `FlashWindowEx` (`FLASHW_TRAY | FLASHW_TIMER`).
  - Khi có tin chưa đọc (> 0), biểu tượng Tray luân phiên nhấp nháy mỗi 750ms và thanh Taskbar Windows nhấp nháy liên tục cho đến khi người dùng quan sát tin nhắn.
- **Tối ưu hóa Hoạt ảnh Nhãn dán Động (Animated Sprite Stickers UX)**:
  - Tinh chỉnh tốc độ chuyển khung hình Sprite sang **18 fps** (56ms) cho hoạt ảnh nhãn dán chuyển động tự nhiên, mượt mà và tiết kiệm CPU.
  - Bọc bảng chọn nhãn dán/emoji bằng `TapRegion`: Tự động đóng bảng chọn khi nhấp chuột ra ngoài khung chat hoặc vùng nhập liệu.
  - Tự động đóng bảng chọn sticker ngay sau khi chọn gửi nhãn dán.
- **Tự động Dọn dẹp Thư mục Staging & Sao lưu khi Đóng gói (Packaging Auto-Cleanup)**:
  - Nâng cấp `windows/packaging/package_dist.ps1` và `clean_project.bat`: Tự động dọn dẹp sạch sẽ các thư mục staging tạm `.package-stage-*` và bản sao lưu cũ `dist.previous-*` ngay sau khi đóng gói thành công.
  - Thu hồi hàng Gigabyte dung lượng đĩa và loại bỏ triệt để rác đồng bộ trên OneDrive.
- **Giao diện Input Dock thích ứng màn hình hẹp (Responsive Input Toolbar)**:
  - Tự động co giãn kích thước nút bấm và padding khi chiều rộng khung chat thu nhỏ (< 360px), loại bỏ hoàn toàn lỗi tràn pixel (`RenderFlex overflowed`) trong chế độ Compact Mode.
- **Đồng bộ toàn diện phiên bản**: Cập nhật `v1.7.0+14` vào toàn bộ mã nguồn, metadata Windows Runner, tài liệu hướng dẫn và bộ cài đặt.

### Cài đặt
Chạy file `install.bat` để cài đặt ứng dụng vào Windows (có shortcut Desktop & Start Menu, đăng ký Control Panel), hoặc chạy trực tiếp `ja_lan_messenger.exe` để sử dụng dạng portable. Xem file `USERGUIDE.md` đính kèm để biết thêm chi tiết.


