# Hướng dẫn sử dụng JA LAN Messenger v1.2.1

Ứng dụng nhắn tin và truyền tập tin ngang hàng (P2P) tốc độ cao dành riêng cho mạng cục bộ văn phòng (LAN), không cần máy chủ trung gian (Serverless), tích hợp Trợ lý Trí tuệ Nhân tạo JA-AI.

---

## 1. Yêu cầu hệ thống & Cài đặt / Gỡ cài đặt
- **Hệ điều hành:** Windows 10 (bản 1809 trở lên) hoặc Windows 11 (64-bit).
- **Cài đặt chuẩn (Khuyên dùng):**
  1. Tải về gói phát hành `JA_LAN_Messenger_v1.2.1_Windows_x64.zip` và giải nén.
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

### 2.1. Tự động tìm kiếm & Kết nối P2P
- Khi khởi động, ứng dụng tự động phát sóng gói tin UDP Discovery trên cổng `36475` để tìm các máy tính khác trong cùng dải mạng LAN.
- **Thêm máy thủ công:** Nếu máy đồng nghiệp ở lớp mạng (subnet) khác hoặc kết nối qua VPN, nhấn nút biểu tượng `+` (Thêm IP) trên danh bạ và nhập địa chỉ IPv4 của máy đó.

### 2.2. Trò chuyện & Truyền tập tin tốc độ cao
- **Nhắn tin tức thì:** Gõ tin nhắn và bấm `Enter` để gửi (`Shift + Enter` để xuống dòng).
- **Rung chuông (Nudge):** Nhấn nút biểu tượng chuông để gửi tín hiệu chú ý tức thì tới máy đối phương.
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
- **Tự động quét bản mới:** Tích hợp kiểm tra cập nhật qua thư mục mạng chia sẻ nội bộ (SMB/UNC, ví dụ: `\\10.81.141.226\temp\...\JA_LAN_Messenger`).
- **Chu kỳ linh hoạt:** Trong **Cài đặt > Tab Cập nhật OTA**, bạn có thể chọn tần suất: *Hàng ngày, Hàng tuần, Hàng tháng, hoặc Tắt*.
- **Cấu hình độc lập:** Có thể cấu hình trực tiếp trong app hoặc qua file `update_config.json` đặt cạnh ứng dụng.
- **Cập nhật 1-chạm:** Khi có bản cập nhật mới, thanh tiêu đề hiển thị huy hiệu xanh lá `vX.Y.Z`. Bấm vào để mở hộp thoại xem Release Notes và bấm "Cập nhật ngay" để tự động tải, giải nén và khởi động lại phiên bản mới.

### 2.8. Đính kèm nhiều tệp & Xem trước (Staged Attachments & File Preview)
- **Gắn tệp vào khung soạn thảo:** Dán (`Ctrl + V`) ảnh/file từ clipboard hoặc chọn từ nút kẹp giấy. Các tệp đính kèm sẽ hiển thị trực tiếp thành các thẻ thu nhỏ ngay trên thanh nhập liệu, cho phép đính kèm nhiều tệp cùng lúc trước khi bấm gửi.
- **Xem trước tức thì:** Nhấp vào ảnh đính kèm để mở hộp thoại Lightbox phóng to/thu nhỏ/xoay ảnh; nhấp vào tệp tài liệu để xem thông tin chi tiết trước khi gửi hoặc tải về.

### 2.9. Bộ gõ tiếng Việt / tiếng Trung tích hợp (Built-in IME)
- **Hỗ trợ gõ trực tiếp:** Tích hợp bộ gõ **Telex (Tiếng Việt)** và **Pinyin (Tiếng Trung)** ngay trong ứng dụng mà không cần cài đặt phần mềm ngoài.
- **Tự động thích ứng:** Nút chuyển đổi nhanh ở góc phải khung chat, tự động tránh xung đột khi phát hiện bộ gõ hệ thống (Unikey, EVKey, Microsoft IME).

### 2.10. Tối ưu hóa hiệu năng & Chế độ Lite (Mini PC / Máy cấu hình thấp)
- **Tự động nhận diện cấu hình:** Ứng dụng tự động đọc thông số CPU/GPU máy tính để thiết lập mức đồ họa phù hợp nhất (`Ultra`, `Medium`, `Lite`).
- **Chế độ Lite siêu mượt:** Dành riêng cho các máy tính văn phòng, Mini PC (như Intel N100, Celeron): tắt hoàn toàn các bộ lọc blur tốn tài nguyên GPU, mang lại tốc độ phản hồi tức thì và cuộn mượt mà.
- **Tùy chỉnh thủ công:** Trong **Cài đặt > Tab Cài đặt nâng cao > Mục Hiệu năng & Đồ họa**, người dùng có thể xem thẻ cấu hình máy và tự do lựa chọn giữa các mức hiệu năng.
- **Menu trạng thái Showcase:** Menu chuyển đổi trạng thái người dùng (Online / Away / Busy) được nâng cấp kính mờ đục cao cấp chống xuyên thấu, hiển thị rõ ràng và đẹp mắt.

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
