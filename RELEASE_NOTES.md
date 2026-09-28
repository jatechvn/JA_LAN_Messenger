TAG=v1.6.0
TITLE=JA LAN Messenger v1.6.0 — System Tray Toggle, Smart Entity Detection & Responsive Chat Header
BODY=
## JA LAN Messenger v1.6.0 — System Tray Toggle, Smart Entity Detection & Responsive Chat Header

- **Ẩn / Hiện Cửa Sổ Thông Minh qua Khay Hệ Thống (System Tray 1-Click Toggle)**:
  - Nhấp chuột trái vào System Tray Icon để toggle tức thì: thu nhỏ/ẩn app vào khay hệ thống nếu đang ở tiền cảnh, hoặc khôi phục (`restore()`) và đưa lên đầu màn hình (`focus()`) nếu đang bị ẩn/minimize/nằm sau cửa sổ khác.
- **Tự động Nhận diện Thực thể Thông minh & Tiện ích Nhanh (Smart Entity Detection & Quick Action Chips)**:
  - Tự động nhận diện URLs (`https://`, `http://`, `www.`, các domain phổ biến).
  - Tự động nhận diện Số điện thoại di động, cố định VN và quốc tế (loại trừ triệt để địa chỉ IP và ngày tháng).
  - Tự động nhận diện Địa chỉ Email chuẩn RFC.
  - Tự động nhận diện Đường dẫn UNC mạng nội bộ (`\\server\share\...`) và file/ổ đĩa Windows (`C:\...`, `D:\...`) hỗ trợ đầy đủ các đường dẫn có khoảng trắng (như `C:\Program Files\...`).
  - Hiển thị dải chip bo tròn kính mờ Bento Glassmorphic ngay dưới tin nhắn: 1-click chuột trái để mở/thao tác (mở trình duyệt, mở Explorer `/select,`, soạn mail, gọi điện) và 1-click chuột phải/nút icon để sao chép.
- **Bôi đen Lựa chọn & Sao chép Linh hoạt trên Bong bóng Chat (Selectable Text)**:
  - Bật `selectable: true` trong `MarkdownMessageView` cho phép người dùng bôi đen và sao chép từng đoạn chữ tùy chọn trong tin nhắn.
  - Tích hợp GitHub Flavored Markdown (GFM) và hỗ trợ click trực tiếp vào link/đường dẫn trong nội dung chat.
- **Tích hợp Menu Chuột phải Tin nhắn (`_showMessageMenu`)**:
  - Bổ sung các lệnh mở và sao chép riêng biệt cho từng thực thể tìm thấy trong tin nhắn.
- **Thu gọn Linh hoạt Tiêu đề Chat khi mở Conversation Info (Responsive Header Adaptation)**:
  - Tự động chuyển tiêu đề sang phong cách thu gọn khi mở bảng thông tin bên phải (`isDetailsOpen`).
  - Gắn chấm tròn trạng thái online/offline trực tiếp vào Avatar và ẩn thẻ StatusBadge rời (tiết kiệm ~85px chiều ngang).
  - Sử dụng `BounceMarqueeText` cho nickname cuộn chữ mượt mà khi tên dài, loại bỏ hoàn toàn việc bị cắt ngắn thành `SG - M...`.
- **Bảo mật Thực thi Lệnh Shell**: Loại bỏ hoàn toàn fallback qua `cmd.exe /c start` với cờ `runInShell: true` trong `QuickActionHelper`. Trên Windows sử dụng trực tiếp lệnh an toàn `Process.run('explorer.exe', [...])` qua ShellExecute của hệ điều hành, chống tuyệt đối nguy cơ command injection.
- **Đồng bộ toàn diện phiên bản**: Cập nhật `v1.6.0+12` vào toàn bộ mã nguồn, metadata Windows Runner, tài liệu hướng dẫn và bộ cài đặt.

### Cài đặt
Chạy file `install.bat` để cài đặt ứng dụng vào Windows (có shortcut Desktop & Start Menu, đăng ký Control Panel), hoặc chạy trực tiếp `ja_lan_messenger.exe` để sử dụng dạng portable. Xem file `USERGUIDE.md` đính kèm để biết thêm chi tiết.
