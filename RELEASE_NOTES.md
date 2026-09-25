TAG=v1.4.1
TITLE=JA LAN Messenger v1.4.1 — Accurate BeeBEEP Detection & Unified Conversation Engine
BODY=
## JA LAN Messenger v1.4.1 — Accurate BeeBEEP Detection & Unified Conversation Engine

- **Nhận diện BeeBEEP Chuẩn xác 100% (`isRemoteBeebeep`)**: Khắc phục triệt để lỗi hiển thị nhầm nhãn "Bee" trên các máy chạy JA LAN Messenger (đặc biệt là máy vừa gỡ BeeBEEP như `172.21.174.103`). Bổ sung chữ ký `JA_LAN_MESSENGER` vào gói tin bắt tay `BEE-CIAO` và thuật toán phân tích chữ ký avatar/phiên bản để tách biệt hoàn toàn với phần mềm BeeBEEP gốc (C++/Qt).
- **Hợp nhất Thiết bị Vật lý & Chống Nhảy Cuộc trò chuyện (Unified Peer & Conversation Engine)**:
  - Tự động nhận diện và gộp các kết nối từ cùng một máy tính (`_isSamePhysicalPeer`), bất kể máy đó có nhiều card mạng / nhiều địa chỉ IP (như Ethernet `172.21.174.103` và Hotspot `192.168.137.231`) hay chạy đồng thời/thay đổi cổng giữa BeeBEEP (6475) và JA Messenger (6477).
  - **Tự động gộp tin nhắn (`_mergeConversations`)**: Mọi tin nhắn gửi/nhận qua các IP, card mạng hoặc cổng khác nhau của cùng một máy đều được gộp chung vào một luồng hội thoại duy nhất theo thứ tự thời gian.
  - **Khóa màn hình chat đang mở (`_selectedPeer` stability)**: Giữ nguyên khung chat đang trò chuyện khi đối phương đổi IP, đổi cổng hoặc gửi handshake mới; tin nhắn mới lập tức đồng bộ hiển thị và đánh dấu đã xem, không gây giật lag hay nhảy sang luồng khác.
  - **Hợp nhất Lịch sử Khởi động (`_consolidateLoadedPeersAndConversations`)**: Ngay khi mở ứng dụng, các file lịch sử cũ bị phân tách trước đây tự động được kết nối và hợp nhất thành một thực thể duy nhất trên danh bạ.
- **Thanh danh bạ Độc bản**: Loại bỏ hoàn toàn tình trạng xuất hiện 2 thẻ trùng lặp cho cùng một đồng nghiệp trên danh bạ bên trái khi máy họ có nhiều card mạng hoặc đổi cổng kết nối.
- **Trạng thái Chọn Bền bỉ (`coordinator.isPeerSelected`)**: Đồng bộ trạng thái highlight của thẻ người dùng trên danh bạ, ngăn chặn hiện tượng mất chọn khi mạng cập nhật ngầm.
- **Đồng bộ toàn diện phiên bản**: Cập nhật `v1.4.1+9` vào toàn bộ mã nguồn, metadata Windows Runner, tài liệu hướng dẫn và bộ cài đặt.

### Cài đặt
Chạy file `install.bat` để cài đặt ứng dụng vào Windows (có shortcut Desktop & Start Menu, đăng ký Control Panel), hoặc chạy trực tiếp `ja_lan_messenger.exe` để sử dụng dạng portable. Xem file `USERGUIDE.md` đính kèm để biết thêm chi tiết.

