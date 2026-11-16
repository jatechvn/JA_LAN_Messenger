TAG=v1.14.0
TITLE=JA LAN Messenger v1.14.0 — AI Server Auto-Recovery, Power Gate Close Fix & Cohesion Modularization
BODY=
## JA LAN Messenger v1.14.0 — AI Server Auto-Recovery, Power Gate Close Fix & Cohesion Modularization

- **Tự động Khôi phục Máy chủ AI qua Danh tính BeeBEEP**: Tự động nhận diện và kết nối máy chủ JA-AI (Ollama) bằng cách đối chiếu hostname máy trạm từ gói tin bắt tay P2P và thăm dò trực tiếp endpoint API tại IP của máy chủ khi DNS/mDNS không phân giải được.
- **Sửa Lỗi Đơ Hộp thoại Đóng Cửa sổ (Power Gate Fix)**: Khắc phục triệt để lỗi không nhấn được nút trong hộp thoại đóng khi ứng dụng đang ở chế độ tiết kiệm năng lượng (dừng render frame khi inactive), tự động đánh thức frame render và sửa race condition lưu cấu hình đóng cửa sổ.
- **Tách Mô-đun Gắn kết & Bản đồ Kiến trúc (Cohesion Modularization)**: Phân tách 4 tệp mã nguồn lớn nhất thành các mô-đun gắn kết (parts), bảo toàn 100% API công khai và hợp đồng giao tiếp với `JA_LanMes_Cli`, bổ sung tài liệu kiến trúc `AI_CONTEXT.md` và các hướng dẫn `MODULE.md`.
- **Mở rộng Bộ Kiểm thử Tự động**: Tích hợp các bộ test mới nâng tổng số kiểm thử lên 621 tests (100% pass).
- **Đồng bộ Toàn diện Phiên bản**: Cập nhật `v1.14.0+24` vào toàn bộ mã nguồn, metadata Windows Runner, tài liệu hướng dẫn và bộ cài đặt.

### Cài đặt
Chạy file `install.bat` để cài đặt ứng dụng vào Windows (có shortcut Desktop & Start Menu, đăng ký Control Panel), hoặc chạy trực tiếp `ja_lan_messenger.exe` để sử dụng dạng portable. Xem file `USERGUIDE.md` đính kèm để biết thêm chi tiết.
