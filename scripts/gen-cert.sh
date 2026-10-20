#!/usr/bin/env bash
# Tạo chứng chỉ HTTPS tự ký (self-signed) cho localhost, hạn 365 ngày.
set -euo pipefail
cd "$(dirname "$0")/../nginx/certs"

MSYS_NO_PATHCONV=1 openssl req -x509 -nodes -newkey rsa:2048 -days 365 \
  -keyout server.key -out server.crt \
  -subj "/C=VN/ST=HaNoi/L=HaNoi/O=Inventory Lab/CN=localhost" \
  -addext "subjectAltName=DNS:localhost,IP:127.0.0.1"

# Nginx chạy bằng UID 101 (không phải root) nên cần đọc được key.
# Đây là chứng chỉ tự ký dùng cho lab; môi trường thật nên dùng Docker secrets.
chmod 644 server.key server.crt
echo "Đã tạo nginx/certs/server.crt và server.key"
openssl x509 -in server.crt -noout -subject -dates
