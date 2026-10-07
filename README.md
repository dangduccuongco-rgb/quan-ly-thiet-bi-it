# Quản lý Thiết bị IT

Website quản lý tài sản IT dạng một file HTML: tổng quan, danh sách thiết bị, bảo trì, nhân viên.

- Tìm kiếm, lọc, sắp xếp, thêm/sửa/xoá thiết bị, xuất CSV
- Phiếu bảo trì tự cập nhật trạng thái thiết bị
- Giao diện sáng/tối, responsive
- Dữ liệu lưu trong `localStorage` của trình duyệt

## Chạy

Mở `index.html` bằng trình duyệt, hoặc:

```bash
python3 -m http.server 8765
```

## Quyền admin

- Người chưa đăng nhập chỉ xem được; bấm **Đăng nhập admin** để thêm/sửa/xoá.
- Đặt mật khẩu admin: chạy `./doi-mat-khau.sh`, rồi commit và deploy lại.
- Lưu ý: đây là khóa phía giao diện, không phải bảo mật máy chủ; dữ liệu vẫn lưu riêng trên từng trình duyệt.
