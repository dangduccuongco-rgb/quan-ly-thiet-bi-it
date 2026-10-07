#!/bin/sh
# Đặt mật khẩu admin mặc định (lưu mã băm SHA-256 vào index.html).
cd "$(dirname "$0")" || exit 1
printf 'Mật khẩu admin mới: '; stty -echo; read -r pw; stty echo; echo
printf 'Nhập lại: '; stty -echo; read -r pw2; stty echo; echo
[ "$pw" = "$pw2" ] || { echo "Hai mật khẩu không khớp."; exit 1; }
[ ${#pw} -ge 6 ] || { echo "Cần ít nhất 6 ký tự."; exit 1; }
hash=$(printf '%s' "$pw" | shasum -a 256 | cut -d' ' -f1)
sed -i '' "s/const DEFAULT_ADMIN_HASH='[0-9a-f]*'/const DEFAULT_ADMIN_HASH='$hash'/" index.html
echo "Đã cập nhật mật khẩu admin trong index.html."
