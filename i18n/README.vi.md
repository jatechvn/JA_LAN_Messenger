# JA LAN Messenger - Ứng Dụng Nhắn Tin & Truyền Tệp Mạng LAN Siêu Nhẹ

Ứng dụng nhắn tin và truyền tập tin ngang hàng (P2P) tốc độ cao, không cần máy chủ (Serverless), được xây dựng trên nền tảng **Flutter Desktop (Dart)**, lấy cảm hứng và đối chiếu giao thức từ **BeeBEEP (C++/Qt)**.

---

## 🌟 Đặc Điểm Nổi Bật

1. **Nhỏ Gọn - Khởi Động Tức Thì (Lightweight & Fast-Loading):**
   - Kích thước cửa sổ mặc định nhỏ gọn tối ưu cho môi trường văn phòng: `960x640`.
   - Sử dụng **Pure Dart Sockets** (`dart:io`), không cần phụ thuộc DLL bên ngoài hay runtime cồng kềnh.
   - Dung lượng RAM tiêu thụ cực thấp chỉ từ **40–60 MB**, chạy mượt mà trên cả máy tính văn phòng cấu hình thấp.
2. **Tương Thích Giao Thức BeeBEEP:**
   - Sử dụng chung các cổng mạng chuẩn:
     - **UDP 36475**: Tự động tìm kiếm đồng nghiệp qua Broadcast `255.255.255.255` và Multicast `224.0.64.75`.
     - **TCP 6475**: Bắt tay (`BEE-CIAO`), gửi tin nhắn văn bản (`BEE-CHAT`), xác nhận đã nhận (`BEE-RECV`), rung chuông Nudge (`BEE-BUZZ`).
     - **TCP 6476**: Kênh truyền tệp độc lập tốc độ cao.
3. **Bộ Khung Giao Diện Bento Glassmorphism:**
   - Hỗ trợ mượt mà cả **Windows 10** (Aero Glass) và **Windows 11** (Acrylic/Mica).
   - Thiết kế 3 cột tiện lợi: Sidebar biểu tượng siêu gọn (58px), danh sách người dùng online/offline (260px), khung chat bong bóng và trình quản lý truyền tệp.
   - Hộp thoại Cài đặt chuẩn 3 tab (`Advanced Settings`, `About`, `User Guide`) có slider tùy chỉnh độ mờ/trong suốt và sàn an toàn chống nhòe chữ.
4. **Mã Hóa Bảo Mật AES-256:**
   - Tùy chọn bật mã hóa nội bộ với mật khẩu nhóm chung (Pre-shared Key).

---

## 🛠️ Hướng Dẫn Chạy & Biên Dịch

### Chạy chế độ phát triển (Debug):
```powershell
.\run.bat
```

### Đóng gói bản phát hành chính thức (Release):
```powershell
.\build.bat
```
Sau khi biên dịch thành công, shortcut `.Release - Shortcut.lnk` sẽ trỏ tới file chạy tại:
`build\windows\x64\runner\Release\ja_lan_messenger.exe`

### Dọn dẹp dự án:
```powershell
.\clean_project.bat
```
