TAG=v1.6.1
TITLE=JA LAN Messenger v1.6.1 — Animated Sprite Stickers, Clipboard Image Copy & Multilingual IP Scan Progress
BODY=
## JA LAN Messenger v1.6.1 — Animated Sprite Stickers, Clipboard Image Copy & Multilingual IP Scan Progress

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
- **Đồng bộ toàn diện phiên bản**: Cập nhật `v1.6.1+13` vào toàn bộ mã nguồn, metadata Windows Runner, tài liệu hướng dẫn và bộ cài đặt.

### Cài đặt
Chạy file `install.bat` để cài đặt ứng dụng vào Windows (có shortcut Desktop & Start Menu, đăng ký Control Panel), hoặc chạy trực tiếp `ja_lan_messenger.exe` để sử dụng dạng portable. Xem file `USERGUIDE.md` đính kèm để biết thêm chi tiết.

