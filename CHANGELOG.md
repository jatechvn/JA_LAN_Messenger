# Changelog

All notable changes to the **JA LAN Messenger** project will be documented in this file.

## [1.2.2] - 2026-09-21

### 🐛 Sửa lỗi & Tối ưu hóa
- **Định dạng tham số thông báo cập nhật OTA (Toast & Badge Tooltip)**: Khắc phục triệt để lỗi hiển thị chuỗi `%s` chưa được thay thế trong thông báo Toast và Tooltip huy hiệu OTA trên thanh tiêu đề khi có bản cập nhật mới (`updateAvailable`). Đồng thời chuẩn hóa tiền tố phiên bản `v`, hiển thị đồng nhất và chính xác trên cả 3 ngôn ngữ (Tiếng Việt, English, 简体中文).
- **Kiểm thử đa ngôn ngữ & Bàn giao kỹ thuật**: Mở rộng test suite `group_and_locale_test.dart` xác minh toàn diện chuỗi nội suy `%s` và cập nhật biên bản kỹ thuật nghiệm thu `docs/AI_HANDOFF.md`.

### 📦 Phát hành
- Đồng bộ version `1.2.2+5` trong `pubspec.yaml`, `constants.dart`, `Runner.rc`, `ABOUT.txt`, `install.bat`, `installer.iss`, `README.md`, `USERGUIDE.md`, `RELEASE_NOTES.md`.

## [1.2.1] - 2026-09-21

### 🚀 Nâng cấp & Tính năng mới
- **Tối ưu hóa phần cứng & Chế độ Lite cho máy cấu hình thấp (Mini PC / Intel N100)**: Tự động phát hiện thông số CPU/GPU qua Windows Registry, phân loại hồ sơ hiệu năng thông minh (`Ultra`, `Medium`, `Lite`). Trong chế độ `Lite`, ứng dụng tự động loại bỏ các hiệu ứng đồ họa tốn GPU (bỏ hoàn toàn `BackdropFilter` và `ClipRRect` trong `GlassSurface`, thay thế hiệu ứng 3x 85px blur orbs của `MeshBackground` bằng dải gradient tĩnh không mờ), giúp ứng dụng chạy siêu mượt trên các thiết bị Mini PC hoặc máy tính văn phòng cấu hình khiêm tốn. Bổ sung mục "Hiệu năng & Đồ họa" trong Cài đặt với thẻ thông số phần cứng và menu tùy chọn hồ sơ thủ công.
- **Menu trạng thái người dùng phong cách Showcase (GlassDropdown)**: Thiết kế lại toàn diện menu chọn trạng thái (Online / Away / Busy) theo phong cách `JA_Mini_Showcase`, sử dụng kính mờ cao cấp với độ đục cao (88%-98%), viền sáng highlight, hiệu ứng hover mượt mà và dấu tick trạng thái trực quan, khắc phục triệt để lỗi menu dropdown bị trong suốt xuyên thấu gây khó nhìn.

### 🐛 Sửa lỗi & Tối ưu hóa
- **Tự động cuộn & Đẩy vị trí bong bóng gõ tin nhắn (Typing Indicator)**: Khắc phục lỗi bong bóng typing bị khuất bên dưới màn hình khi đối phương đang soạn thảo. Giao diện trò chuyện tự động đẩy nội dung và cuộn mượt xuống dưới để người dùng tức thì nhìn thấy chỉ báo đang nhập mà không phải cuộn tay.
- **Khởi động chuẩn xác theo ngôn ngữ hệ điều hành Windows**: Khắc phục lỗi ứng dụng tự chọn tiếng Trung khi khởi động trên các máy cài đặt Windows tiếng Anh hoặc tiếng Việt; tích hợp lớp bảo vệ reentrancy cho bàn phím native C++ Win32 (`keyboard_reentrancy_guard.h`).
- **Đóng gói phát hành tin cậy (Dist Packaging)**: Nâng cấp script `windows/packaging/package_dist.ps1` và `build.bat`, tự động dọn dẹp thư mục staging tạm (`.package-stage-*`, `dist.previous-*`), đảm bảo thư mục `dist/` luôn chứa trọn vẹn bản thực thi portable và file zip phát hành mới nhất kèm mã SHA256 chính xác.

### 📦 Phát hành
- Đồng bộ version `1.2.1+4` trong `pubspec.yaml`, `constants.dart`, `Runner.rc`, `ABOUT.txt`, `installer.iss`, `README.md`, `USERGUIDE.md`, `RELEASE_NOTES.md`.

## [1.2.0] - 2026-09-19

### 🚀 Nâng cấp & Tính năng mới
- **Cập nhật tự động OTA qua mạng nội bộ (Over-The-Air Update)**: Tự động phát hiện và cập nhật phiên bản mới qua thư mục chia sẻ mạng LAN (SMB/UNC), hỗ trợ cấu hình chu kỳ (hàng ngày, hàng tuần, hàng tháng, tắt) qua file JSON và giao diện; hộp thoại `GlassUpdateDialog` hiển thị Release Notes, thanh tiến trình tải và áp dụng bản cập nhật không khóa tệp.
- **Bộ cài đặt & gỡ cài đặt chuẩn Windows (Control Panel Integration)**: Cung cấp `install.bat` cài đặt per-user (`%LOCALAPPDATA%\Programs\JA_LAN_Messenger`) không cần quyền UAC, tự tạo shortcut Desktop & Start Menu, đăng ký chính thức vào Windows Control Panel (`Programs and Features`) và Windows Settings; `uninstall.bat` & `uninstall.ps1` hỗ trợ gỡ cài đặt sạch sẽ, an toàn, tùy chọn lưu giữ dữ liệu cá nhân và cơ chế tự hủy không khóa tệp. Kèm kịch bản Inno Setup chuẩn hóa (`windows/packaging/installer.iss`).
- **Đính kèm nhiều tệp & Xem trước (Staged Attachments & File Preview)**: Cho phép dán hoặc chọn nhiều file/ảnh trực tiếp vào thanh soạn thảo trước khi gửi; xem trước ảnh qua Lightbox tương tác (phóng to, thu nhỏ, xoay ảnh) và hộp thoại xem chi tiết tài liệu.
- **Bộ gõ thông minh tích hợp (Built-in IME Telex & Pinyin)**: Tích hợp engine gõ tiếng Việt Telex và tiếng Trung Pinyin trực tiếp trong app với nút chuyển đổi nhanh và cơ chế tự động tránh xung đột khi bộ gõ ngoài (Unikey, EVKey, Microsoft IME) đang bật.
- **Tối ưu trải nghiệm chuyển đổi Compact Mode**: Hiệu ứng chuyển cảnh mượt mà giữa chế độ chuẩn (Standard) và chế độ thu nhỏ góc màn hình (Compact Mode); tối ưu diện tích hiển thị danh sách mạng và di chuyển nút scan mạng LAN.

### 🐛 Sửa lỗi & Tối ưu hóa
- Khắc phục triệt để lỗi test suite ghi đè file cấu hình thực tế của người dùng dẫn đến app luôn khởi động bằng tiếng Trung sau khi build.
- Bổ sung cơ chế cách ly kiểm thử `_isInTest` và `customFileForTesting` trong `LanguageProvider`, tự động nhận diện ngôn ngữ hệ điều hành Windows chính xác (`en_US` ➔ English, `vi_VN` ➔ Tiếng Việt, `zh_CN` ➔ Tiếng Trung).
- Sửa lỗi tràn giao diện (RenderFlex overflow) trong hộp thoại Cài đặt khi chuyển đổi giữa các ngôn ngữ có độ dài văn bản khác nhau.
- Dọn dẹp tệp thừa trùng lặp `lib/modules/theme/language_provider.dart`.

### 📦 Phát hành
- Đồng bộ version `1.2.0+3` trong `pubspec.yaml`, `constants.dart`, `Runner.rc`, `ABOUT.txt`, `install.bat`, `installer.iss`, `README.md`, `USERGUIDE.md`, `RELEASE_NOTES.md`.

## [1.1.0] - 2026-09-18

### 🚀 Nâng cấp & Tính năng mới
- **Dynamic AI Model Detection & Auto-Switch**: Tự động kết nối máy chủ JA-AI (Ollama), nhận diện toàn bộ danh sách model khả dụng (`/api/tags`), áp dụng heuristic phát hiện Vision, Thinking (Reasoning), Coder và chuẩn hóa tên hiển thị; hỗ trợ nút Làm mới (Refresh) trong Cài đặt và Header chat AI; tự động chuyển model hợp lệ khi đổi server; lưu cache model offline.
- **Trích dẫn & Ghim tin nhắn (Quote & Pin Messages)**: Hỗ trợ trích dẫn tin nhắn bất kỳ để trả lời với hiệu ứng cuộn mượt đến tin nhắn gốc; ghim nhiều tin nhắn lên thanh ghim phía trên khung trò chuyện với bộ đếm và điều hướng tức thì.
- **Glassmorphism Live Tuning & Tối ưu Dark/Light Mode**: Tinh chỉnh độ mờ (Blur) và độ trong suốt (Opacity) trực tiếp cho Card và Dialog với xem trước thời gian thực; giao diện Dark mode được cân chỉnh màu sắc dịu mắt, độ tương phản cao, hoạt động mượt mà với hiệu ứng kính mờ.
- **Độ bền lịch sử trò chuyện (Chat History Durability)**: Lưu trữ tin nhắn an toàn trên đĩa bằng cơ chế ghi file tạm nguyên tử (atomic write); tự động khôi phục tin nhắn khi mở lại ứng dụng; thống kê dung lượng lưu trữ và hỗ trợ xóa lịch sử.
- **Đa ngôn ngữ toàn diện**: Hỗ trợ 3 ngôn ngữ Tiếng Việt (VI), English (EN), 简体中文 (ZH) trên toàn bộ các thành phần giao diện, cài đặt và thông báo.

### 🐛 Sửa lỗi & Tối ưu hóa
- Khắc phục triệt để lỗi `Looking up a deactivated widget's ancestor is unsafe` khi đóng dialog hoặc chuyển trạng thái bằng cách tách luồng microtask an toàn.
- Ngăn chặn triệt để hiện tượng tràn layout (RenderFlex overflow) trong menu dropdown chọn model AI bằng cơ chế `isExpanded` và bọc flex tự co giãn.
- Tối ưu hóa timeout stream token AI và cơ chế tự phục hồi hàng đợi AI.
- Quản lý vòng đời quét mạng LAN, chỉ duy trì một luồng scan hoạt động duy nhất.

### 📦 Phát hành
- Đồng bộ version `1.1.0+2` trong `pubspec.yaml`, `constants.dart`, `Runner.rc`, `ABOUT.txt`, `README.md`, `USERGUIDE.md`, `RELEASE_NOTES.md`.

## [1.0.0] - 2026-09-16

### Initial Release
- **Source Code Reference**: Cloned BeeBEEP (C++/Qt) repository into `reference_sources/beebeep` for protocol comparison.
- **Pure Dart Networking Core**:
  - `LanDiscoveryService`: UDP Broadcast on `255.255.255.255:36475` & Multicast on `224.0.64.75:36475`.
  - `LanTcpServer`: Dedicated TCP server on port `6475` for incoming chat connections and handshakes.
  - `LanTcpClient`: Outbound TCP connection pool for messaging, buzzes, and handshakes.
  - `FileTransferEngine`: High-speed binary chunk streaming on TCP port `6476` with progress tracking.
  - `ProtocolBeebeep`: Codec for BeeBEEP delimiter wire protocol (`\u2029`, `\u2028`).
  - `SecurityService`: AES-256 encryption with pre-shared workgroup key.
- **Bento Glassmorphism UI**:
  - Responsive compact window (`960x640`), native Windows 10/11 frame integration.
  - `CompactSidebar`: Ultra-slim navigation rail (58px) with status avatar.
  - `PeerListView`: Contact list (260px) with online status dots, search, and manual IP add.
  - `ChatViewPanel`: Conversation panel with message bubbles, file previews, and input dock.
  - `TransferListView`: Dedicated active file transfer dashboard.
  - `SettingsDialog`: 3-tab layout (`Advanced Settings`, `About`, `User Guide`) complying with `flutter-project-rules`.
- **Scripts**: Added `run.bat`, `build.bat`, and `clean_project.bat`.
