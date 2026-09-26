TAG=v1.5.1
TITLE=JA LAN Messenger v1.5.1 — Group Renaming Fix & Multi-entry Support
BODY=
## JA LAN Messenger v1.5.1 — Group Renaming Fix & Multi-entry Support

- **Khắc phục triệt để lỗi không thể đổi tên nhóm sau khi tạo (Group Renaming Fix)**:
  - Tự động định tuyến cuộc gọi `setPeerNickname` sang `renameGroup` khi định danh là nhóm P2P, ngăn ngừa việc bỏ qua khi tìm kiếm trong danh bạ 1-1.
  - Hiển thị nút đổi tên nhóm (biểu tượng bút chì) trực tiếp trên thanh tiêu đề cuộc trò chuyện nhóm (`ChatViewPanel`) dành cho Quản trị viên.
  - Bổ sung nút đổi tên nhóm trực tiếp trong phần tiêu đề của hộp thoại xem thành viên nhóm (`GroupMembersDialog`).
  - Bổ sung menu chuột phải (Context Menu) cho thẻ nhóm trong danh sách (`PeerListView`): Đổi tên nhóm, Đổi ảnh đại diện nhóm, Xem danh sách thành viên, Rời nhóm / Giải tán nhóm.
  - Chuẩn hóa hộp thoại chi tiết (`ConversationDetailsPanel`) và hộp thoại đổi nhanh biệt danh (`showQuickNicknameDialog`) hiển thị tiêu đề và gợi ý "Đổi tên nhóm" đa ngôn ngữ (Tiếng Việt, English, 简体中文).
- **Tối ưu Nút Chọn Nhanh Chu kỳ Cập nhật OTA**:
  - Chuyển đổi dropdown list chọn thời gian kiểm tra bản cập nhật sang dạng các nút bấm chọn nhanh trực quan (Quick Selection Chips) theo chuẩn UX Desktop.
- **Đồng bộ hóa Tên Nhóm Tức thì**: Cập nhật tức thì tên nhóm hiển thị trên thanh tiêu đề và danh bạ ngay khi hoàn tất đổi tên, đồng bộ thời gian thực đến tất cả các thành viên qua giao thức P2P.
- **Đồng bộ toàn diện phiên bản**: Cập nhật `v1.5.1+11` vào toàn bộ mã nguồn, metadata Windows Runner, tài liệu hướng dẫn và bộ cài đặt.

### Cài đặt
Chạy file `install.bat` để cài đặt ứng dụng vào Windows (có shortcut Desktop & Start Menu, đăng ký Control Panel), hoặc chạy trực tiếp `ja_lan_messenger.exe` để sử dụng dạng portable. Xem file `USERGUIDE.md` đính kèm để biết thêm chi tiết.
