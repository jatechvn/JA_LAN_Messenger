TAG=v1.8.0
TITLE=JA LAN Messenger v1.8.0 — Desktop Power & GPU Optimizer, Idle Sleep Mode, Resilient AI Locator
BODY=
## JA LAN Messenger v1.8.0 — Desktop Power & GPU Optimizer, Idle Sleep Mode, Resilient AI Locator

- **Bộ Tối ưu hóa Năng lượng & GPU trên Desktop (Flutter Desktop Power & GPU Optimizer)**:
  - **Quản lý Nguồn tập trung (Single Source of Truth)**: Xây dựng singleton `AppPowerManager.instance` quản lý 4 trạng thái cửa sổ thực tế: Có tiêu điểm (Focused/Active), Mất tiêu điểm (Inactive/Blur), Thu nhỏ (Minimized/Tray), và Ngủ rảnh tay khi không thao tác (Idle Sleep 12s/30s/60s).
  - **Phân tách 3 kênh Notifier độc lập**: Cung cấp 3 `ValueNotifier<bool>` riêng biệt (`backgroundAnimationNotifier`, `indicatorsAnimationNotifier`, `marqueeAnimationNotifier`) giúp hiệu ứng nền nặng (`MeshOrb` gradient) ngắt lập tức khi cửa sổ bị che hoặc mất focus để đưa tải GPU về 0%, trong khi các chỉ báo trạng thái UI và chữ cuộn hoạt động theo logic phù hợp.
  - **Bảo toàn hướng chạy của Hoạt ảnh (Direction Preservation on Resume)**: Hoạt ảnh `MeshOrb` ghi nhớ trạng thái đang tiến (`forward`) hay đang lùi (`reverse`) khi bị tạm dừng; khi cửa sổ active trở lại, hoạt ảnh tiếp tục chạy theo đúng hướng trước đó, khắc phục triệt để lỗi giật nhảy về đầu chu kỳ (snapback).
  - **Đóng băng vị trí cuộn & Session Epoch (Freeze Scroll Offset & Session Epoch)**: `BounceMarqueeText` giữ nguyên vị trí cuộn khi mất focus và tăng thế hệ phiên (`_sessionEpoch`) để vô hiệu hóa hoàn toàn các timer chờ hoặc ghost animation callback bị hoãn từ phiên trước.
  - **Đấu nối Native Win32 `WM_ACTIVATE`**: Tinh chỉnh mã nguồn native C++ trong `windows/runner/win32_window.cpp` để phân biệt chính xác `WA_INACTIVE` với các trạng thái kích hoạt khác, đảm bảo bắt kịp thời điểm chuyển đổi cửa sổ cấp hệ điều hành.
  - **Giao diện Cài đặt Tối ưu Năng lượng & Đa ngôn ngữ**: Bổ sung thẻ điều khiển trong hộp thoại Cài đặt (SettingsDialog) cho phép bật/tắt chế độ Ngủ rảnh tay (Idle Sleep) và chọn thời gian chờ (12 giây, 30 giây, 60 giây) với bản dịch hoàn chỉnh qua 3 ngôn ngữ: Tiếng Việt, English, 简体中文.
- **Tự động Tìm kiếm & Khôi phục Kết nối AI (Resilient AI Server Locator & Auto-Recovery)**:
  - Tích hợp lớp `AiServerLocator` tự động quét và định vị máy chủ AI (Ollama/JA-AI) trong mạng nội bộ.
  - Cơ chế tự phục hồi kết nối ngầm khi máy chủ khởi động lại hoặc mạng thay đổi.
- **Hiển thị Tên Ứng dụng Chuẩn & Đồng bộ Metadata Windows (Consistent Windows Branding & Metadata)**:
  - Đồng bộ tiêu đề cửa sổ Win32 và Flutter luôn hiển thị tên ứng dụng thân thiện `JA LAN Messenger` trên cả Windows 10 và Windows 11 thay vì tên file thực thi (`ja_lan_messenger.exe`).
  - Cập nhật thông tin bản quyền và nhà phát hành (`JA Tech`) cùng `FileDescription`, `ProductName` trong tài nguyên nhị phân `Runner.rc`, giúp Task Manager, Taskbar Tooltip và Alt+Tab hiển thị đúng tên app chuyên nghiệp.
- **Đồng bộ Toàn diện Phiên bản**: Cập nhật `v1.8.0+17` vào toàn bộ mã nguồn, metadata Windows Runner, tài liệu hướng dẫn và bộ cài đặt.

### Cài đặt
Chạy file `install.bat` để cài đặt ứng dụng vào Windows (có shortcut Desktop & Start Menu, đăng ký Control Panel), hoặc chạy trực tiếp `ja_lan_messenger.exe` để sử dụng dạng portable. Xem file `USERGUIDE.md` đính kèm để biết thêm chi tiết.
