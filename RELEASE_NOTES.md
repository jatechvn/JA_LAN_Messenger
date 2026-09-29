TAG=v1.7.1
TITLE=JA LAN Messenger v1.7.1 — Smart Manual IP 2-Octet Suggestion, Connection Feedback & New Friend Badge
BODY=
## JA LAN Messenger v1.7.1 — Smart Manual IP 2-Octet Suggestion, Connection Feedback & New Friend Badge

- **Gợi ý Thông minh theo IP Đang Sử dụng & Viết sẵn 2 Octet Đầu (Smart 2-Octet Manual IP Suggestion)**:
  - Tự động nhận diện dải mạng của card mạng LAN vật lý đang hoạt động (`172.21.*.*` hoặc `192.168.*.*`) và điền sẵn 2 số đầu tiên (ví dụ `172.21.` hoặc `192.168.`) thay vì gán cứng 3 số (`192.168.1.`) như trước.
  - Con trỏ soạn thảo tự động đặt ngay sau dấu chấm thứ 2, giúp người dùng chỉ việc gõ nốt 2 số còn lại (ví dụ `.100.25`) và nhấn Enter để kết nối.
  - Tích hợp thanh **Suggestion Chips** (`[ 172.21. ]`, `[ 192.168. ]`) giúp chuyển đổi tiền tố mạng chỉ bằng 1 cú nhấp chuột khi máy có nhiều card mạng hoạt động đồng thời (LAN dây xưởng + Wi-Fi).
- **Phản hồi Kết nối Thời gian thực & Thông báo Thành công (Connection Feedback & Toast)**:
  - Nút "Kết nối" hiển thị vòng xoay tiến trình (`CircularProgressIndicator`) và văn bản `Đang kết nối tới [IP]...` trong thời gian bắt tay TCP & HELLO (timeout 3.2s), ngăn chặn nhấp chuột trùng lặp.
  - Khi kết nối thành công: Hộp thoại tự động đóng, Toast thông báo nổi lên (`Đã kết nối và thêm bạn mới: $name ($ip)`), và tự động mở ngay khung chat với bạn mới.
  - Khi không kết nối được: Hiển thị cảnh báo lỗi inline màu cam/vàng rõ ràng ngay dưới ô nhập, cho phép sửa lại IP mà không bị mất dữ liệu đã gõ, kèm nút `Lưu vào danh bạ (ngoại tuyến)` để lưu trước khi máy đồng nghiệp chưa bật ứng dụng.
- **Ưu tiên Bạn mới lên Đầu Danh sách & Huy hiệu "Bạn mới" (New Friend Prioritization & Badge)**:
  - Tự động ưu tiên đưa bạn mới vừa kết nối lên vị trí cao nhất trong danh sách liên hệ (ngay sau các mục đã ghim `isPinned`), áp dụng cho cả tab *Tất cả* và tab *Trực tuyến*.
  - Hiển thị huy hiệu `[Bạn mới]` (VI) / `[New]` (EN) / `[新好友]` (ZH) màu xanh ngọc bích (`accentEmerald`) tinh tế bên cạnh tên liên hệ.
  - Tự động gỡ huy hiệu khi người dùng gửi tin nhắn trò chuyện đầu tiên (`sendMessage`), hoặc chủ động gỡ bỏ qua menu chuột phải (`Bỏ đánh dấu bạn mới`).
- **Đồng bộ Toàn diện Phiên bản**: Cập nhật `v1.7.1+15` vào toàn bộ mã nguồn, metadata Windows Runner, tài liệu hướng dẫn và bộ cài đặt.

### Cài đặt
Chạy file `install.bat` để cài đặt ứng dụng vào Windows (có shortcut Desktop & Start Menu, đăng ký Control Panel), hoặc chạy trực tiếp `ja_lan_messenger.exe` để sử dụng dạng portable. Xem file `USERGUIDE.md` đính kèm để biết thêm chi tiết.
