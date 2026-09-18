# Hướng dẫn sử dụng JA LAN Messenger v1.1.0

Ứng dụng nhắn tin và truyền tập tin ngang hàng (P2P) tốc độ cao dành riêng cho mạng cục bộ văn phòng (LAN), không cần máy chủ trung gian (Serverless), tích hợp Trợ lý Trí tuệ Nhân tạo JA-AI.

---

## 1. Yêu cầu hệ thống & Cài đặt
- **Hệ điều hành:** Windows 10 (bản 1809 trở lên) hoặc Windows 11 (64-bit).
- **Cài đặt:** 
  1. Tải về gói phát hành `JA_LAN_Messenger_v1.1.0_Windows_x64.zip`.
  2. Giải nén toàn bộ thư mục vào vị trí mong muốn (ví dụ: `D:\Tools\JA_LAN_Messenger\`).
  3. Nhấp đúp vào file `ja_lan_messenger.exe` (hoặc chạy qua `debug.bat` để theo dõi console log).
  4. **Tường lửa Windows Defender:** Trong lần chạy đầu tiên, chọn **"Allow access" (Cho phép truy cập)** cho cả mạng Private và Public để ứng dụng có thể lắng nghe và nhận diện thiết bị trên mạng LAN qua cổng UDP 36475 và TCP 6475/6476.

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
