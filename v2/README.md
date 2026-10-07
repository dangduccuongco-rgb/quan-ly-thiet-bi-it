# Quản lý Thiết bị IT — v2 (Supabase)

Phiên bản dùng cơ sở dữ liệu Supabase (Postgres), chịu được hàng trăm nghìn thiết bị:

- Tìm kiếm, lọc, sắp xếp, phân trang chạy trên máy chủ (mỗi lần chỉ tải 25 dòng).
- Dữ liệu dùng chung cho mọi người xem.
- Phân quyền thật bằng Row Level Security: chỉ tài khoản trong bảng `admins` mới thêm/sửa/xoá được.
- Phiếu bảo trì tự cập nhật trạng thái thiết bị (trigger trong database).
- Công cụ tạo/xoá dữ liệu thử (tối đa 500.000 dòng) để thử tốc độ.

Phiên bản cũ (lưu trên trình duyệt) vẫn ở thư mục gốc của repo.

## Cài đặt

1. Tạo project miễn phí tại https://supabase.com/dashboard.
2. Vào **SQL Editor → New query**, dán toàn bộ nội dung `schema.sql`, bấm **Run**.
3. Vào **Authentication → Users → Add user → Create new user**, nhập email + mật khẩu của admin, tích **Auto Confirm User**.
4. Quay lại **SQL Editor**, chạy (thay email):
   ```sql
   insert into public.admins (user_id)
   select id from auth.users where email = 'email-cua-ban@example.com';
   ```
5. (Khuyến nghị) **Authentication → Sign In / Providers**: tắt **Allow new users to sign up**.
6. Vào **Project Settings → API** (hoặc **Data API**), lấy **Project URL** và khoá **anon / publishable**, điền vào `config.js`.

> Chỉ dùng khoá anon/publishable. Không bao giờ đưa khoá `service_role`/secret lên web.

## Thêm admin khác

Tạo user ở bước 3 rồi chạy lại câu lệnh ở bước 4 với email mới.

## Giới hạn gói miễn phí

Gói Free có 500 MB database. 500.000 thiết bị (kèm chỉ mục tìm kiếm) chiếm khoảng 250–350 MB.
Project Free bị tạm dừng sau 7 ngày không có truy cập; vào dashboard bấm **Restore** để bật lại.
