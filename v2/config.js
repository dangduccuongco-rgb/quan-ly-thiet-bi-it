// Điền 2 giá trị lấy từ Supabase → Project Settings → API (hoặc Data API).
// Đây là khoá công khai (anon / publishable), an toàn khi đưa lên web vì dữ liệu được bảo vệ bằng RLS.
// TUYỆT ĐỐI KHÔNG dán khoá "service_role" / "secret" vào đây.
window.ITAM_CONFIG = {
  SUPABASE_URL: '',
  SUPABASE_ANON_KEY: ''
};
