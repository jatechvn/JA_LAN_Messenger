TAG=v1.8.1
TITLE=JA LAN Messenger v1.8.1 — Scheduler Frame Gate, Zero Inactive GPU, Remote Session Guard & OTA Cleanup
BODY=
## JA LAN Messenger v1.8.1 — Scheduler Frame Gate, Zero Inactive GPU, Remote Session Guard & OTA Cleanup

- **Cổng Khóa Khung Hình Tầng Scheduler (Scheduler Frame Gate & Zero Inactive GPU)**:
  - Tích hợp `PowerFrameGate` trên `PowerAwareWidgetsBinding` kiểm soát trực tiếp `framesEnabled` của Flutter Engine.
  - Ngắt tuyệt đối mọi thao tác dựng hình khi cửa sổ Inactive / Blur / Minimized, giải quyết triệt để lỗi các timer hoặc `setState` ngầm tiêu tốn tài nguyên GPU trên Desktop / RDP / VNC.
  - Tự động phát lệnh `scheduleFrame()` để vẽ lại giao diện tích lũy (dirty UI replay) mượt mà ngay khi cửa sổ active trở lại.
- **Đối soát Ảnh chụp Trạng thái Cửa sổ Native & Bảo vệ Phiên Remote (Native Snapshot Reconcile & Remote Guard)**:
  - Khắc phục sự cố Remote Desktop (RDP / VNC / AnyDesk) kích hoạt nhầm sự kiện `resumed`: đối soát với trạng thái Win32 thực tế (`isFocused`, `isVisible`, `isMinimized`) trước khi cấp quyền vẽ.
  - Thêm luồng kiểm tra nền chu kỳ 2 giây (`startNativeMonitoring`) đồng bộ trạng thái thực tế mà không làm re-arm bộ đếm giờ Idle Sleep.
- **Gia cố Thao tác Đóng Cửa sổ & Tránh Treo Hiệu ứng Kính Mờ (Close-to-Tray UI Hardening)**:
  - Bổ sung cờ chặn `_closePending` ngăn chặn người dùng nhấp nút X liên tục gây xếp chồng hộp thoại xác nhận.
  - Hộp thoại `CloseActionDialog` render tức thì không qua animation fade/scale khi ticker đang tắt, tránh treo trong suốt.
- **Bền vững Cấu hình Người Dùng (`AppPreferences` Durability & Atomic Flush)**:
  - Tuần tự hóa tiến trình lưu cấu hình qua file tạm `.tmp` rồi đổi tên nguyên tử (`atomic rename`), chống mất cài đặt khi tắt máy đột ngột.
  - Hàm `flush()` ép ghi toàn bộ dữ liệu xuống đĩa trước khi thoát app hoặc khởi chạy cập nhật OTA.
- **Tự động Dọn dẹp Vùng đệm Cập nhật OTA (`OtaStagingCleanup`)**:
  - Tự động xóa file `update.zip` và thư mục giải nén tạm sau khi app mới khởi động thành công (nhận diện qua cờ `--ota-session`), bảo toàn bản backup và log rollback.
- **Đồng bộ Toàn diện Phiên bản**: Cập nhật `v1.8.1+18` vào toàn bộ mã nguồn, metadata Windows Runner, tài liệu hướng dẫn và bộ cài đặt.

### Cài đặt
Chạy file `install.bat` để cài đặt ứng dụng vào Windows (có shortcut Desktop & Start Menu, đăng ký Control Panel), hoặc chạy trực tiếp `ja_lan_messenger.exe` để sử dụng dạng portable. Xem file `USERGUIDE.md` đính kèm để biết thêm chi tiết.
