TAG=v1.3.0
TITLE=JA LAN Messenger v1.3.0 — Personal & Group Avatars, Tray Badge & Group Enhancements
BODY=
## JA LAN Messenger v1.3.0 — Personal & Group Avatars, Tray Badge & Group Enhancements

- **Đồng bộ Avatar cá nhân qua LAN (Personal Avatar LAN Sync)**: Tự động nén ảnh đại diện 96x96 px Base64 (~2-4 KB), truyền qua handshake `BEE-CIAO` và cập nhật tức thì qua gói tin `BEE-USER`. Đồng nghiệp nhìn thấy ngay avatar trên danh bạ và khung chat.
- **Tùy biến & Đồng bộ Avatar Nhóm (Group Avatar)**: Hỗ trợ chọn icon preset hoặc tải ảnh từ máy tính kèm bảng màu nền tùy biến; đồng bộ qua LAN với gói `BEE-GROU` và hỗ trợ đổi avatar linh hoạt trong cài đặt nhóm.
- **Chống mở trùng ứng dụng (Single-Instance Mutex)**: Tích hợp Win32 Mutex trong C++ native runner, tự động kích hoạt và đưa cửa sổ đang chạy lên trên cùng khi mở lại ứng dụng, tránh xung đột chiếm giữ cổng mạng.
- **Huy hiệu số tin nhắn trên Khay hệ thống (Tray Icon Badge Counter)**: Tự động vẽ số tin nhắn chưa đọc dạng huy hiệu đỏ nổi bật trực tiếp lên biểu tượng khay hệ thống Windows.
- **Nâng cấp toàn diện Nhóm chat**: Lọc bỏ bản thân khi tạo nhóm, nhấp vào số lượng thành viên để xem danh sách chi tiết, hỗ trợ giải tán nhóm triệt để đồng bộ trên toàn mạng LAN, rời nhóm, đuổi thành viên, kèm chỉ báo đang nhập (Typing Indicator) và thông báo tin nhắn mới trong nhóm.
- **Đồng bộ toàn diện phiên bản**: Cập nhật `v1.3.0+6` vào toàn bộ mã nguồn, metadata Windows Runner, tài liệu hướng dẫn và bộ cài đặt.

### Cài đặt
Chạy file `install.bat` để cài đặt ứng dụng vào Windows (có shortcut Desktop & Start Menu, đăng ký Control Panel), hoặc chạy trực tiếp `ja_lan_messenger.exe` để sử dụng dạng portable. Xem file `USERGUIDE.md` đính kèm để biết thêm chi tiết.
