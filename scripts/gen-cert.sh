#!/usr/bin/env bash
# Tạo chứng chỉ HTTPS tự ký (self-signed), hạn 365 ngày, cho IP của server
# (tự phát hiện) kèm localhost. Muốn chỉ định IP: bash scripts/gen-cert.sh 192.168.8.10
set -euo pipefail
cd "$(dirname "$0")/../nginx/certs"

detect_ip() {
  ip -4 route get 1.1.1.1 2>/dev/null \
    | awk '{for (i = 1; i <= NF; i++) if ($i == "src") { print $(i + 1); exit }}'
}
SERVER_IP="${1:-$(detect_ip || true)}"

CN="localhost"
SAN="DNS:localhost,IP:127.0.0.1"
if [ -n "${SERVER_IP}" ] && [ "${SERVER_IP}" != "localhost" ]; then
  CN="${SERVER_IP}"
  SAN="IP:${SERVER_IP},${SAN}"
fi

openssl req -x509 -nodes -newkey rsa:2048 -days 365 \
  -keyout server.key -out server.crt \
  -subj "/C=VN/ST=HaNoi/L=HaNoi/O=Inventory Lab/CN=${CN}" \
  -addext "subjectAltName=${SAN}"

# Nginx chạy bằng UID 101 (không phải root) nên cần đọc được key.
# Đây là chứng chỉ tự ký dùng cho lab; môi trường thật nên dùng Docker secrets.
chmod 644 server.key server.crt
echo "Đã tạo nginx/certs/server.crt và server.key cho: ${SAN}"
openssl x509 -in server.crt -noout -subject -dates
