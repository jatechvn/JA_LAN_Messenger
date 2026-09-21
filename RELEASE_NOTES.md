TAG=v1.2.1
TITLE=JA LAN Messenger v1.2.1 — Mini PC Hardware Optimization, Showcase GlassDropdown, Typing Indicator Auto-Scroll
BODY=
## JA LAN Messenger v1.2.1 — Mini PC Hardware Optimization, Showcase GlassDropdown, Typing Indicator Auto-Scroll

- **Tối ưu hóa hiệu năng Mini PC & Thiết bị cấu hình thấp**: Tự động nhận diện phần cứng qua Windows Registry và phân hạng (Ultra, Medium, Lite). Chế độ Lite triệt tiêu toàn bộ chi phí GPU của BackdropFilter, ClipRRect và chuyển MeshBackground sang gradient tĩnh không mờ giúp app chạy siêu nhẹ, siêu mượt trên Intel N100 và máy văn phòng.
- **Dropdown chọn trạng thái chuẩn phong cách Showcase**: Thay thế menu cũ bằng `GlassDropdown` theo thiết kế `JA_Mini_Showcase`, loại bỏ hoàn toàn lỗi trong suốt xuyên thấu gây khó đọc, bổ sung viền sáng và dấu tick trạng thái rõ ràng.
- **Tự động cuộn & Đẩy vị trí bong bóng soạn thảo (Typing Indicator)**: Khi đối phương đang nhập tin nhắn, danh sách trò chuyện tự động cuộn mượt và hiển thị bong bóng rõ ràng phía trên khung nhập liệu.
- **Sửa lỗi khởi động ngôn ngữ & Reentrancy bàn phím Win32**: Nhận diện chuẩn xác ngôn ngữ Windows khi khởi động, bổ sung reentrancy guard cho bàn phím Win32 C++.
- **Đóng gói phát hành tin cậy**: Cải tiến quy trình đóng gói `package_dist.ps1` tự động dọn dẹp staging và xuất file cài đặt / portable độc lập vào thư mục `dist/`.

### Cài đặt
Chạy file `install.bat` để cài đặt ứng dụng vào Windows (có shortcut Desktop & Start Menu, đăng ký Control Panel), hoặc chạy trực tiếp `ja_lan_messenger.exe` để sử dụng dạng portable. Xem file `USERGUIDE.md` đính kèm để biết thêm chi tiết.
