TAG=v1.7.2
TITLE=JA LAN Messenger v1.7.2 — Bento Smart File Inspector, Pure Dart ZIP/Excel Parser, Hex View & Backdrop Dismissal
BODY=
## JA LAN Messenger v1.7.2 — Bento Smart File Inspector, Pure Dart ZIP/Excel Parser, Hex View & Backdrop Dismissal

- **Hộp thoại Soi tập tin Đa năng Bento & Đóng khi Click Ra ngoài (Bento Smart File Inspector & Backdrop Dismissal)**:
  - **Đóng nhanh khi click ra ngoài backdrop**: Hỗ trợ đóng hộp thoại xem trước ngay lập tức khi nhấp chuột ra ngoài vùng cửa sổ modal (backdrop tap-to-dismiss) hoặc nhấn phím `Esc`, không còn bắt buộc phải rê chuột tìm và bấm nút X.
  - **Thẻ Bento Thông tin Chi tiết (Bento Metadata Grid)**: Hiển thị phân loại MIME, dung lượng tệp định dạng đẹp, thời gian sửa đổi lần cuối, phân tích quyền truy cập tệp (Read/Write/Execute), và ứng dụng mặc định của hệ thống Windows được đăng ký để mở phần mở rộng đó (qua kênh `AssocQueryStringW` native Win32).
  - **Trình Duyệt Cấu trúc Tệp Nén ZIP Thuần Dart (Pure Dart ZIP Archive Explorer)**: Phân tích trực tiếp tệp nén `.zip`, `.jar`, `.apk` không cần giải nén ra ổ cứng; hiển thị danh sách cây thư mục/tệp tin, kích thước nén, kích thước thực tế và tỷ lệ nén (compression ratio) kèm biểu tượng trực quan.
  - **Trình Xem Trước Bảng Tính Excel (Pure Dart Sheet Structure Inspector)**: Đọc cấu trúc bảng tính `.xlsx`, trích xuất số lượng trang tính (Sheet count), tên danh sách từng Sheet, và dung lượng dữ liệu tệp nén bảng tính.
  - **Băm Toàn vẹn Tệp Tin SHA-256 (File Integrity Checksum)**: Tự động tính toán mã băm SHA-256 thời gian thực cho mọi tệp tin, tích hợp nút sao chép mã băm nhanh chỉ với 1 cú click (`Ctrl+Shift+C`) để kiểm tra toàn vẹn và đối soát an toàn.
  - **Trình Soi Mã Nhị Phân Hex Dump (Binary Hex Dump Viewer)**: Trích xuất và định dạng 512 bytes đầu tiên của mọi tệp nhị phân (`.bin`, `.dat`, `.exe`, `.dll`, `.iso`...) theo chuẩn Hex Editor (Offset | Hex bytes | ASCII representation) trong bảng cuộn giao diện tối Monospace.
  - **Sao Chép Trực Tiếp Tệp Tin Vật Lý vào Windows Clipboard**: Bổ sung nút sao chép file thật (`Pasteboard.writeFiles`) vào khay nhớ tạm Windows, cho phép người dùng `Ctrl+C` trong hộp thoại và `Ctrl+V` dán thẳng file vào Windows Explorer, thư mục làm việc, hoặc các ứng dụng khác.
  - **Phím Tắt Toàn Diện (Keyboard Shortcuts)**: `Enter` hoặc `Ctrl+O` để mở tệp bằng ứng dụng mặc định, `Ctrl+C` sao chép tệp vật lý, `Ctrl+Shift+C` sao chép mã SHA-256, `Esc` để đóng hộp thoại.
  - **Layout Thích Ứng (Responsive Bento UI)**: Sử dụng `LayoutBuilder` tự động co giãn kích thước dialog theo kích thước cửa sổ ứng dụng (kể cả trong Compact Mode), loại bỏ triệt để lỗi tràn pixel.
- **Đồng bộ Toàn diện Phiên bản**: Cập nhật `v1.7.2+16` vào toàn bộ mã nguồn, metadata Windows Runner, tài liệu hướng dẫn và bộ cài đặt.

### Cài đặt
Chạy file `install.bat` để cài đặt ứng dụng vào Windows (có shortcut Desktop & Start Menu, đăng ký Control Panel), hoặc chạy trực tiếp `ja_lan_messenger.exe` để sử dụng dạng portable. Xem file `USERGUIDE.md` đính kèm để biết thêm chi tiết.
