# Changelog

All notable changes to the **JA LAN Messenger** project will be documented in this file.

## [1.9.0] - 2026-10-06

### 🚀 Nâng cấp & Tính năng mới
- **Gộp Bong Bóng Đính Kèm Theo Mẻ (LAN Attachment Batches & Shared Bubble)**:
  - Khi gửi nhiều tệp tin hoặc hình ảnh cùng một lúc, các tệp liền kề thuộc cùng một mẻ (`attachmentBatchId`) tự động gộp chung trong một bong bóng tin nhắn duy nhất, mang lại giao diện tinh gọn, hiện đại tương tự các ứng dụng nhắn tin hàng đầu.
  - Mỗi tệp trong mẻ vẫn duy trì đầy đủ tiến trình tải, trạng thái truyền, menu thao tác chuột phải, và bộ phím nhận diện đã đọc độc lập.
  - **Cách ly lỗi gửi tệp (Send Error Isolation)**: Khi một tệp trong mẻ bị lỗi hoặc không tồn tại, hệ thống không hủy toàn bộ mẻ mà tiếp tục gửi các tệp còn lại, ghi nhận chính xác tệp lỗi và báo cáo số lượng thất bại.
  - **Mở rộng Giao thức BeeBEEP an toàn**: Bổ sung trường thứ 15 lưu `attachmentBatchId` trong gói tin chào file (`file offer`), giữ tương thích ngược tuyệt đối với các máy BeeBEEP C++ và bản cũ (vốn chỉ đọc 13 trường đầu).
- **Lưới Ảnh Thích Ứng Thu Nhỏ Co Giãn (Compact Adaptive Attachment Image Grid)**:
  - Tự động sắp xếp các hình ảnh đính kèm theo lưới thu nhỏ linh hoạt (`Wrap tiles`): 2 ảnh chia 2 cột, 4 ảnh xếp lưới 2x2 vuông vức, 3 ảnh hoặc 5+ ảnh hiển thị 3 cột khi bong bóng rộng >= 400px (hoặc 2 cột trên màn hình hẹp).
  - Tệp tài liệu thông thường trong mẻ hỗn hợp giữ nguyên dạng hàng ngang đầy đủ theo đúng thứ tự lựa chọn.
  - Thu nhỏ và giới hạn giải mã thumbnail theo kích thước hiển thị * tỷ lệ pixel thiết bị (DPR), tiết kiệm đáng kể bộ nhớ RAM và GPU, nhấp vào ảnh vẫn mở Lightbox xem độ phân giải gốc.
- **Xác Nhận Đã Nhận & Đã Xem Cho Tệp Tin & Ảnh (Attachment Received & Read Receipts)**:
  - Bổ sung trạng thái **Đã nhận** (khi đối phương tải xong file và gửi ACK hoàn tất) và **Đã xem** (`seen` / phát sự kiện `BEE-READ`) trên từng tệp tin và ảnh gửi đi.
  - Hỗ trợ đầy đủ cho cả cuộc trò chuyện trực tiếp (Direct) và trò chuyện nhóm (Group chat - tổng hợp chỉ đánh dấu Đã nhận/Đã xem khi tất cả thành viên đáp ứng).
- **Chân Bong Bóng Gộp Chung Thống Nhất (Shared Attachment Batch Footer)**:
  - Loại bỏ việc lặp lại tem thời gian (timestamp) và nhãn trạng thái ở từng tệp lẻ. Toàn bộ mẻ đính kèm hiển thị một chân footer góc dưới bên phải thống nhất, phản ánh trạng thái tổng hợp của cả mẻ.

### 📦 Phát hành
- Đồng bộ version 1.9.0+19 trong pubspec.yaml, constants.dart, Runner.rc, installer.iss, install.bat, ABOUT.txt, USERGUIDE.md, README.md, RELEASE_NOTES.md.

## [1.8.1] - 2026-10-05

### 🚀 Nâng cấp & Tính năng mới
- **Cổng Khóa Khung Hình Tầng Scheduler (Scheduler Frame Gate & Zero Inactive GPU)**:
  - Tích hợp mixin `PowerFrameGate` trên `PowerAwareWidgetsBinding` kế thừa `WidgetsFlutterBinding`, trực tiếp kiểm soát thuộc tính `framesEnabled` của Flutter SchedulerBinding.
  - Khi cửa sổ ở trạng thái không hoạt động (Inactive, Mất tiêu điểm Blur, Thu nhỏ Minimized), `framesEnabled` lập tức chuyển về `false`. Khắc phục triệt để lỗi các timer ngầm, con trỏ văn bản caret, hoặc lệnh `setState` từ logic nghiệp vụ tiếp tục kích hoạt vẽ lại màn hình gây hao tốn GPU trên Desktop/RDP/VNC.
  - Khi cửa sổ active trở lại, tự động phát lệnh `scheduleFrame()` để vẽ lại giao diện tích lũy (dirty UI replay) mượt mà mà không sinh các sự kiện vòng đời giả tạo.
- **Đối soát Ảnh chụp Trạng thái Cửa sổ Native & Bảo vệ Phiên Remote (Native Snapshot Reconcile & Remote Guard)**:
  - Khắc phục sự cố kết nối lại qua Remote Desktop (RDP / VNC / AnyDesk) khiến cửa sổ nhận sự kiện `resumed` ảo dù thực tế đang bị ẩn hoặc thu nhỏ: chuyển các sự kiện vòng đời thành gợi ý kích hoạt (`reconcileActivation()`) và đối soát trực tiếp qua API Win32 thực tế (`isFocused`, `isVisible`, `isMinimized`).
  - Thêm luồng kiểm tra nền chu kỳ 2 giây (`startNativeMonitoring`) để tự động bắt kịp trạng thái cửa sổ thực tế mà không làm tái kích hoạt (re-arm) bộ đếm giờ Idle Sleep.
- **Gia cố Thao tác Đóng Cửa sổ & Tránh Treo Hiệu ứng Kính Mờ (Close-to-Tray UI Hardening)**:
  - Bổ sung cờ chặn `_closePending` ngăn chặn hiện tượng người dùng nhấp nút X liên tục gây xếp chồng nhiều hộp thoại xác nhận.
  - Hộp thoại `CloseActionDialog` tự động phát hiện khi cổng ticker đang tắt để dựng hình ngay lập tức, loại bỏ hiệu ứng mờ/scale chuyển động có thể bị treo trong suốt.
- **Bền vững Cấu hình Người Dùng (`AppPreferences` Durability & Atomic Flush)**:
  - Tuần tự hóa toàn bộ tiến trình lưu file cấu hình người dùng qua file tạm `.tmp` rồi đổi tên nguyên tử (`atomic rename`), triệt tiêu rủi ro hỏng file JSON hoặc mất cài đặt (chế độ đóng cửa sổ, nhớ lựa chọn, theme) khi tắt máy đột ngột.
  - Bổ sung hàm `flush()` ép ghi toàn bộ dữ liệu xuống đĩa trước khi thoát app hoặc khởi chạy cập nhật OTA.
- **Tự động Dọn dẹp Vùng đệm Cập nhật OTA (`OtaStagingCleanup`)**:
  - Tích hợp lớp `OtaStagingCleanup` tự động kiểm tra cờ `--ota-session` khi phiên bản mới khởi chạy thành công và xóa sạch file `update.zip` cùng thư mục giải nén tạm trong `%TEMP%`, tiết kiệm dung lượng ổ cứng trong khi vẫn bảo toàn bản backup và log rollback.

### 📦 Phát hành
- Đồng bộ version 1.8.1+18 trong pubspec.yaml, constants.dart, Runner.rc, installer.iss, install.bat, ABOUT.txt, USERGUIDE.md, README.md, RELEASE_NOTES.md.

## [1.8.0] - 2026-10-03

### 🚀 Nâng cấp & Tính năng mới
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

### 📦 Phát hành
- Đồng bộ version 1.8.0+17 trong pubspec.yaml, constants.dart, Runner.rc, ABOUT.txt, USERGUIDE.md, README.md, RELEASE_NOTES.md.

## [1.7.2] - 2026-10-02

### 🚀 Nâng cấp & Tính năng mới
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

### 📦 Phát hành
- Đồng bộ version 1.7.2+16 trong pubspec.yaml, constants.dart, Runner.rc, ABOUT.txt, USERGUIDE.md, README.md, RELEASE_NOTES.md.

## [1.7.1] - 2026-09-29

### 🚀 Nâng cấp & Tính năng mới
- **Gợi ý Thông minh theo IP đang sử dụng & Viết sẵn 2 Octet Đầu (Smart 2-Octet Manual IP Suggestion)**:
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

### 📦 Phát hành
- Đồng bộ version 1.7.1+15 trong pubspec.yaml, constants.dart, Runner.rc, ABOUT.txt, USERGUIDE.md, README.md, RELEASE_NOTES.md.

## [1.7.0] - 2026-09-29

### 🚀 Nâng cấp & Tính năng mới
- **Khôi phục vị trí cuộn & ý định xem tin nhắn qua các lần khởi động lại (Conversation Scroll Restoration)**:
  - Bổ sung `ConversationScrollStore` lưu trữ trạng thái vị trí cuộn chat vào tệp `conversation_scroll.json` ngay cạnh cấu hình ứng dụng.
  - Tự động ghi nhớ vị trí pixel cuộn và ý định bám đáy (bottom intent) riêng biệt cho từng người dùng/nhóm.
  - Khi mở lại ứng dụng hoặc chuyển đổi giữa các cuộc trò chuyện, khung chat tự động khôi phục đúng vị trí người dùng đang đọc thay vì luôn tự động nhảy xuống tin nhắn mới nhất nếu người dùng đang đọc lại lịch sử cũ.
- **Cơ chế xác nhận đã đọc dựa trên khả năng nhìn thấy thực tế (Visible-Message Read Receipts)**:
  - Bỏ cơ chế tự động đánh dấu đã đọc toàn bộ tin nhắn chỉ khi người dùng click chọn người liên hệ hoặc gửi tin nhắn.
  - Tin nhắn nhận được chỉ được đánh dấu là "đã đọc" (`read`) khi cửa sổ ứng dụng đang ở trạng thái active/focused, tin nhắn nằm trong vùng hiển thị (viewport) và lưu lại trên màn hình tối thiểu 500ms.
  - Giữ nguyên trạng thái tin nhắn chưa đọc (`unread`) khi cửa sổ bị che khuất, thu nhỏ hoặc tin nhắn nằm ngoài vùng cuộn.
- **Dịch vụ thông báo chú ý tin nhắn chưa đọc & Nhấp nháy Taskbar Windows (Persistent Unread Attention)**:
  - Tích hợp `UnreadAttentionService` giao tiếp trực tiếp với native Windows runner qua MethodChannel `FlashWindowEx` (`FLASHW_TRAY | FLASHW_TIMER`).
  - Khi có tin nhắn chưa đọc (> 0), biểu tượng khay hệ thống (Tray) tự động luân phiên nhấp nháy chu kỳ 750ms và nhấp nháy thanh tác vụ Windows (Taskbar) cho đến khi người dùng mở và thực sự quan sát tin nhắn.
  - Khắc phục lỗi tính toán số tin chưa đọc khi đang bật ô tìm kiếm danh bạ (dùng danh sách liên hệ không bị search filter).
- **Tối ưu hóa Trải nghiệm Nhãn dán Động (Animated Sprite Stickers UX)**:
  - Tinh chỉnh tốc độ chuyển khung hình Sprite từ 22 fps xuống **18 fps** (56ms) cho hoạt ảnh nhãn dán chuyển động tự nhiên, mượt mà và tiết kiệm CPU.
  - Bọc bảng chọn nhãn dán và emoji bằng `TapRegion`: Tự động đóng bảng chọn khi người dùng nhấp chuột ra ngoài khung chat hoặc vùng nhập liệu.
  - Tự động đóng bảng chọn sticker ngay sau khi người dùng bấm chọn một nhãn dán để gửi.
- **Tự động Dọn dẹp Thư mục Staging & Sao lưu khi Đóng gói (Packaging Auto-Cleanup)**:
  - Nâng cấp `windows/packaging/package_dist.ps1` và `clean_project.bat`: Tự động dọn dẹp sạch sẽ các thư mục staging tạm `.package-stage-*` và bản sao lưu cũ `dist.previous-*` ngay sau khi đóng gói thành công.
  - Thu hồi hàng Gigabyte dung lượng ổ cứng bị chiếm dụng và loại bỏ triệt để xung đột đồng bộ rác lên OneDrive.
  - Bổ sung cơ chế Pre-packaging sweep tự động xóa các thư mục dở dang nếu các lần đóng gói trước bị gián đoạn đột ngột.
- **Giao diện Input Dock thích ứng màn hình hẹp (Responsive Input Toolbar)**:
  - Tích hợp `LayoutBuilder` cho thanh công cụ dưới ô nhập tin nhắn: Tự động co giãn kích thước nút bấm và padding khi chiều rộng khung chat thu nhỏ (< 360px), loại bỏ hoàn toàn lỗi tràn pixel (`RenderFlex overflowed`) trong chế độ Compact Mode.

### 🐛 Sửa lỗi & Tối ưu hóa
- **Độ chính xác Nhận diện Thực thể (Message Entity Detector)**:
  - Khắc phục lỗi trích xuất URL bị trùng lặp do nhận diện cả domain trần bên trong URL đầy đủ.
  - Nâng cấp biểu thức chính quy nhận diện đường dẫn UNC và Windows Path: Giới hạn các khoảng trắng theo chuẩn hệ thống tệp Windows, không nuốt nhầm các từ ngữ trong câu vào đường dẫn thư mục.
  - Sắp xếp các thẻ Quick Action Chips theo đúng thứ tự xuất hiện của thực thể trong tin nhắn văn bản.
- **Kiểm thử tự động hóa**: Đạt 100% kiểm thử thành công (469 tests passed, 0 failures) trên toàn bộ dự án.

### 📦 Phát hành
- Đồng bộ version `1.7.0+14` trong `pubspec.yaml`, `constants.dart`, `Runner.rc`, `ABOUT.txt`, `README.md`, `USERGUIDE.md`, `RELEASE_NOTES.md`.

## [1.6.1] - 2026-09-28

### 🚀 Nâng cấp & Tính năng mới
- **Tích hợp Nhãn dán Động (Animated Sprite Stickers - Zalo Style)**:
  - Tự động nhận diện và nạp các bộ nhãn dán trong thư mục `assets/sticker/` thông qua `StickerService`.
  - Hỗ trợ ảnh Sprite Sheet động kèm file tọa độ JSON (`spritesheet.json`, `frames.json`) và bộ ảnh từng frame rời.
  - Xây dựng hộp thoại chọn nhãn dán (`StickerPickerDialog`) với tab chuyển bộ sticker, xem trước animation thời gian thực và thanh chọn nhanh ngay cạnh ô nhập liệu.
  - Giao thức P2P truyền tải nhãn dán tức thì giữa các máy trạm trong mạng LAN, hiển thị nhãn dán động mượt mà với `SpriteStickerWidget`.
  - Hỗ trợ hiển thị preview tin nhắn cuối cùng (`[Nhãn dán] / [Sticker] / [贴图]`) trên danh bạ liên hệ và kênh All Users.
- **Sao chép Ảnh Tin nhắn vào Clipboard (Copy Chat Image to Clipboard)**:
  - Bổ sung tùy chọn "Sao chép ảnh" (Copy Image) trực tiếp trên menu ngữ cảnh chuột phải của bong bóng hình ảnh trong khung trò chuyện.
  - Tích hợp chuẩn Pasteboard Windows, trích xuất dữ liệu nhị phân ảnh và dán trực tiếp vào các ứng dụng văn phòng (Word, Excel, Zalo, Paint...).
  - Thông báo Toast phản hồi trực quan khi sao chép thành công hoặc thất bại.
- **Đa ngôn ngữ hóa Toàn diện Tiến độ Quét IP Mạng (Network Scan Status Localization)**:
  - Khắc phục triệt để lỗi hiển thị cứng chuỗi Tiếng Việt khi ứng dụng đang chạy ở ngôn ngữ Tiếng Anh (EN) hoặc Tiếng Trung (ZH).
  - Tách rời các chỉ số kỹ thuật mạng (`sweepDone`, `sweepTotal`, `sweepSent`, `arpCount`, `errorMessage`) ra khỏi chuỗi hiển thị trong `DiscoveryScanState`.
  - Nâng cấp hàm dịch `LanguageProvider.tr` hỗ trợ cả tham số vị trí `{0}`, `{1}` lẫn `%s` và `%d`.
  - Bản địa hóa toàn bộ các trạng thái: Quét subnet UDP/TCP, phát sóng đa tầng NIC, đối soát bảng ARP, chuẩn bị quét, dừng quét, hoàn tất quét và báo cáo lỗi trên cả 3 ngôn ngữ (VI, EN, ZH).
  - Cơ chế Double-Guard Regex Fallback tự động phân tích chuỗi trạng thái nếu số liệu chưa kịp truyền, bảo đảm không bao giờ để lọt chuỗi Tiếng Việt thô sang giao diện EN/ZH.

### 🐛 Sửa lỗi & Tối ưu hóa
- **Độ tin cậy Banner Quét Mạng**: Bảo đảm banner hiển thị tiến độ chính xác theo tỷ lệ phần trăm và số lượng địa chỉ đã quét, không gây giật lag giao diện.
- **Kiểm thử tự động**: Bổ sung bộ Unit Test toàn diện tại `test/scan_localization_test.dart` xác minh tính chính xác của bản địa hóa và cập nhật trạng thái scan.

### 📦 Phát hành
- Đồng bộ version `1.6.1+13` trong `pubspec.yaml`, `constants.dart`, `Runner.rc`, `ABOUT.txt`, `README.md`, `USERGUIDE.md`, `RELEASE_NOTES.md`.

## [1.6.0] - 2026-09-28

### 🚀 Nâng cấp & Tính năng mới
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

### 🐛 Sửa lỗi & Tối ưu hóa
- **Bảo mật Thực thi Lệnh Shell**: Loại bỏ hoàn toàn fallback qua `cmd.exe /c start` với cờ `runInShell: true` trong `QuickActionHelper`. Trên Windows sử dụng trực tiếp lệnh an toàn `Process.run('explorer.exe', [...])` qua ShellExecute của hệ điều hành, chống tuyệt đối nguy cơ command injection.
- **Đồng bộ Từ điển Localization**: Loại bỏ trùng lặp khóa `copyPath` ở cả 3 ngôn ngữ (VI, EN, ZH).
- **Bộ Kiểm thử Tự động**: Bổ sung bộ Unit Test toàn diện tại `test/message_entity_detector_test.dart` bao phủ URLs, emails, số điện thoại, đường dẫn UNC LAN và đường dẫn Windows chứa khoảng trắng.

### 📦 Phát hành
- Đồng bộ version `1.6.0+12` trong `pubspec.yaml`, `constants.dart`, `Runner.rc`, `ABOUT.txt`, `README.md`, `USERGUIDE.md`, `RELEASE_NOTES.md`.

## [1.5.1] - 2026-09-26

### 🚀 Nâng cấp & Tính năng mới
- **Đổi tên nhóm sau khi tạo (Group Renaming & Multi-entry Support)**:
  - Khắc phục hoàn toàn lỗi không thể đổi tên nhóm sau khi tạo nhóm.
  - Bổ sung định tuyến tự động từ `setPeerNickname` sang `renameGroup` khi ID là nhóm, tránh việc bị bỏ qua do nhầm lẫn danh bạ 1-1.
  - Thêm nút đổi tên nhóm (biểu tượng bút chì) trực tiếp trên thanh tiêu đề cuộc trò chuyện nhóm (`ChatViewPanel`) dành cho Quản trị viên.
  - Thêm nút đổi tên nhóm trực tiếp trong phần tiêu đề của hộp thoại xem thành viên nhóm (`GroupMembersDialog`).
  - Bổ sung menu chuột phải (Context Menu) cho thẻ nhóm trong danh sách (`PeerListView`): Đổi tên nhóm, Đổi ảnh đại diện nhóm, Xem danh sách thành viên, Rời nhóm / Giải tán nhóm.
  - Chuẩn hóa hộp thoại chi tiết (`ConversationDetailsPanel`) và hộp thoại đổi nhanh biệt danh (`showQuickNicknameDialog`) hiển thị tiêu đề và gợi ý "Đổi tên nhóm" đa ngôn ngữ (Tiếng Việt, English, 简体中文).
- **Tối ưu Nút Chọn Nhanh Chu kỳ Cập nhật OTA**:
  - Chuyển đổi dropdown list chọn thời gian kiểm tra bản cập nhật sang dạng các nút bấm chọn nhanh trực quan (Quick Selection Chips) theo chuẩn UX Desktop.

### 🐛 Sửa lỗi & Tối ưu hóa
- **Đồng bộ hóa Tên Nhóm Tức thì**: Cập nhật tức thì tên nhóm hiển thị trên thanh tiêu đề và danh bạ ngay khi hoàn tất đổi tên, đồng bộ thời gian thực đến tất cả các thành viên qua giao thức P2P.
- **Bảo toàn Quyền Quản trị Nhóm**: Xác minh chặt chẽ phân quyền quản trị viên, tránh việc người dùng bị mất quyền sửa tên hoặc avatar nhóm khi khởi động lại ứng dụng.

### 📦 Phát hành
- Đồng bộ version `1.5.1+11` trong `pubspec.yaml`, `constants.dart`, `Runner.rc`, `ABOUT.txt`, `README.md`, `USERGUIDE.md`, `RELEASE_NOTES.md`.

## [1.5.0] - 2026-09-26

### 🚀 Nâng cấp & Tính năng mới
- **Kích hoạt Ứng dụng từ xa qua WinRM khi Rung chuông (Remote WinRM App Launch on Buzz)**:
  - Khi đối phương đang offline (tắt ứng dụng hoặc chưa mở), nút Buzz (Rung chuông) tự động thực hiện kích hoạt ứng dụng trên máy đối phương thông qua Windows Remote Management (WinRM).
  - Tự động tạo phiên tương tác thực (`SessionId > 0`) trên desktop người dùng từ xa, tránh trường hợp mở nhầm tiến trình headless trong Session 0.
  - Sau khi WinRM mở app đối phương thành công, ngay khi máy đối phương hoàn tất khởi động và bắt tay mạng LAN, hệ thống tự động gửi rung chuông (`Auto-Buzz`) đến đúng người nhận.
  - **Tối ưu hóa Buzz khi đối phương Online**: Nếu đối phương đang online (hoặc thăm dò TCP port 6475 thành công ngay lập tức), hệ thống chỉ gửi rung chuông thông thường và không kích hoạt hay hiển thị thông báo WinRM không cần thiết.
- **Bảo mật Thông tin Đăng nhập WinRM bằng AES-256**:
  - Mã hóa mật khẩu lưu trữ an toàn bằng chuẩn **AES-256-CBC (`enc:v2:`)** kết hợp IV ngẫu nhiên và khóa liên kết thiết bị (`USERNAME`, `COMPUTERNAME`, `USERPROFILE`).
  - Hỗ trợ cấu hình WinRM mặc định toàn cục (`FT` / `123`) trong Cài đặt và cấu hình riêng lẻ cho từng người dùng qua hộp thoại hồ sơ liên hệ.
  - Cơ chế thực thi kịch bản an toàn qua file script tạm thời trong `%TEMP%` (`powershell.exe -File`), bảo vệ tuyệt đối mật khẩu và mã script khỏi việc bị lộ trong Command Line Arguments của Task Manager / Process Explorer.
- **Nút Chọn Nhanh Chu kỳ Cập nhật OTA (Quick Selection Chips)**:
  - Thay thế droplist chọn chu kỳ cập nhật bằng các **Nút chọn nhanh trực quan 1-chạm** (`Hàng ngày`, `Hàng tuần`, `Hàng tháng`, `Tắt`) kèm icon và highlight trạng thái đang chọn, giúp thao tác mượt mà và trực quan hơn.

### 🐛 Sửa lỗi & Tối ưu hóa
- **Đồng bộ Múi giờ Bong bóng Chat (UTC to Local Time)**: Chuẩn hóa toàn bộ thời gian tin nhắn nhận qua giao thức BeeBEEP sang giờ địa phương máy tính (`.toLocal()`), khắc phục triệt để hiện tượng lệch giờ (ví dụ hiển thị 02:28 thay vì 09:28 trên múi giờ GMT+7).
- **Ổn định Chấm Xanh Trạng thái Online/Offline**: Tối ưu hóa logic gộp danh bạ (`peers` deduplication) và đồng bộ trực tiếp trạng thái online vào đối tượng đang chọn, loại bỏ hoàn toàn hiện tượng chấm xanh bị nhấp nháy hoặc kẹt ở trạng thái offline khi có dữ liệu mạng mới.
- **Xác minh Thiết bị Chặt chẽ (`PendingBuzzTarget`)**: Đảm bảo yêu cầu rung chuông tự động chỉ gửi tới đúng máy tính đích, ngăn ngừa trường hợp nhầm lẫn khi địa chỉ IP bị DHCP cấp phát lại.

### 📦 Phát hành
- Đồng bộ version `1.5.0+10` trong `pubspec.yaml`, `constants.dart`, `Runner.rc`, `ABOUT.txt`, `README.md`, `USERGUIDE.md`, `RELEASE_NOTES.md`.

## [1.4.1] - 2026-09-25

### 🚀 Nâng cấp & Tính năng mới
- **Nhận diện BeeBEEP Chuẩn xác 100% (`isRemoteBeebeep`)**: Khắc phục triệt để lỗi hiển thị nhầm nhãn "Bee" trên các máy chạy JA LAN Messenger (đặc biệt là máy vừa gỡ BeeBEEP như `172.21.174.103`). Bổ sung chữ ký nhận diện `JA_LAN_MESSENGER` vào gói tin bắt tay `BEE-CIAO` và thuật toán phân tích chữ ký avatar/phiên bản để tách bạch tuyệt đối giữa ứng dụng BeeBEEP gốc (C++/Qt) và JA LAN Messenger.
- **Hợp nhất Thiết bị Vật lý & Chống Nhảy Cuộc trò chuyện (Unified Peer & Conversation Engine)**:
  - Tự động nhận diện và gộp các kết nối từ cùng một máy tính (`_isSamePhysicalPeer`), bất kể máy đó có nhiều card mạng / nhiều địa chỉ IP (như Ethernet `172.21.174.103` và Hotspot `192.168.137.231`) hay chạy đồng thời/thay đổi cổng giữa BeeBEEP (6475) và JA Messenger (6477).
  - **Tự động gộp tin nhắn (`_mergeConversations`)**: Mọi tin nhắn gửi/nhận qua các IP, card mạng hoặc cổng khác nhau của cùng một máy đều được gộp chung vào một luồng hội thoại duy nhất theo thứ tự thời gian, lưu bền vững trên đĩa.
  - **Khóa màn hình chat đang mở (`_selectedPeer` stability)**: Giữ nguyên khung chat đang trò chuyện khi đối phương đổi IP, đổi cổng hoặc gửi handshake mới; tin nhắn mới lập tức đồng bộ hiển thị và đánh dấu đã xem, không gây giật lag hay nhảy sang luồng khác.
  - **Hợp nhất Lịch sử Khởi động (`_consolidateLoadedPeersAndConversations`)**: Ngay khi mở ứng dụng, các file lịch sử cũ bị phân tách trước đây tự động được kết nối và hợp nhất thành một thực thể duy nhất trên danh bạ.

### 🐛 Sửa lỗi & Tối ưu hóa
- **Thanh danh bạ Độc bản**: Loại bỏ hoàn toàn tình trạng xuất hiện 2 thẻ trùng lặp cho cùng một đồng nghiệp trên danh bạ bên trái khi máy họ có nhiều card mạng hoặc đổi cổng kết nối.
- **Trạng thái Chọn Bền bỉ (`coordinator.isPeerSelected`)**: Đồng bộ trạng thái highlight của thẻ người dùng trên danh bạ, ngăn chặn hiện tượng mất chọn khi mạng cập nhật ngầm.

### 📦 Phát hành
- Đồng bộ version `1.4.1+9` trong `pubspec.yaml`, `constants.dart`, `Runner.rc`, `ABOUT.txt`, `README.md`, `USERGUIDE.md`, `RELEASE_NOTES.md`.

## [1.4.0] - 2026-09-24

### 🚀 Nâng cấp & Tính năng mới
- **Hàng đợi Ngoại tuyến & Tự động gửi lại (Offline Outbox Queue & Auto-Retry)**: Giải quyết triệt để vấn đề thất lạc tin nhắn khi đối phương ngoại tuyến trong mạng P2P cục bộ. Khi gửi tin nhắn cho peer đang offline (hoặc kết nối TCP bị gián đoạn), tin nhắn tự động chuyển sang trạng thái `failed` và được xếp vào hàng đợi Outbox (`_pendingOfflineMessageIds`).
- **Tự động gửi bù khi Reconnect (`flushPendingOutgoingMessagesForPeer`)**: Ngay khi máy người nhận bật lên, hoàn tất dò tìm và bắt tay mạng LAN (`handlePeerHandshake`), ứng dụng tự động kích hoạt tiến trình gửi bù toàn bộ tin nhắn tồn đọng theo đúng thứ tự thời gian (`timestamp`) với độ giãn cách 40ms chống nghẽn socket.
- **Hỗ trợ Chat nhóm Toàn diện**: Tự động theo dõi các thành viên nhóm đang offline tại thời điểm gửi tin và gửi bù tin nhắn nhóm cho từng thành viên ngay khi họ online trở lại.
- **Giao diện Trực quan & Thao tác Thử lại (UI/UX Retry Controls)**:
  - Thay thế biểu tượng đồng hồ chờ mập mờ bằng icon cảnh báo lỗi `Icons.error_outline_rounded` màu đỏ cam (`#F87171`) kèm chữ **"Thử lại"** trên bong bóng tin nhắn văn bản và thẻ tệp đính kèm.
  - Bấm 1 chạm trực tiếp vào icon lỗi để kích hoạt gửi lại (`retrySendMessage`).
  - Thêm tùy chọn **"Thử lại"** (`retrySend`) trực tiếp vào Menu chuột phải (Context menu) của tin nhắn.
  - Tooltip giải thích nguyên nhân rõ ràng: *"Chưa gửi được (Người nhận ngoại tuyến). Nhấn để thử lại."*
- **Độ bền dữ liệu qua các phiên khởi động**: Tự động phục hồi trạng thái tin nhắn và chuẩn hóa các tin dở dang (`sending`) khi tắt máy thành `failed`, nạp vào Outbox để sẵn sàng gửi lại khi khởi động lại app.
- **Đa ngôn ngữ Trọn vẹn**: Bổ sung đầy đủ chuỗi giao diện cho cả 3 ngôn ngữ: Tiếng Việt, Tiếng Anh và Tiếng Trung.

### 📦 Phát hành
- Đồng bộ version `1.4.0+8` trong `pubspec.yaml`, `constants.dart`, `Runner.rc`, `ABOUT.txt`, `README.md`, `USERGUIDE.md`, `RELEASE_NOTES.md`.

## [1.3.1] - 2026-09-24

### 🚀 Nâng cấp & Tính năng mới
- **Tăng tốc & Ổn định hóa Nhận diện Subnet Mask trên Windows (`netsh`)**: Chuyển đổi phương thức truy vấn Subnet Mask từ PowerShell sang lệnh native `netsh interface ipv4 show addresses`, giảm thời gian truy vấn từ >5000ms xuống chỉ **~5ms**. Loại bỏ hoàn toàn lỗi timeout và lỗi chặn chính sách `Restricted ExecutionPolicy` trên các dòng Mini PC / máy cấu hình thấp, đảm bảo phát hiện chính xác các dải Supernet /21 (`255.255.248.0`) và quét toàn diện đủ 2046 hosts trên 8 dải con.
- **Bộ công cụ Kiểm tra & Chẩn đoán Mạng Độc lập (`verify_scan.bat` & `verify_scan.ps1`)**: Cung cấp công cụ chạy 1-click không cần cài Flutter/Dart SDK, tự động chẩn đoán cấu hình card mạng, Subnet Mask, cổng tường lửa (TCP 6475, UDP 36475), đọc file cấu hình preferences và đo đạc kết nối thời gian thực tới toàn bộ các subnet slice.
- **Phân quyền Quản trị Nhóm chuẩn Zalo/Telegram**: Chỉ Trưởng nhóm (Creator/Admin) mới có quyền giải tán nhóm chat; thành viên thông thường chỉ có tùy chọn rời nhóm, ngăn chặn việc thành viên thường vô tình xóa nhóm chung.

### 🐛 Sửa lỗi & Tối ưu hóa
- **Khôi phục Kiểu dáng Avatar Tròn Mặc định & Màu Nền Mờ Tinh Tế**: Đưa `isCircle: true` làm mặc định trên toàn bộ ứng dụng; khôi phục màu nền mờ `avatarColor.withValues(alpha: 0.2)` kèm viền màu đồng bộ `effectiveColor.withValues(alpha: 0.5)` và chữ cái đầu (Initials) / preset icon hiển thị trang nhã, không còn hiện tượng hình vuông khuyết góc hay nền màu đặc chói mắt.
- **Đồng bộ Avatar Danh bạ & Cố định Ảnh Đại diện JA AI**: Sử dụng `AppAvatar` thống nhất cho toàn bộ danh bạ bạn bè và nhóm; cố định nạp ảnh gốc `assets/ai_avatar.png` trong khung trò chuyện JA AI.

### 📦 Phát hành
- Đồng bộ version `1.3.1+7` trong `pubspec.yaml`, `constants.dart`, `Runner.rc`, `ABOUT.txt`, `install.bat`, `installer.iss`, `README.md`, `USERGUIDE.md`, `RELEASE_NOTES.md`.

## [1.3.0] - 2026-09-22

### 🚀 Nâng cấp & Tính năng mới
- **Đồng bộ Avatar cá nhân qua mạng LAN (Personal Avatar LAN Sync)**: Tự động nén ảnh đại diện thành thumbnail kích thước 96x96 px Base64 (~2-4 KB), đính kèm vào handshake `BEE-CIAO` và truyền thời gian thực qua gói tin `BEE-USER` tới các kết nối TCP hiện hữu. Hiển thị tức thì ảnh đại diện của đồng nghiệp trên danh bạ, thanh tiêu đề hội thoại và bong bóng tin nhắn.
- **Tùy biến & Đồng bộ Avatar Nhóm (Group Avatar)**: Hỗ trợ chọn avatar nhóm bằng icon preset phong phú hoặc tải ảnh từ máy tính kèm bảng màu nền tùy biến; lưu trữ metadata định dạng `ja-group-v1:avatar:...` và đồng bộ qua LAN với gói `BEE-GROU` khi tạo nhóm hoặc cập nhật. Cho phép thay đổi avatar nhóm trực tiếp trong `CreateGroupDialog`, `ConversationDetailsPanel` và `GroupMembersDialog`.
- **Chống mở trùng ứng dụng (Single-Instance Mutex & Focus Bring)**: Tích hợp Win32 Mutex (`JA_LAN_MESSENGER_SINGLE_INSTANCE_MUTEX`) trong C++ native runner (`main.cpp` & `flutter_window.cpp`). Khi người dùng mở trùng ứng dụng, tiến trình mới sẽ tự động kích hoạt, khôi phục từ khay hệ thống và đưa cửa sổ đang chạy lên trên cùng màn hình, ngăn ngừa triệt để lỗi xung đột chiếm giữ cổng mạng `36475` / `6475`.
- **Huy hiệu số tin nhắn chưa đọc trên Khay hệ thống (Tray Icon Badge Counter)**: Tự động vẽ số tin nhắn chưa đọc dạng huy hiệu tròn đỏ nổi bật trực tiếp lên icon khay hệ thống Windows thông qua `TrayBadgeService` (sử dụng Win32 GDI & dynamic canvas icon), cập nhật tức thì khi có tin nhắn mới hoặc khi người dùng xem cuộc trò chuyện.
- **Nâng cấp toàn diện Nhóm chat (Group Chat Lifecycle & UX)**:
  - Tự động lọc bỏ chính người tạo khỏi danh sách chọn thành viên khi tạo nhóm trong `CreateGroupDialog`.
  - Nhấp trực tiếp vào dòng số lượng thành viên trên tiêu đề nhóm để mở ngay danh sách thành viên chi tiết (`GroupMembersDialog`).
  - Hỗ trợ cơ chế giải tán nhóm triệt để (đồng bộ thông báo giải tán tới tất cả thành viên trên LAN qua gói `BEE-GROU`), rời nhóm an toàn và quản trị viên đuổi thành viên.
  - Tích hợp chỉ báo đang soạn thảo (Typing Indicator) và thông báo tin nhắn mới có âm thanh/toast nổi trong nhóm tương tự tin nhắn cá nhân.

### 🐛 Sửa lỗi & Tối ưu hóa
- **Tối ưu hóa băng thông truyền Avatar**: Giới hạn kích thước ảnh đại diện nén Base64 giúp gói tin handshake nhẹ nhàng, kết nối nhanh chóng mà không làm trễ quá trình quét mạng.
- **Độ ổn định vòng đời nhóm chat**: Tự động chuyển hội thoại an toàn khi nhóm bị giải tán hoặc người dùng bị xóa khỏi nhóm, xóa sạch cache tin nhắn tạm thời mà không gây lỗi giao diện.

### 📦 Phát hành
- Đồng bộ version `1.3.0+6` trong `pubspec.yaml`, `constants.dart`, `Runner.rc`, `ABOUT.txt`, `install.bat`, `installer.iss`, `README.md`, `USERGUIDE.md`, `RELEASE_NOTES.md`.

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
