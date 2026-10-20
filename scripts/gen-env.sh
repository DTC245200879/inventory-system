#!/usr/bin/env bash
# Sinh file .env với mật khẩu ngẫu nhiên mạnh (24-32 ký tự).
set -euo pipefail
cd "$(dirname "$0")/.."

if [ -f .env ]; then
  echo ".env đã tồn tại - xoá file cũ nếu muốn sinh lại." >&2
  exit 1
fi

rand() { openssl rand -base64 48 | tr -dc 'A-Za-z0-9' | head -c "${1:-24}"; }

cat > .env <<ENV
# ==== FILE BÍ MẬT - KHÔNG COMMIT LÊN GITHUB (.gitignore đã chặn) ====
MYSQL_ROOT_PASSWORD=$(rand 32)
APP_DB_USER=inventory_app
APP_DB_PASSWORD=$(rand 24)
EXPORTER_DB_PASSWORD=$(rand 24)
SECRET_KEY=$(rand 48)
ADMIN_USERNAME=admin
ADMIN_PASSWORD=$(rand 16)
GRAFANA_ADMIN_USER=admin
GRAFANA_ADMIN_PASSWORD=$(rand 20)
# Địa chỉ truy cập từ trình duyệt (đổi thành https://localhost:8443 nếu dùng cổng 8443)
PUBLIC_URL=https://localhost
ENV

chmod 600 .env
echo "Đã tạo .env. Thông tin đăng nhập:"
grep -E '^(ADMIN_|GRAFANA_|APP_DB_)' .env
