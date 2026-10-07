#!/usr/bin/env python3
"""Tạo (hoặc cấp quyền cho) tài khoản admin trên Supabase.

Chạy: python3 v2/tao-admin.py
Cần đã đăng nhập Supabase CLI (npx supabase login). Khoá quản trị chỉ dùng
tạm trong lúc chạy, không in ra và không lưu vào file nào.
"""
import getpass, json, os, re, subprocess, sys, tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
cfg = open(os.path.join(HERE, 'config.js'), encoding='utf-8').read()
m = re.search(r"https://([a-z0-9]+)\.supabase\.co", cfg)
if not m:
    sys.exit('Không tìm thấy SUPABASE_URL trong config.js')
REF, URL = m.group(1), m.group(0)


def admin_key():
    out = subprocess.run(['npx', '--yes', 'supabase@latest', 'projects', 'api-keys', '--project-ref', REF, '-o', 'json'],
                         stdin=subprocess.DEVNULL, capture_output=True, text=True).stdout
    j = re.search(r'(\{.*\}|\[.*\])', out, re.S)
    if not j:
        sys.exit('Không lấy được khoá từ Supabase CLI. Hãy chạy: npx supabase login')
    data = json.loads(j.group(1))
    keys = data.get('keys', data) if isinstance(data, dict) else data
    for want in ('service_role', 'secret'):
        for k in keys:
            if want in (k.get('name'), k.get('type')) and k.get('api_key'):
                return k['api_key']
    sys.exit('Không tìm thấy khoá quản trị của project.')


def call(method, path, key, body=None, extra=None):
    # Dùng curl (chứng chỉ hệ thống macOS); khoá nằm trong file tạm quyền 600, dữ liệu gửi qua stdin.
    h = {'apikey': key, 'Content-Type': 'application/json'}
    if key.startswith('eyJ'):
        h['Authorization'] = 'Bearer ' + key
    h.update(extra or {})
    fd, hfile = tempfile.mkstemp()
    try:
        with os.fdopen(fd, 'w') as f:
            f.write(''.join(f'{k}: {v}\n' for k, v in h.items()))
        args = ['curl', '-sS', '-X', method, '-H', '@' + hfile, '-w', '\n%{http_code}', URL + path]
        if body is not None:
            args += ['--data-binary', '@-']
        r = subprocess.run(args, input=json.dumps(body) if body is not None else None, capture_output=True, text=True)
    finally:
        os.remove(hfile)
    if r.returncode != 0:
        sys.exit('Lỗi kết nối: ' + r.stderr.strip())
    txt, _, code = r.stdout.rpartition('\n')
    try:
        return int(code), json.loads(txt) if txt.strip() else None
    except ValueError:
        return int(code), {'msg': txt}


email = input('Email admin: ').strip().lower()
if not re.fullmatch(r'[^@\s]+@[^@\s]+\.[^@\s]+', email):
    sys.exit('Email không hợp lệ.')
pw = getpass.getpass('Mật khẩu (ít nhất 8 ký tự, không hiện khi gõ): ')
if len(pw) < 8:
    sys.exit('Mật khẩu cần ít nhất 8 ký tự.')
if getpass.getpass('Nhập lại mật khẩu: ') != pw:
    sys.exit('Hai mật khẩu không khớp.')

print('Đang kết nối Supabase…')
key = admin_key()

st, res = call('POST', '/auth/v1/admin/users', key, {'email': email, 'password': pw, 'email_confirm': True})
if st in (200, 201):
    uid = res['id']
    print('✓ Đã tạo tài khoản', email)
elif st == 422 or 'already' in json.dumps(res).lower() or 'exists' in json.dumps(res).lower():
    uid = None
    page = 1
    while uid is None:
        st2, lst = call('GET', f'/auth/v1/admin/users?page={page}&per_page=200', key)
        users = (lst or {}).get('users', [])
        uid = next((u['id'] for u in users if (u.get('email') or '').lower() == email), None)
        if uid is None and len(users) < 200:
            sys.exit('Tài khoản đã tồn tại nhưng không tìm thấy. Kiểm tra lại email.')
        page += 1
    st3, res3 = call('PUT', f'/auth/v1/admin/users/{uid}', key, {'password': pw, 'email_confirm': True})
    if st3 not in (200, 201):
        sys.exit(f'Không cập nhật được mật khẩu: {res3}')
    print('✓ Tài khoản đã có sẵn — đã đặt lại mật khẩu theo mật khẩu vừa nhập')
else:
    sys.exit(f'Tạo tài khoản thất bại ({st}): {res}')

st, res = call('POST', '/rest/v1/admins?on_conflict=user_id', key, {'user_id': uid},
               {'Prefer': 'resolution=ignore-duplicates,return=minimal'})
if st not in (200, 201, 204):
    sys.exit(f'Cấp quyền admin thất bại ({st}): {res}')
print('✓ Đã cấp quyền admin. Giờ bạn có thể đăng nhập website bằng email và mật khẩu vừa nhập.')
