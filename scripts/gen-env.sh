#!/usr/bin/env bash
# Sinh file .env với mật khẩu ngẫu nhiên mạnh (24-32 ký tự).
# PUBLIC_URL tự lấy theo IP của server (vd. https://192.168.8.10);
# muốn đặt khác thì truyền vào: bash scripts/gen-env.sh 192.168.8.10
set -euo pipefail
cd "$(dirname "$0")/.."

if [ -f .env ]; then
  echo ".env đã tồn tại - xoá file cũ nếu muốn sinh lại." >&2
  exit 1
fi

rand() { openssl rand -base64 48 | tr -dc 'A-Za-z0-9' | head -c "${1:-24}"; }

# IP mà server dùng để ra ngoài (IP của card mạng chính)
detect_ip() {
  ip -4 route get 1.1.1.1 2>/dev/null \
    | awk '{for (i = 1; i <= NF; i++) if ($i == "src") { print $(i + 1); exit }}'
}
SERVER_IP="${1:-$(detect_ip || true)}"
SERVER_IP="${SERVER_IP:-localhost}"

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
# Địa chỉ mở website từ trình duyệt (IP của server)
PUBLIC_URL=https://${SERVER_IP}
ENV

chmod 600 .env
echo "Đã tạo .env. Thông tin đăng nhập:"
grep -E '^(ADMIN_|GRAFANA_|APP_DB_|PUBLIC_URL)' .env
