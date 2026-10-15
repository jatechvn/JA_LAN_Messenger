TAG=v1.10.0
TITLE=JA LAN Messenger v1.10.0 — In-Chat Search, Per-Peer Drafts, Folder Auto-Zip, Message Forwarding & Performance Upgrade
BODY=
## JA LAN Messenger v1.10.0 — In-Chat Search, Per-Peer Drafts, Folder Auto-Zip, Message Forwarding & Performance Upgrade

- **Tìm kiếm Tin nhắn trong Cuộc trò chuyện (`Ctrl+F`)**:
  - Thanh tìm kiếm trực tiếp trong khung chat với bộ đếm kết quả (`1/N`), nhảy nhanh qua các tin nhắn khớp bằng `Enter` / `Shift+Enter` (`↑`/`↓`), tự động cuộn tới vị trí tin nhắn và làm nổi bật bong bóng chat.
- **Lưu Bản nháp theo Từng Cuộc trò chuyện (Per-Peer Drafts)**:
  - Tự động lưu và khôi phục nội dung đang gõ dở khi chuyển đổi giữa các cuộc trò chuyện, hiển thị huy hiệu `[Nháp]` / `[Draft]` / `[草稿]` nổi bật trên danh sách liên hệ.
- **Kéo-Thả Thư mục Tự động Nén `.zip` (Folder Auto-Zip)**:
  - Kéo-thả trực tiếp thư mục vào khung chat để tự động đóng gói thành tệp `.zip` tốc độ cao (`tar.exe` / PowerShell fallback) và đính kèm sẵn sàng gửi.
- **Chuyển tiếp Tin nhắn & Tệp đính kèm (Forward Message Dialog)**:
  - Hỗ trợ chuyển tiếp nhanh tin nhắn văn bản, nhãn dán hoặc tệp đính kèm tới một hoặc nhiều đồng nghiệp và nhóm cùng lúc kèm lời nhắn tùy chọn.
- **Nhãn Phân cách Ngày & Phím tắt Điều hướng Nhanh**:
  - Bổ sung nhãn ngày (`Hôm nay`, `Hôm qua`, `dd/MM/yyyy`), gom cụm tin nhắn liên tiếp cùng người gửi, chống tràn thanh công cụ Compact `320px`, và hệ thống phím tắt `Ctrl+F`, `Ctrl+K`, `Alt+Up/Down`, `Esc`.
- **Tối ưu Hiệu năng Dựng hình & I/O Lịch sử**:
  - Thay thế `jsonEncode` mỗi frame bằng bộ đếm $O(1)$ `reactionRevision`, ảo hóa danh sách `PeerListView` bằng `ListView.builder`, và đọc/ghi lịch sử JSON song song tốc độ cao.
- **Đồng bộ Toàn diện Phiên bản**: Cập nhật `v1.10.0+20` vào toàn bộ mã nguồn, metadata Windows Runner, tài liệu hướng dẫn và bộ cài đặt.

### Cài đặt
Chạy file `install.bat` để cài đặt ứng dụng vào Windows (có shortcut Desktop & Start Menu, đăng ký Control Panel), hoặc chạy trực tiếp `ja_lan_messenger.exe` để sử dụng dạng portable. Xem file `USERGUIDE.md` đính kèm để biết thêm chi tiết.
