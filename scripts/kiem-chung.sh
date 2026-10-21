#!/usr/bin/env bash
# =====================================================================
#  Kiểm chứng triển khai + hardening - chạy TRÊN SERVER, trong thư mục dự án:
#      bash scripts/kiem-chung.sh
#  Mỗi mục in ra lệnh/kết quả thật và đánh dấu [ĐẠT] / [CHƯA ĐẠT] để chụp ảnh
#  minh chứng cho báo cáo. Script không thay đổi cấu hình và KHÔNG in mật khẩu.
#  Phần UFW/SSH cần sudo (hỏi mật khẩu 1 lần).
# =====================================================================
cd "$(dirname "$0")/.." || exit 1

if [ -t 1 ]; then
  G=$'\e[32m'; R=$'\e[31m'; Y=$'\e[33m'; B=$'\e[1;36m'; N=$'\e[0m'
else
  G=''; R=''; Y=''; B=''; N=''
fi
PASS=0; FAIL=0
ok()   { echo "  ${G}[ĐẠT]${N} $*"; PASS=$((PASS + 1)); }
bad()  { echo "  ${R}[CHƯA ĐẠT]${N} $*"; FAIL=$((FAIL + 1)); }
note() { echo "  ${Y}[LƯU Ý]${N} $*"; }
sec()  { echo; echo "${B}=== $* ===${N}"; }
show() { sed 's/^/      /'; }                       # thụt lề kết quả lệnh
running() { docker ps --format '{{.Names}}' | grep -qx "$1"; }

PROJECT_FILTER="label=com.docker.compose.project=inventory"
HOST=$(grep -E '^PUBLIC_URL=' .env 2>/dev/null | tail -1 | cut -d= -f2- | sed -E 's#^https?://##; s#/.*$##')
HOST=${HOST:-localhost}
URL="https://${HOST}"
APPU=$(grep -E '^APP_DB_USER=' .env 2>/dev/null | tail -1 | cut -d= -f2-)
APPU=${APPU:-inventory_app}

if ! docker info >/dev/null 2>&1; then
  echo "Không gọi được Docker. Chạy script trên server Ubuntu (không phải PowerShell của Windows)"
  echo "và đảm bảo user thuộc nhóm docker."
  exit 1
fi

# ---------------------------------------------------------------------
sec "1. Server và các container"
hostnamectl 2>/dev/null | grep -E 'Static hostname|Operating System|Kernel' | sed 's/^ *//' | show
echo "      Docker Engine $(docker version --format '{{.Server.Version}}' 2>/dev/null), Compose $(docker compose version --short 2>/dev/null)"
echo "      IP server: $(hostname -I | awk '{print $1}')   Website: ${URL}"
docker ps -a --filter "$PROJECT_FILTER" --format 'table {{.Names}}\t{{.Image}}\t{{.Status}}' | show
TOTAL=$(docker ps -a --filter "$PROJECT_FILTER" -q | wc -l)
UP=$(docker ps --filter "$PROJECT_FILTER" --filter status=running -q | wc -l)
UNHEALTHY=$(docker ps --filter "$PROJECT_FILTER" --filter health=unhealthy -q | wc -l)
if [ "$TOTAL" -gt 0 ] && [ "$UP" -eq "$TOTAL" ] && [ "$UNHEALTHY" -eq 0 ]; then
  ok "$UP/$TOTAL container đang chạy, không có container unhealthy"
else
  bad "$UP/$TOTAL container đang chạy, $UNHEALTHY container unhealthy"
fi
[ "$TOTAL" -eq 12 ] || note "Chạy đủ 3 phần sẽ có 12 container (hiện có $TOTAL)"

# ---------------------------------------------------------------------
sec "2. Giám sát: Prometheus + Grafana"
if running inventory-prometheus; then
  TLIST=$(curl -s --max-time 5 http://127.0.0.1:9090/api/v1/targets | python3 -c '
import json, sys
for t in sorted(json.load(sys.stdin)["data"]["activeTargets"], key=lambda t: t["labels"]["job"]):
    print("%-14s %-8s %s" % (t["labels"]["job"], t["health"].upper(), t.get("lastError", "")[:70]))
' 2>/dev/null)
  echo "$TLIST" | show
  if running inventory-loki; then
    DOWN=$(echo "$TLIST" | awk 'NF && $2 != "UP" {printf "%s ", $1}')
  else
    DOWN=$(echo "$TLIST" | awk 'NF && $2 != "UP" && $1 != "loki" && $1 != "promtail" {printf "%s ", $1}')
    note "loki/promtail DOWN là bình thường khi chưa chạy phần 3"
  fi
  if [ -n "$TLIST" ] && [ -z "$DOWN" ]; then ok "Các target giám sát đều UP"; else bad "Target chưa UP: ${DOWN:-không đọc được API}"; fi
  RULES=$(curl -s --max-time 5 http://127.0.0.1:9090/api/v1/rules | python3 -c '
import json, sys
g = json.load(sys.stdin)["data"]["groups"]
print(sum(len(x["rules"]) for x in g))' 2>/dev/null)
  FIRING=$(curl -s --max-time 5 http://127.0.0.1:9090/api/v1/alerts | python3 -c '
import json, sys
print(" ".join(sorted({a["labels"]["alertname"] for a in json.load(sys.stdin)["data"]["alerts"] if a["state"] == "firing"})))' 2>/dev/null)
  echo "      Luật cảnh báo đã nạp: ${RULES:-?}   Đang kích hoạt: ${FIRING:-không có}"
  [ "${RULES:-0}" -gt 0 ] && ok "Prometheus đã nạp ${RULES} alert rule"
  GH=$(curl -sk --max-time 5 "${URL}/grafana/api/health")
  echo "      Grafana /api/health: $(echo "$GH" | tr -d '\n ' )"
  echo "$GH" | grep -q '"database": *"ok"' && ok "Grafana chạy sau Nginx tại ${URL}/grafana/" || bad "Grafana không phản hồi qua ${URL}/grafana/"
else
  note "Chưa chạy phần 2 (giám sát) - bỏ qua"
fi

# ---------------------------------------------------------------------
sec "3. Log tập trung: Loki + Promtail (LogQL)"
if running inventory-loki; then
  lokiget() { docker exec inventory-prometheus wget -qO- -T 5 "http://loki:3100$1" 2>/dev/null; }
  logql() {   # chạy 1 câu LogQL dạng metric (instant query) qua API của Loki
    local enc
    enc=$(python3 -c 'import sys, urllib.parse; print(urllib.parse.quote(sys.argv[1]))' "$1")
    lokiget "/loki/api/v1/query?query=${enc}" | python3 -c '
import json, sys
res = json.load(sys.stdin)["data"]["result"]
if not res:
    print("(chưa có log khớp)")
for r in res:
    lbl = ",".join("%s=%s" % kv for kv in sorted(r["metric"].items())) or "tổng"
    print("%-28s %s" % (lbl, r["value"][1]))' 2>/dev/null
  }
  READY=$(lokiget /ready)
  echo "      Loki /ready: ${READY:-không phản hồi}"
  [ "$(echo "$READY" | tr -d '[:space:]')" = "ready" ] && ok "Loki sẵn sàng" || bad "Loki chưa sẵn sàng"
  Q1='sum by (service) (count_over_time({container=~"inventory-.+"}[1h]))'
  Q2='sum by (status_class) (count_over_time({service="nginx", status_class=~".+"}[1h]))'
  Q3='sum by (event) (count_over_time({service="app"} | logfmt | __error__="" | event=~"login_failed|stock_in|stock_out|stock_out_rejected" [24h]))'
  for q in "$Q1" "$Q2" "$Q3"; do
    echo "      LogQL> $q"
    logql "$q" | sed 's/^/        /' | show
  done
  SERVICES=$(logql "$Q1" | grep -c 'service=')
  [ "$SERVICES" -gt 0 ] && ok "Promtail đã đẩy log của $SERVICES service về Loki" || bad "Loki chưa có log nào"
else
  note "Chưa chạy phần 3 (Loki/Promtail) - bỏ qua"
fi

# ---------------------------------------------------------------------
sec "4. Hardening container: non-root, read-only, bỏ capabilities, giới hạn tài nguyên"
printf "      %-26s %-10s %-9s %-9s %-15s %-8s %s\n" CONTAINER "UID" READONLY CAP_DROP NO_NEW_PRIVS "RAM_MAX" PIDS_MAX
ROOTS=""; NONEW_MISSING=""; COUNT=0
for c in $(docker ps --filter "$PROJECT_FILTER" --format '{{.Names}}' | sort); do
  uids=$(docker top "$c" -eo pid,uid 2>/dev/null | awk 'NR > 1 {print $2}' | sort -un | paste -sd, -)
  COUNT=$((COUNT + 1))
  IFS='|' read -r ro cap secopt mem pids <<<"$(docker inspect "$c" --format '{{.HostConfig.ReadonlyRootfs}}|{{.HostConfig.CapDrop}}|{{.HostConfig.SecurityOpt}}|{{.HostConfig.Memory}}|{{.HostConfig.PidsLimit}}')"
  cap=$(echo "$cap" | tr -d '[]'); [ -z "$cap" ] && cap="-"
  case "$secopt" in *no-new-privileges*) nn="có" ;; *) nn="KHÔNG"; NONEW_MISSING="$NONEW_MISSING $c" ;; esac
  if [ "${mem:-0}" -gt 0 ] 2>/dev/null; then mem="$((mem / 1024 / 1024))MiB"; else mem="-"; fi
  case "$pids" in ''|0|-1|"<nil>") pids="-" ;; esac
  case ",$uids," in *,0,*) ROOTS="$ROOTS $c" ;; esac
  printf "      %-26s %-10s %-9s %-9s %-15s %-8s %s\n" "$c" "${uids:-?}" "$ro" "$cap" "$nn" "$mem" "$pids"
done
NONROOT=$(( COUNT - $(echo "$ROOTS" | wc -w) ))
ok "$NONROOT/$COUNT container không có tiến trình nào chạy bằng root (UID 0)"
[ -n "$ROOTS" ] && note "Có tiến trình root:$ROOTS - phpMyAdmin (Apache master rồi hạ quyền www-data), cAdvisor/Promtail cần đọc dữ liệu Docker (đã mount :ro)"
[ -z "$NONEW_MISSING" ] && ok "Mọi container bật no-new-privileges" || bad "Thiếu no-new-privileges:$NONEW_MISSING"
echo "      \$ docker exec inventory-app touch /app/kiem_tra"
OUT=$(docker exec inventory-app touch /app/kiem_tra 2>&1); echo "$OUT" | show
echo "$OUT" | grep -qi "read-only" && ok "Filesystem của app là chỉ đọc" || bad "Ghi được vào filesystem của app"
echo "      \$ docker stats --no-stream"
# shellcheck disable=SC2046  # cần tách từng ID container
docker stats --no-stream --format 'table {{.Name}}\t{{.CPUPerc}}\t{{.MemUsage}}\t{{.PIDs}}' $(docker ps --filter "$PROJECT_FILTER" -q) | show

# ---------------------------------------------------------------------
sec "5. Cô lập mạng (network isolation)"
INTERNAL=$(docker network inspect inventory_backend --format '{{.Internal}}' 2>/dev/null)
MEMBERS=$(docker network inspect inventory_backend --format '{{range .Containers}}{{.Name}} {{end}}' 2>/dev/null)
echo "      Mạng backend: internal=${INTERNAL}  thành viên: ${MEMBERS}"
[ "$INTERNAL" = "true" ] && ok "Mạng backend là internal (không có gateway ra ngoài)" || bad "Mạng backend chưa đặt internal: true"
PORTS_DB=$(docker port inventory-db 2>/dev/null)
[ -z "$PORTS_DB" ] && ok "MySQL không publish cổng nào ra host" || bad "MySQL đang publish cổng: $PORTS_DB"
echo "      \$ docker exec inventory-nginx wget -qO- -T2 http://db:3306"
OUT=$(docker exec inventory-nginx wget -qO- -T 2 http://db:3306 2>&1 | head -1); echo "$OUT" | show
echo "$OUT" | grep -qiE "bad address|resolve|unknown host" && ok "Nginx (mạng frontend) không nhìn thấy db" || bad "Nginx truy cập được tới db"
echo "      \$ docker run --rm --network inventory_backend busybox (ip route; wget http://1.1.1.1)"
OUT=$(docker run --rm --network inventory_backend busybox:1.36 sh -c 'ip route; wget -q -T 3 -O /dev/null http://1.1.1.1 2>&1 || true' 2>&1 | grep -v -E '^(Unable to find|[0-9a-f]+: |Digest:|Status:|1\.36:)')
echo "$OUT" | show
if echo "$OUT" | grep -q "default"; then bad "Mạng backend có default route"; else ok "Container trong mạng backend không ra được Internet"; fi

# ---------------------------------------------------------------------
sec "6. Nginx: HTTPS, security headers, rate-limit"
H=$(curl -sI --max-time 5 "http://${HOST}/")
echo "      \$ curl -I http://${HOST}/"
echo "$H" | grep -iE '^(HTTP|location)' | tr -d '\r' | show
if echo "$H" | head -1 | grep -q ' 301' && echo "$H" | grep -qi '^location: https://'; then ok "HTTP chuyển hướng 301 sang HTTPS"; else bad "HTTP chưa chuyển sang HTTPS"; fi
echo "      \$ curl -kv ${URL}/ (thông tin TLS)"
curl -skv --max-time 5 "${URL}/" -o /dev/null 2>&1 | grep -E 'SSL connection using|subject:|issuer:|expire date' | sed 's/^\* *//' | show
HS=$(curl -skI --max-time 5 "${URL}/login" | tr -d '\r')
echo "      \$ curl -kI ${URL}/login"
echo "$HS" | grep -iE '^(HTTP|server|strict-transport|content-security|x-frame|x-content-type|referrer-policy|permissions-policy|cross-origin|set-cookie)' | cut -c1-150 | show
MISSING=""
for h in Strict-Transport-Security Content-Security-Policy X-Frame-Options X-Content-Type-Options Referrer-Policy Permissions-Policy; do
  echo "$HS" | grep -qi "^$h:" || MISSING="$MISSING $h"
done
[ -z "$MISSING" ] && ok "Đủ 6 security header (HSTS, CSP, X-Frame-Options, X-Content-Type-Options, Referrer-Policy, Permissions-Policy)" || bad "Thiếu header:$MISSING"
echo "$HS" | grep -i '^server:' | grep -q '[0-9]' && bad "Header Server lộ phiên bản" || ok "Ẩn phiên bản Nginx (server_tokens off)"
CK=$(echo "$HS" | grep -i '^set-cookie')
if echo "$CK" | grep -qi 'secure' && echo "$CK" | grep -qi 'httponly' && echo "$CK" | grep -qi 'samesite'; then ok "Cookie phiên có Secure, HttpOnly, SameSite"; else note "Không đọc được cookie phiên để kiểm tra cờ bảo mật"; fi
CODE=$(curl -sk -o /dev/null -w '%{http_code}' --max-time 5 -X POST --data 'username=x&password=y' "${URL}/login")
echo "      POST /login không kèm CSRF token -> HTTP $CODE"
[ "$CODE" = "400" ] && ok "Chặn request thiếu CSRF token" || note "POST không token trả về $CODE (429 nghĩa là đang bị rate-limit, chạy lại sau 1 phút)"
CODE=$(curl -sk -o /dev/null -w '%{http_code}' --max-time 5 "${URL}/metrics")
echo "      GET /metrics qua Nginx -> HTTP $CODE"
[ "$CODE" = "404" ] && ok "Endpoint /metrics không lộ ra ngoài" || bad "/metrics truy cập được từ ngoài"
CODES=$(for _ in $(seq 1 15); do curl -sk -o /dev/null -w '%{http_code} ' --max-time 5 "${URL}/login"; done)
echo "      15 request liên tiếp tới /login: $CODES"
echo "$CODES" | grep -q 429 && ok "Rate-limit trang đăng nhập hoạt động (trả 429)" || bad "Không thấy rate-limit"

# ---------------------------------------------------------------------
sec "7. Cơ sở dữ liệu: đặc quyền tối thiểu"
echo "      Quyền của các tài khoản (SHOW GRANTS):"
GR=$(docker exec -i inventory-db sh -c 'exec mysql -uroot -p"$MYSQL_ROOT_PASSWORD" -N -B' 2>/dev/null <<SQL
SHOW GRANTS FOR '${APPU}'@'%';
SHOW GRANTS FOR 'exporter'@'%';
SELECT CONCAT('USERS: ', GROUP_CONCAT(CONCAT(user, '@', host) ORDER BY user SEPARATOR ', ')) FROM mysql.user WHERE user NOT LIKE 'mysql.%';
SQL
)
echo "$GR" | sed 's/^USERS: /Tài khoản trong MySQL: /' | show
APPGR=$(echo "$GR" | grep "\`${APPU}\`")
if [ -n "$APPGR" ] && ! echo "$APPGR" | grep -qiE 'ALL PRIVILEGES|DROP|ALTER|CREATE|GRANT OPTION'; then
  ok "User ${APPU} chỉ có SELECT/INSERT/UPDATE/DELETE"
else
  bad "Không xác nhận được quyền tối thiểu của ${APPU}"
fi
if echo "$GR" | grep -q 'root@localhost' && ! echo "$GR" | grep -q 'root@%'; then ok "root chỉ đăng nhập được từ localhost"; else bad "root có thể đăng nhập từ xa"; fi
echo "      \$ (đăng nhập bằng ${APPU}) CREATE TABLE ... ; DROP TABLE ..."
OUT=$(docker exec -i inventory-db sh -c 'exec mysql --force -u"$APP_DB_USER" -p"$APP_DB_PASSWORD" inventory_db' 2>&1 <<'SQL' | grep -v 'Using a password'
CREATE TABLE _kiem_tra_quyen (id INT);
DROP TABLE IF EXISTS _kiem_tra_quyen;
SQL
)
echo "$OUT" | show
if [ "$(echo "$OUT" | grep -c 'command denied')" -ge 2 ]; then
  ok "User của app bị từ chối CREATE/DROP (ERROR 1142)"
else
  bad "User của app không bị chặn CREATE/DROP"
  docker exec -i inventory-db sh -c 'exec mysql -uroot -p"$MYSQL_ROOT_PASSWORD" inventory_db' >/dev/null 2>&1 <<<'DROP TABLE IF EXISTS _kiem_tra_quyen;'
fi

# ---------------------------------------------------------------------
sec "8. Quản lý bí mật"
if [ -f .env ]; then
  echo "      $(ls -l .env | awk '{print $1, $NF}')"
  [ "$(stat -c %a .env)" = "600" ] && ok ".env chỉ chủ sở hữu đọc/ghi được (600)" || bad ".env chưa đặt quyền 600 (chmod 600 .env)"
  grep -E '^[A-Z_]*(PASSWORD|SECRET_KEY)=' .env | while IFS='=' read -r k v; do echo "      $k: ${#v} ký tự (không in giá trị)"; done
fi
if git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  git check-ignore -q .env && ok ".env bị .gitignore chặn, không lên GitHub" || bad ".env chưa nằm trong .gitignore"
  TRACKED=$(git ls-files | grep -E '(^|/)\.env$|\.key$|\.crt$|\.pem$')
  [ -z "$TRACKED" ] && ok "Không có .env, khoá hay chứng chỉ nào trong git" || bad "File bí mật đang được git theo dõi: $TRACKED"
  echo "      Lịch sử commit:"
  git log --oneline -n 10 | show
fi

# ---------------------------------------------------------------------
sec "9. Hardening hệ điều hành (Ubuntu)"
echo "      Cổng đang lắng nghe (ss -tln):"
LISTEN=$(ss -H -tln | awk '{print $4}' | sort -u)
echo "$LISTEN" | paste -sd' ' - | fold -s -w 100 | show
EXTERNAL=$(echo "$LISTEN" | grep -vE '^(127\.|\[::1\])' | sed -E 's/.*:([0-9]+)$/\1/' | sort -un | paste -sd' ' -)
echo "      Cổng mở ra ngoài: $EXTERNAL"
EXTRA=$(echo "$EXTERNAL" | tr ' ' '\n' | grep -vxE '22|80|443' | paste -sd' ' -)
[ -z "$EXTRA" ] && ok "Chỉ mở 22, 80, 443 ra ngoài (Prometheus 9090 chỉ trên 127.0.0.1)" || bad "Có cổng mở thêm: $EXTRA"
UU=$(systemctl is-active unattended-upgrades 2>/dev/null)
echo "      unattended-upgrades: $UU"
[ "$UU" = "active" ] && ok "Tự động cài bản vá bảo mật" || note "unattended-upgrades chưa chạy"
echo "      (Cần sudo để đọc UFW và cấu hình SSH)"
if sudo -v; then
  sudo ufw status verbose | show
  sudo ufw status | grep -q "Status: active" && ok "Tường lửa UFW đang bật" || bad "UFW chưa bật (mục 8.1: sudo ufw allow OpenSSH/80/443 rồi sudo ufw enable)"
  sudo sshd -T 2>/dev/null | grep -Ei '^(permitrootlogin|passwordauthentication|pubkeyauthentication|maxauthtries|x11forwarding) ' | show
  sudo sshd -T 2>/dev/null | grep -qiE '^permitrootlogin (no|without-password|prohibit-password)' && ok "SSH không cho root đăng nhập bằng mật khẩu"
else
  note "Không có quyền sudo - bỏ qua UFW/SSH"
fi

# ---------------------------------------------------------------------
echo
echo "${B}=== KẾT QUẢ: ${G}${PASS} mục đạt${B}, ${R}${FAIL} mục chưa đạt${B} ===${N}"
