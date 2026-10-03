# Hướng dẫn sử dụng JA LAN Messenger v1.8.0

Ứng dụng nhắn tin và truyền tập tin ngang hàng (P2P) tốc độ cao dành riêng cho mạng cục bộ văn phòng (LAN), không cần máy chủ trung gian (Serverless), tích hợp Trợ lý Trí tuệ Nhân tạo JA-AI.

---

## 1. Yêu cầu hệ thống & Cài đặt / Gỡ cài đặt
- **Hệ điều hành:** Windows 10 (bản 1809 trở lên) hoặc Windows 11 (64-bit).
- **Cài đặt chuẩn (Khuyên dùng):**
  1. Tải về gói phát hành `JA_LAN_Messenger_v1.8.0_Windows_x64.zip` và giải nén.
  2. Nhấp đúp chạy file **`install.bat`**. Ứng dụng sẽ tự động được cài đặt vào `%LOCALAPPDATA%\Programs\JA_LAN_Messenger` (không đòi hỏi quyền Administrator).
  3. Phím tắt sẽ tự động được tạo ra **Màn hình chính (Desktop)** và **Menu Start**.
  4. Ứng dụng được đăng ký chính thức vào Windows, có thể quản lý qua **Control Panel** hoặc **Settings**.
  - Thoát bản đã cài trước khi cài lại. Bộ cài không cưỡng bức đóng app; giữ cấu hình và sao lưu file chương trình vào `%TEMP%` trước khi thay thế.
- **Chạy trực tiếp dạng Portable (Không cần cài đặt):**
  - Mở thư mục giải nén, nhấp đúp chạy trực tiếp `ja_lan_messenger.exe` (hoặc qua `debug.bat` để xem console log).
- **Gỡ cài đặt (Uninstall):**
  - Mở **Control Panel (`Programs and Features`)** hoặc **Windows Settings (`Installed apps`)** -> tìm `JA LAN Messenger` -> chọn **Uninstall**.
  - Hoặc chạy trực tiếp file **`uninstall.bat`** trong thư mục cài đặt / Start Menu.
  - Bộ gỡ cài đặt cho phép tùy chọn giữ lại hoặc xóa lịch sử trò chuyện cá nhân.
  - `/silent` luôn giữ dữ liệu. Cần giữ `uninstall.ps1` đi kèm; bộ gỡ chỉ xóa thư mục cài đã đăng ký, không xóa thư mục portable hoặc mã nguồn. Lựa chọn xóa dữ liệu cũng xóa logs tại `%LOCALAPPDATA%\JA_LAN_Messenger`.
- **Tường lửa Windows Defender:** Trong lần chạy đầu tiên, chọn **"Allow access" (Cho phép truy cập)** cho cả mạng Private và Public để ứng dụng có thể lắng nghe và nhận diện thiết bị trên mạng LAN qua cổng UDP 36475 và TCP 6475/6476.

---

## 2. Các tính năng chính

### 2.1. Tự động tìm kiếm & Thêm bạn qua IP thông minh
- Khi khởi động, ứng dụng tự động phát sóng gói tin UDP Discovery trên cổng `36475` để tìm các máy tính khác trong cùng dải mạng LAN.
- **Thêm bạn qua IP thông minh:** Nhấn biểu tượng `+` (Thêm IP) trên thanh công cụ tìm kiếm:
  - **Gợi ý dải mạng tự động 2 octet:** Ứng dụng tự động phát hiện IP của card mạng đang kết nối và viết sẵn 2 số đầu tiên (ví dụ `172.21.` hoặc `192.168.`), con trỏ nhấp nháy ngay sau dấu chấm thứ 2 để bạn gõ tiếp 2 số còn lại (ví dụ `.100.25`) rồi nhấn Enter.
  - **Thanh Chip gợi ý:** Nếu máy kết nối nhiều mạng (dây xưởng + Wi-Fi), các chip như `[ 172.21. ]`, `[ 192.168. ]` xuất hiện để bạn đổi dải mạng chỉ với 1 cú click.
  - **Thông báo kết nối thành công:** Nút kết nối xoay vòng tiến trình trong lúc bắt tay mạng; khi kết nối thành công, hộp thoại đóng, Toast báo thành công nổi lên và ứng dụng tự động mở khung chat ngay.
  - **Ưu tiên Bạn mới & Huy hiệu:** Bạn mới được tự động đưa lên vị trí cao nhất danh bạ (ngay sau các mục đã ghim) kèm huy hiệu `[Bạn mới]` màu xanh ngọc bích. Huy hiệu tự động biến mất khi bạn gửi tin nhắn trò chuyện đầu tiên hoặc qua chuột phải chọn `Bỏ đánh dấu bạn mới`.
  - **Lưu danh bạ ngoại tuyến:** Nếu máy đồng nghiệp chưa bật app, bạn có thể chọn `Lưu vào danh bạ (ngoại tuyến)` để lưu trước.

### 2.2. Trò chuyện, Rung chuông & Khởi chạy từ xa qua WinRM
- **Nhắn tin tức thì:** Gõ tin nhắn và bấm `Enter` để gửi (`Shift + Enter` để xuống dòng).
- **Rung chuông (Buzz / Nudge):**
  - Khi đối phương đang **Online**: Nhấn nút chuông để rung chuông thông thường tức thì.
  - Khi đối phương đang **Offline**: Nút Buzz tự động kích hoạt khởi chạy ứng dụng từ xa trên máy đối phương thông qua dịch vụ WinRM (mặc định user/pass: `FT`/`123`, mật khẩu lưu trữ mã hóa AES-256 an toàn và có thể cấu hình riêng cho từng đồng nghiệp). Khi ứng dụng trên máy đối phương bật lên và bắt tay mạng thành công, hệ thống sẽ tự động rung chuông ngay.
- **Đính kèm tập tin lớn:** Nhấn biểu tượng kẹp giấy hoặc dán (`Ctrl + V`) ảnh/tệp từ Clipboard. File được stream trực tiếp qua kết nối TCP cổng `6476` với tốc độ tối đa của switch mạng mà không ngốn RAM.

### 2.3. Trích dẫn & Ghim tin nhắn (Quote & Pin)
- **Trích dẫn tin nhắn (Reply/Quote):** Rê chuột lên tin nhắn bất kỳ, nhấn biểu tượng trích dẫn để trích dẫn tin nhắn đó vào thanh soạn thảo. Khi người nhận hoặc bạn nhấp vào khối trích dẫn, danh sách chat sẽ tự động cuộn đến vị trí tin nhắn gốc.
- **Ghim tin nhắn (Pin Messages):** Nhấn biểu tượng Ghim để ghim các thông báo quan trọng lên đầu cuộc trò chuyện. Thanh ghim hỗ trợ hiển thị nhiều tin nhắn kèm bộ đếm và chuyển đổi nhanh.

### 2.4. Trợ lý AI Cục bộ (JA-AI Assistant)
- **Tích hợp mô hình AI nội bộ:** Kết nối với máy chủ Ollama / JA-AI Engine qua mạng LAN hoặc máy local (`http://127.0.0.1:11434` hoặc IP máy chủ AI).
- **Phát hiện mô hình tự động (Dynamic Model Detection):**
  - Trong **Cài đặt > Trợ lý JA-AI**: Nhấn nút **"Kiểm tra kết nối"** hoặc icon **Làm mới**, hệ thống sẽ tự động quét danh sách toàn bộ model đang có trên server (`/api/tags`).
  - Phân loại trực quan: Mô hình Thị giác (👁️ Vision), Suy nghĩ/Lập luận (🧠 Thinking), Lập trình (💻 Coder).
  - Khung chat AI hỗ trợ chọn nhanh model từ popup trên thanh tiêu đề và nút Làm mới tức thì.
  - Tự động chuyển đổi mô hình (Auto-switch) khi đổi máy chủ AI mà model cũ không tồn tại.
- **Khối suy nghĩ (Thought Process):** Đối với các model hỗ trợ Thinking (như `Qwen 3.5`, `DeepSeek R1`), bạn có thể bật/tắt chế độ Thinking và xem quá trình suy luận chi tiết qua khối accordion thu gọn.

### 2.5. Tinh chỉnh hiệu ứng kính mờ (Live Glass Tuning)
- Trong **Cài đặt > Cài đặt nâng cao > Hiệu ứng kính mờ**:
  - **Card Blur & Card Opacity:** Điều chỉnh độ mờ và độ trong suốt của các thẻ danh bạ, khung chat.
  - **Dialog Blur & Dialog Opacity:** Điều chỉnh độ mờ và độ trong suốt của các hộp thoại cài đặt.
  - Hỗ trợ xem trước trực tiếp (Live Preview) và khôi phục cài đặt gốc an toàn khi đóng mà không lưu.
- Giao diện Dark mode được tinh chỉnh tối ưu, độ tương phản cao, dễ nhìn trong môi trường thiếu sáng.

### 2.6. Quản lý Card mạng & Lịch sử trò chuyện
- **Chọn Card mạng:** Trong Cài đặt, bạn có thể tích chọn các card mạng mong muốn hoặc bỏ chọn card ảo (VMware, VirtualBox, WSL) để tối ưu tốc độ quét mạng LAN.
- **Lưu trữ lịch sử an toàn:** Cơ chế ghi đĩa nguyên tử (atomic file write) bảo vệ lịch sử trò chuyện không bị hỏng file hay mất dữ liệu khi tắt máy đột ngột.

### 2.7. Tự động cập nhật OTA qua mạng nội bộ (Over-The-Air Update)
- **Tự động quét bản mới:** Tích hợp kiểm tra cập nhật qua thư mục mạng chia sẻ nội bộ (SMB/UNC, ví dụ: `\\10.81.141.226\temp\FBT\JA_PROJECT\JA_Update\JA_LAN_Messenger`).
- **Nút chọn nhanh chu kỳ (Quick Selection Buttons):** Trong **Cài đặt > Tab Cập nhật OTA**, bạn có thể chọn nhanh tần suất bằng các nút trực quan 1-chạm: *Hàng ngày, Hàng tuần, Hàng tháng, hoặc Tắt*.
- **Cấu hình độc lập:** Có thể cấu hình trực tiếp trong app hoặc qua file `update_config.json` đặt cạnh ứng dụng.
- **Cập nhật 1-chạm:** Khi có bản cập nhật mới, thanh tiêu đề hiển thị huy hiệu xanh lá `vX.Y.Z`. Bấm vào để mở hộp thoại xem Release Notes và bấm "Cập nhật ngay" để tự động tải, giải nén và khởi động lại phiên bản mới.

### 2.8. Đính kèm nhiều tệp & Hộp thoại Soi tập tin Đa năng Bento (Bento Smart File Inspector)
- **Gắn tệp vào khung soạn thảo:** Dán (`Ctrl + V`) ảnh/file từ clipboard hoặc chọn từ nút kẹp giấy. Các tệp đính kèm sẽ hiển thị trực tiếp thành các thẻ thu nhỏ ngay trên thanh nhập liệu, cho phép đính kèm nhiều tệp cùng lúc trước khi bấm gửi.
- **Xem trước thông minh & Soi tập tin đa năng (Smart File Inspector):**
  - **Đóng nhanh linh hoạt:** Nhấp chuột ra ngoài cửa sổ modal (backdrop tap-to-dismiss) hoặc bấm phím `Esc` để đóng ngay lập tức, không bắt buộc phải bấm nút X.
  - **Lưới thông tin Bento:** Hiển thị chi tiết MIME type, kích thước định dạng chuẩn, thời gian sửa đổi, quyền tệp (Read/Write/Execute) và ứng dụng mặc định của hệ thống Windows được đăng ký để mở tệp.
  - **Duyệt tệp nén ZIP thuần Dart:** Đối với tệp `.zip`, `.jar`, `.apk`, người dùng có thể xem danh sách cấu trúc tệp tin/thư mục bên trong, kích thước nén, kích thước gốc và tỷ lệ nén trực tiếp mà không cần giải nén ra đĩa.
  - **Xem cấu trúc bảng tính Excel:** Đối với tệp `.xlsx`, trích xuất số lượng trang tính (Sheet count), tên danh sách từng Sheet và kích thước nén.
  - **Băm toàn vẹn SHA-256:** Tự động tính toán mã băm SHA-256 kèm nút 1-chạm sao chép nhanh (`Ctrl + Shift + C`) để kiểm tra tính toàn vẹn tệp tin.
  - **Trình soi nhị phân Hex Dump:** Xem trước 512 byte đầu tiên theo chuẩn Hex Editor (Offset | Hex | ASCII) với phông Monospace.
  - **Sao chép tệp vật lý vào Clipboard:** Bấm nút sao chép file hoặc nhấn `Ctrl + C` để copy trực tiếp tệp thật vào khay nhớ tạm Windows, sau đó có thể paste (`Ctrl + V`) ngay vào thư mục Explorer hay ứng dụng bất kỳ.
  - **Phím tắt hỗ trợ:** `Enter` hoặc `Ctrl + O` để mở tệp bằng ứng dụng mặc định, `Ctrl + C` copy tệp, `Ctrl + Shift + C` copy mã hash SHA-256, `Esc` đóng hộp thoại.

### 2.9. Bộ gõ tiếng Việt / tiếng Trung tích hợp (Built-in IME)
- **Hỗ trợ gõ trực tiếp:** Tích hợp bộ gõ **Telex (Tiếng Việt)** và **Pinyin (Tiếng Trung)** ngay trong ứng dụng mà không cần cài đặt phần mềm ngoài.
- **Tự động thích ứng:** Nút chuyển đổi nhanh ở góc phải khung chat, tự động tránh xung đột khi phát hiện bộ gõ hệ thống (Unikey, EVKey, Microsoft IME).

### 2.10. Tối ưu hóa hiệu năng & Chế độ Lite (Mini PC / Máy cấu hình thấp)
- **Tự động nhận diện cấu hình:** Ứng dụng tự động đọc thông số CPU/GPU máy tính để thiết lập mức đồ họa phù hợp nhất (`Ultra`, `Medium`, `Lite`).
- **Chế độ Lite siêu mượt:** Dành riêng cho các máy tính văn phòng, Mini PC (như Intel N100, Celeron): tắt hoàn toàn các bộ lọc blur tốn tài nguyên GPU, mang lại tốc độ phản hồi tức thì và cuộn mượt mà.
- **Tùy chỉnh thủ công:** Trong **Cài đặt > Tab Cài đặt nâng cao > Mục Hiệu năng & Đồ họa**, người dùng có thể xem thẻ cấu hình máy và tự do lựa chọn giữa các mức hiệu năng.
- **Menu trạng thái Showcase:** Menu chuyển đổi trạng thái người dùng (Online / Away / Busy) được nâng cấp kính mờ đục cao cấp chống xuyên thấu, hiển thị rõ ràng và đẹp mắt.

### 2.11. Tùy biến & Đồng bộ Avatar cá nhân & Avatar nhóm
- **Avatar cá nhân:** Nhấp vào ảnh đại diện của bạn ở thanh điều hướng bên trái hoặc trong mục **Cài đặt** để mở hộp thoại tùy chọn Avatar. Bạn có thể chọn icon preset từ thư viện hoặc tải ảnh từ máy tính. Ảnh sẽ được tự động nén tối ưu (96x96 px Base64) và đồng bộ qua mạng LAN tới tất cả đồng nghiệp trong văn phòng.
- **Avatar nhóm chat:** Khi tạo nhóm mới hoặc chỉnh sửa nhóm hiện có (trong bảng Thông tin hội thoại hoặc Danh sách thành viên), bạn có thể chọn ảnh đại diện riêng cho nhóm bằng ảnh tùy chọn hoặc icon theo chủ đề kèm màu nền nổi bật. Thay đổi được đồng bộ tức thì tới tất cả thành viên trong nhóm qua mạng LAN.

### 2.12. Huy hiệu Khay hệ thống & Khởi động đơn nhất (Single-Instance)
- **Huy hiệu số tin nhắn chưa đọc:** Khi có tin nhắn mới mà ứng dụng đang thu nhỏ hoặc ẩn xuống khay hệ thống, biểu tượng app dưới khay Taskbar sẽ tự động vẽ thêm huy hiệu tròn đỏ hiển thị số lượng tin nhắn chưa đọc thời gian thực.
- **Chống mở trùng ứng dụng:** Tích hợp cơ chế Win32 Mutex giúp bảo vệ ứng dụng không bị chạy nhiều tiến trình cùng lúc gây xung đột cổng mạng LAN. Nếu bạn nhấp mở lại ứng dụng khi đang chạy, cửa sổ hiện hành sẽ tự động hiển thị lên trên cùng màn hình.

### 2.13. Quản lý nhóm trò chuyện nâng cao
- **Tạo nhóm thông minh:** Hộp thoại tạo nhóm tự động lọc bỏ tên của bạn, cho phép chọn nhanh các thành viên đang trực tuyến trong mạng LAN.
- **Xem thành viên nhóm:** Nhấp trực tiếp vào dòng số lượng thành viên (ví dụ: `3 thành viên`) trên thanh tiêu đề nhóm để mở ngay danh sách chi tiết các thành viên.
- **Giải tán & Rời nhóm:** Quản trị viên (người tạo nhóm) có quyền giải tán nhóm, hệ thống sẽ tự động đồng bộ lệnh giải tán tới tất cả thành viên còn lại trên mạng LAN. Thành viên cũng có thể chủ động rời nhóm an toàn bất cứ lúc nào.
- **Chỉ báo đang gõ & Thông báo nhóm:** Khi thành viên trong nhóm đang soạn tin nhắn, chỉ báo soạn thảo sẽ hiển thị ngay dưới đáy khung chat. Tin nhắn nhóm mới cũng phát âm thanh và toast thông báo tương tự tin nhắn cá nhân.

### 2.14. Hàng đợi Ngoại tuyến & Tự động gửi lại (Offline Outbox & Auto-Retry)
- **Gửi tin nhắn khi người nhận đang tắt máy:** Tin nhắn chưa thể chuyển phát sẽ tự động chuyển sang trạng thái lỗi và được lưu an toàn vào hàng đợi Outbox trên máy của bạn.
- **Tự động gửi bù (Auto-Retry):** Ngay khi máy người nhận bật lên và kết nối vào mạng LAN, ứng dụng sẽ tự động kích hoạt gửi bù toàn bộ tin nhắn tồn đọng theo đúng thứ tự thời gian mà không cần bạn phải thao tác lại.
- **Thao tác Thử lại trực quan (Manual Retry):** Bấm trực tiếp vào biểu tượng cảnh báo lỗi màu đỏ cam trên tin nhắn, hoặc nhấp chuột phải chọn **"Thử lại"** (`Retry`) để kích hoạt gửi lại bất kỳ lúc nào.
- **Hỗ trợ Chat nhóm:** Tin nhắn gửi vào nhóm khi có thành viên ngoại tuyến sẽ được lưu riêng và tự động gửi bù cho thành viên đó ngay khi họ online trở lại.

### 2.15. Toggle Khay Hệ Thống & Tiện Ích Thông Minh Bong Bóng Chat
- **Ẩn / Hiện ứng dụng 1-chạm (System Tray Toggle):** Nhấp chuột trái vào biểu tượng khay hệ thống (System Tray) để toggle nhanh cửa sổ: tự động ẩn vào khay nếu đang ở tiền cảnh, hoặc khôi phục và đưa lên trước màn hình nếu đang thu nhỏ hay nằm dưới các cửa sổ khác.
- **Bôi đen lựa chọn & Sao chép linh hoạt (Selectable Chat Text):** Bạn có thể dùng chuột bôi đen bất kỳ đoạn chữ nào trong tin nhắn để sao chép (Ctrl+C hoặc menu chuột phải), không bị bắt buộc phải copy toàn bộ tin nhắn.
- **Tự động nhận diện thực thể thông minh (Entity Detection):** Hệ thống tự động phát hiện các liên kết web (`https://...`, `www...`), số điện thoại, email và đường dẫn mạng LAN (`\\server\share\...`) / file ổ đĩa (`C:\...`) có chứa khoảng trắng.
- **Thanh tiện ích nhanh Bento Glassmorphic (Smart Action Chips):** Các nút chip bo tròn kính mờ hiển thị ngay dưới tin nhắn:
  - **Chuột trái:** Thực thi hành động tương ứng (Mở web bằng trình duyệt mặc định, mở Explorer chọn file/thư mục, soạn email, gọi điện).
  - **Chuột phải hoặc bấm icon copy:** Sao chép nhanh giá trị vào Clipboard kèm thông báo nổi.
- **Thu gọn tiêu đề thông minh khi mở Thông tin hội thoại (Responsive Header):** Khi mở bảng bên phải, tiêu đề tự động thu gọn, chuyển chấm trạng thái online/offline lên Avatar và bật cuộn chữ marquee mượt mà cho nickname dài, tránh bị cắt ngắn tên đối phương.

### 2.16. Bộ Nhãn Dán Động (Stickers Sprite) & Sao Chép Ảnh Tin Nhắn
- **Nhãn dán động Zalo (Animated Sprite Stickers):**
  - Nhấp vào biểu tượng mặt cười (Stickers) cạnh ô nhập liệu để mở bảng chọn nhãn dán.
  - Tự động nạp toàn bộ các bộ sticker đặt trong thư mục `assets/sticker/` (hỗ trợ ảnh Sprite Sheet động với file tọa độ JSON hoặc bộ frame rời).
  - Nhấp chọn nhãn dán để gửi ngay lập tức qua mạng LAN tới đối phương. Nhãn dán phát chuyển động animation mượt mà trên khung trò chuyện.
  - Tin nhắn cuối cùng trên danh bạ liên hệ tự động hiển thị nhãn `[Nhãn dán]` / `[Sticker]` / `[贴图]` tương ứng ngôn ngữ đang chọn.
- **Sao chép ảnh trong tin nhắn vào Clipboard (Copy Image):**
  - Nhấp chuột phải vào bất kỳ hình ảnh nào trong bong bóng chat và chọn **"Sao chép ảnh"** (`Copy Image`). Dữ liệu ảnh sẽ được lưu ngay vào Clipboard hệ điều hành để dán (`Ctrl + V`) sang Word, Excel, Paint, Zalo mà không cần lưu file ra ổ đĩa.
- **Đa ngôn ngữ tiến độ quét IP mạng (Network IP Sweep Localization):**
  - Thanh trạng thái quét mạng hiển thị đầy đủ tiến độ (UDP/TCP, đa card mạng NIC, đối soát ARP) chuẩn xác theo ngôn ngữ bạn chọn (Tiếng Việt, English, 简体中文).
- **Khôi phục vị trí cuộn & ý định xem tin nhắn (Conversation Scroll Restoration):**
  - Tự động lưu vị trí đọc tin nhắn và ý định xem lịch sử của bạn trên từng cuộc trò chuyện.
  - Khi bạn khởi động lại ứng dụng hoặc chuyển đổi qua lại giữa các bạn chat, màn hình tự động dừng đúng vị trí bạn đang đọc, không bị tình trạng tự động nhảy mất dấu xuống cuối trang.
- **Xác nhận đã đọc theo khả năng nhìn thấy thực tế (Visible-Message Read Receipts):**
  - Tin nhắn chỉ được đánh dấu là "đã đọc" khi cửa sổ đang mở active và tin nhắn thực sự nằm trong tầm mắt của bạn tối thiểu 0.5 giây. Nếu app đang bị thu nhỏ hoặc che khuất, tin nhắn vẫn giữ nguyên trạng thái chưa đọc.
- **Nhắc nhở tin nhắn chưa đọc & Nhấp nháy Taskbar Windows (Persistent Unread Attention):**
  - Biểu tượng khay hệ thống (Tray) tự động luân phiên nhấp nháy và thanh Taskbar Windows nhấp nháy liên tục khi có tin nhắn chưa đọc cho đến khi bạn bấm vào xem.

### 2.17. Tối ưu hóa Năng lượng & Tải GPU Thông minh (Desktop Power & GPU Optimizer)
- **Tự động giảm tải GPU về 0% khi không thao tác:**
  - Khi bạn chuyển sang làm việc trên cửa sổ khác (Inactive/Blur) hoặc thu nhỏ app xuống Taskbar/Tray, toàn bộ hiệu ứng chuyển màu động nền kính mờ (`MeshOrb`) sẽ được tạm dừng ngay lập tức. GPU máy tính sẽ trở về mức 0% lý tưởng.
  - **Bảo toàn hướng chạy khi mở lại:** Khi bạn bấm vào ứng dụng, hoạt ảnh tiếp tục chạy tiếp từ vị trí và theo đúng chiều tiến/lùi trước đó mà không bị giật hay nhảy hình.
- **Chế độ Ngủ Rảnh Tay (Idle Sleep Mode):**
  - Khi cửa sổ app vẫn mở trên màn hình nhưng bạn không di chuột hay gõ phím trong một khoảng thời gian, app sẽ tự động đưa hiệu ứng nền vào trạng thái ngủ để tiết kiệm điện và làm mát máy tính.
  - Ngay khi bạn di chuột hoặc bấm phím, app sẽ thức dậy ngay lập tức.
- **Tùy chỉnh trong Cài đặt:**
  - Mở **Cài đặt hệ thống** -> Cuộn tới thẻ **"TỐI ƯU NĂNG LƯỢNG & GPU (POWER OPTIMIZER)"**:
    - Bật hoặc tắt tính năng **Chế độ ngủ rảnh tay khi không thao tác**.
    - Lựa chọn thời gian chờ thông minh: **12 giây (Mặc định)**, **30 giây**, hoặc **60 giây**.

### 2.18. Hiển thị Tên Ứng dụng Chuẩn & Nhận diện Windows (Consistent Windows Branding & Metadata)
- **Tên hiển thị chuyên nghiệp:** Cửa sổ ứng dụng, thanh Taskbar, trình chuyển cửa sổ `Alt + Tab`, và trình quản lý tác vụ Windows Task Manager luôn hiển thị tên chính thức **"JA LAN Messenger"** (phát hành bởi JA Tech) thay vì tên file thực thi kỹ thuật `ja_lan_messenger.exe`.
- **Tương thích toàn diện:** Áp dụng đồng bộ trên cả Windows 10 (Aero Glass blur) và Windows 11 (Acrylic/Mica), đảm bảo đầy đủ thông tin mô tả chi tiết (File Description, Product Name, Copyright) trong thuộc tính tệp nhị phân.

---

## 3. Cấu hình cổng mạng mặc định
| Cổng | Giao thức | Chức năng |
| :--- | :--- | :--- |
| `36475` | UDP Broadcast & Multicast | Dò tìm và thông báo thiết bị trong mạng LAN |
| `6475` | TCP Direct | Kết nối trò chuyện, gửi handshake, ACK, rung chuông |
| `6476` | TCP Binary Stream | Truyền nhận tập tin tốc độ cao |

---

## 4. Khắc phục sự cố thường gặp
1. **Không nhìn thấy máy đồng nghiệp:**
   - Kiểm tra xem hai máy có cùng chung một mạng LAN/WiFi hay không.
   - Kiểm tra Windows Defender Firewall: đảm bảo đã cho phép `ja_lan_messenger.exe` truy cập mạng.
   - Thử bấm nút **"Quét lại"** hoặc nhập trực tiếp IP của máy đồng nghiệp qua nút `+`.
2. **Không kết nối được với JA-AI Assistant:**
   - Kiểm tra máy chủ Ollama đang chạy và mở cổng (ví dụ: `OLLAMA_HOST=0.0.0.0:11434`).
   - Nhập đúng URL vào Cài đặt và bấm **"Kiểm tra kết nối"**.
