TAG=v1.9.0
TITLE=JA LAN Messenger v1.9.0 — LAN Attachment Batches, Adaptive Image Grid, File Read Receipts & Shared Footer
BODY=
## JA LAN Messenger v1.9.0 — LAN Attachment Batches, Adaptive Image Grid, File Read Receipts & Shared Footer

- **Gộp Bong Bóng Đính Kèm Theo Mẻ (LAN Attachment Batches & Shared Bubble)**:
  - Khi gửi nhiều tệp tin hoặc ảnh cùng lúc, các tệp liền kề trong cùng mẻ tự động gom vào chung một bong bóng chat tinh gọn.
  - Tách biệt hoàn toàn tiến trình tải, trạng thái truyền, menu thao tác chuột phải, và bộ phím nhận diện đã đọc của từng tệp.
  - **Cách ly lỗi gửi tệp (Send Error Isolation)**: Một tệp lỗi không làm ảnh hưởng đến các tệp còn lại trong mẻ.
  - **Tương thích BeeBEEP an toàn**: Bổ sung trường thứ 15 mang `attachmentBatchId` trong gói chào tệp tin, tương thích ngược 100% với BeeBEEP C++ và bản cũ.
- **Lưới Ảnh Thích Ứng Thu Nhỏ Co Giãn (Compact Adaptive Attachment Image Grid)**:
  - Tự động sắp xếp ảnh theo lưới thu nhỏ co giãn (2 ảnh chia 2 cột, 4 ảnh xếp 2x2, 3 hoặc 5+ ảnh chia 3 cột trên khung rộng >= 400px).
  - Tệp tài liệu trong mẻ hỗn hợp giữ nguyên dạng hàng ngang đầy đủ theo đúng thứ tự.
  - Giới hạn giải mã thumbnail theo kích thước hiển thị * DPR giúp tiết kiệm bộ nhớ RAM và GPU, hỗ trợ Lightbox xem full-size khi nhấp.
- **Xác Nhận Đã Nhận & Đã Xem Cho Tệp Tin & Ảnh (Attachment Received & Read Receipts)**:
  - Bổ sung trạng thái Đã nhận (khi đối phương tải xong file) và Đã xem (`seen` qua giao thức `BEE-READ`) trên từng tệp tin và ảnh gửi đi.
  - Hỗ trợ đầy đủ cho cả cuộc trò chuyện trực tiếp và trò chuyện nhóm.
- **Chân Bong Bóng Gộp Chung Thống Nhất (Shared Attachment Batch Footer)**:
  - Một chân footer chung góc dưới bên phải hiển thị tem thời gian và nhãn trạng thái tổng hợp cho cả mẻ đính kèm.
- **Đồng bộ Toàn diện Phiên bản**: Cập nhật `v1.9.0+19` vào toàn bộ mã nguồn, metadata Windows Runner, tài liệu hướng dẫn và bộ cài đặt.

### Cài đặt
Chạy file `install.bat` để cài đặt ứng dụng vào Windows (có shortcut Desktop & Start Menu, đăng ký Control Panel), hoặc chạy trực tiếp `ja_lan_messenger.exe` để sử dụng dạng portable. Xem file `USERGUIDE.md` đính kèm để biết thêm chi tiết.
