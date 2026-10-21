# Hướng dẫn thực hiện Đề 5 – Hệ thống Quản lý Kho hàng (Inventory) trên Ubuntu Server

Tài liệu đi theo đúng thứ tự chấm điểm của đề: **chuẩn bị server → 3 commit bắt buộc → hardening → demo → báo cáo**. Làm lần lượt từ trên xuống; xong mỗi bước thì đối chiếu với dòng **Kết quả đúng** trước khi sang bước sau.

**Mô hình:** máy Windows chạy **VMware Workstation** → máy ảo **Ubuntu Server 24.04 LTS** có IP tĩnh **`192.168.8.10`** → Docker Engine → 12 container. Bạn gõ lệnh trên server qua **SSH** từ PowerShell; website mở bằng trình duyệt trên Windows tại **`https://192.168.8.10`**.

```
Windows (trình duyệt + PowerShell)
   │  mạng NAT VMnet8 của VMware (192.168.8.0/24)
   │  https://192.168.8.10        ssh dang@192.168.8.10
   ▼
Ubuntu Server 24.04 (máy ảo, IP tĩnh 192.168.8.10) ── Docker Engine ── 12 container
```

> **Quy ước – đọc kỹ trước khi làm:**
> - Khối lệnh `powershell` gõ trên **Windows** (dấu nhắc `PS C:\…>`). Khối lệnh `bash` gõ trên **server** (dấu nhắc dạng `dang@dangdang:~$`). Trước khi dán lệnh `bash`, nhìn đầu dòng: nếu đang là `PS C:\…>` thì gõ `ssh dang@192.168.8.10` trước.
> - `192.168.8.10`: số thứ ba (`8`) là dải mạng VMnet8 trên máy này (mục 2.2) – máy khác có thể là số khác.
> - Thay `dang` bằng tên đăng nhập của server, `DTC245200879` bằng MSSV của bạn (cũng là tên Organization trên GitHub).
> - Khi gõ trong terminal, chuyển bộ gõ tiếng Việt (EVKey/Unikey) sang chế độ **E**: chế độ Telex biến `yes` thành `yé`, làm hỏng các lệnh có chữ `s, f, r, x, j`.

## 0. Yêu cầu của đề ↔ phần trong repo

| # | Yêu cầu (điểm) | Nằm ở đâu | Commit |
|---|---|---|---|
| 1 | GitHub, README, 3 commit (1.5) | toàn bộ repo, `README.md` | 1–3 |
| 2 | Web app + DB + công cụ quản lý DB (1.5) | `app/`, `db/init/`, service `db`, `phpmyadmin` | 1 |
| 3 | Nginx reverse proxy + HTTPS/headers (1.5) | `nginx/`, `scripts/gen-cert.sh` | 1 |
| 4 | Prometheus + Grafana (1.5) | `docker-compose.monitoring.yml`, `monitoring/` | 2 |
| 5 | Loki + Promtail + LogQL (1.5) | `docker-compose.logging.yml`, `logging/` | 3 |
| 6 | Hardening ≥ 3–4 biện pháp (1.5) | mọi file compose/nginx + cấu hình Ubuntu (mục 8) | 1–3 |
| 7 | Tổng thể, demo, hiểu bài (1.0) | mục 9, 10, 12 | — |

---

## 1. Chuẩn bị trên Windows và GitHub

1. **Docker Desktop** trên Windows không dùng cho dự án này: chuột phải biểu tượng cá voi ở khay hệ thống → *Quit Docker Desktop* (để dành RAM cho máy ảo). Gõ `docker` trên Windows là gọi Docker Desktop, **không phải** Docker trong server.
2. **GitHub** – yêu cầu số 1 của đề là đặt tên theo MSSV. GitHub chỉ cho mỗi người một tài khoản cá nhân miễn phí, nên giữ tài khoản hiện tại và tạo thêm một **Organization** tên MSSV:
   - Đăng nhập tài khoản của bạn → dấu **+** góc trên bên phải → **New organization** → gói **Free** → *Organization name*: `DTC245200879`; *This organization belongs to*: *My personal account* → *Next* → bỏ qua bước mời thành viên → *Complete setup*.
   - Tạo repo: **+** → **New repository** → *Owner*: chọn **DTC245200879** (không chọn tài khoản cá nhân) → tên `inventory-system`, *Public*, **không** bật *Add README*, *.gitignore* để *No .gitignore*, *License* để *No license* (repo phải trống) → *Create repository*.
   - **Kết quả đúng:** GitHub hiện trang *Quick setup* với đường dẫn `git@github.com:DTC245200879/inventory-system.git`. Repo nằm trong Organization nên xem ở `github.com/DTC245200879/inventory-system` (không nằm trong danh sách repo của tài khoản cá nhân).
3. Tải file **`inventory-system.zip` mới nhất** về thư mục *Downloads*. Nếu trong Downloads có nhiều bản (`inventory-system (1).zip`…), xoá các bản cũ và đổi tên bản mới nhất thành `inventory-system.zip`.

---

## 2. Tạo máy ảo Ubuntu Server (VMware Workstation)

### 2.1 Chuẩn bị
- **VMware Workstation** (máy chưa có thì tải VMware Workstation Pro – hiện miễn phí – từ trang hỗ trợ của Broadcom).
- **Ubuntu Server 24.04 LTS**: https://releases.ubuntu.com/24.04/ → tải file `ubuntu-24.04.x-live-server-amd64.iso` (khoảng 3 GB). **Không bấm đúp** vào file ISO trong Windows: Windows sẽ mở nó thành ổ đĩa ảo và giữ file, VMware sẽ báo *Cannot connect file … as a CD*. Nếu lỡ mở, vào File Explorer chọn ổ đĩa đó → *Eject*.

### 2.2 Xem dải mạng NAT của VMware (VMnet8)
VMware → **Edit → Virtual Network Editor** → chọn dòng **VMnet8** (Type: *NAT*):
- Ghi lại **Subnet Address**, ví dụ `192.168.8.0` – số thứ ba gọi là **X** (ở máy này X = 8).
- Bấm **NAT Settings…** → ghi lại **Gateway IP** (thường là `192.168.X.2`).

Máy ảo sẽ dùng **IP tĩnh `192.168.X.10`** (ở máy này là `192.168.8.10`). IP này nằm ngoài dải VMware tự cấp (`.128–.254`) nên không bao giờ bị trùng với máy ảo khác, và không đổi qua các lần khởi động.

### 2.3 Tạo máy ảo
VMware → **File → New Virtual Machine…**:
1. **Typical (recommended)** → *Next*
2. *Install from*: chọn **I will install the operating system later** (tránh chế độ *Easy Install* tự cài) → *Next*
3. *Guest operating system*: **Linux**, *Version*: **Ubuntu 64-bit** → *Next*
4. *Virtual machine name*: tuỳ ý (vd. `ubuntu-inventory`); *Location*: ổ đĩa còn nhiều chỗ trống → *Next*
5. *Maximum disk size*: **20 GB** (dư dả thì 30 GB) → *Next*
6. **Customize Hardware…**:
   - *Memory*: **4096 MB**
   - *Processors*: **2**
   - *New CD/DVD (SATA)*: chọn **Use ISO image file** → *Browse* → chọn file ISO Ubuntu; tick **Connect at power on**
   - *Network Adapter*: **NAT** (mặc định)
   - Bấm *Close* → **Finish**.

### 2.4 Cài Ubuntu Server
Bấm **Power on this virtual machine** → chọn *Try or Install Ubuntu Server*. (Nếu màn hình báo *Operating System not found* nghĩa là máy ảo chưa gắn được file ISO – xem lại mục 2.1 và 2.3.) Bấm chuột vào cửa sổ máy ảo để gõ (nhấn **Ctrl+Alt** để nhả chuột ra). Dùng phím mũi tên để di chuyển, **Space** để tick, **Enter** để chọn:

1. Language: **English**
2. *Installer update available* → *Continue without updating*
3. Keyboard: English (US) → *Done*
4. Type of installation: **Ubuntu Server** → *Done*
5. **Network – đặt IP tĩnh:** chọn card mạng (thường là `ens33`) → Enter → **Edit IPv4** → *IPv4 Method*: **Manual** → điền:
   - *Subnet*: `192.168.8.0/24`
   - *Address*: `192.168.8.10`
   - *Gateway*: `192.168.8.2`
   - *Name servers*: `192.168.8.2, 8.8.8.8`
   - *Search domains*: để trống

   → **Save** → *Done*. (Nếu lỡ để tự động/DHCP thì sau khi cài vẫn đặt IP tĩnh được – xem mục 11, dòng *"IP của máy ảo bị đổi"*.)
6. Proxy: để trống → *Done*
7. Ubuntu archive mirror: để mặc định, chờ kiểm tra xong → *Done* (bước này báo lỗi mạng nghĩa là IP/Gateway ở bước 5 bị sai)
8. Storage: *Use an entire disk* → **bỏ tick "Set up this disk as an LVM group"** (để LVM thì Ubuntu chỉ cấp khoảng một nửa ổ đĩa – nếu lỡ để, xem mục 3.1) → *Done* → *Done* → *Continue*
9. Profile: *Your name*; *Your server's name* (vd. `dangdang`); *Pick a username*: chữ thường, không dấu (vd. `dang`); mật khẩu mạnh → *Done*
10. Upgrade to Ubuntu Pro: *Skip for now* → *Continue*
11. SSH configuration: **tick "Install OpenSSH server"** → *Done*
12. Featured server snaps: **không chọn gì** (đặc biệt không chọn `docker` – Docker bản chính thức được cài ở bước 3) → *Done*
13. Chờ cài xong → **Reboot Now**. Nếu hiện *Please remove the installation medium, then press ENTER* → nhấn Enter.

**Kết quả đúng:** sau khi khởi động lại, cửa sổ máy ảo hiện dòng `<tên-server> login:`. Đăng nhập thử rồi gõ `hostname -I` → phải ra `192.168.8.10`.

### 2.5 SSH từ Windows vào server
Từ đây **không gõ lệnh trong cửa sổ VMware** (không dán lệnh vào đó được) – mọi thao tác làm qua SSH. Mở PowerShell (hoặc Windows Terminal):
```powershell
ssh dang@192.168.8.10
```
Lần đầu sẽ hỏi *Are you sure you want to continue connecting* → gõ `yes` → nhập mật khẩu (khi gõ không hiện ký tự).

**Kết quả đúng:** dấu nhắc đổi thành `dang@<tên-server>:~$` (vd. `dang@dangdang:~$`). Dán lệnh bằng Ctrl+V hoặc chuột phải. Nếu báo `Connection refused`: server chưa có OpenSSH → trong cửa sổ VMware chạy `sudo apt install -y openssh-server` rồi `sudo systemctl enable --now ssh.socket`.

---

## 3. Cài đặt trên server

### 3.1 Cập nhật hệ thống, múi giờ, công cụ
```bash
sudo apt update && sudo apt -y upgrade
sudo timedatectl set-timezone Asia/Ho_Chi_Minh
sudo apt install -y unzip git
df -h /
```
Ở lệnh `df -h /`, cột *Size* của dòng `/` phải xấp xỉ dung lượng ổ ảo (vd. 18–19G với ổ 20 GB). Nếu chỉ khoảng một nửa (vd. 9.8G) là do lúc cài để LVM → mở rộng ra toàn bộ ổ:
```bash
sudo lvextend -r -l +100%FREE /dev/ubuntu-vg/ubuntu-lv
df -h /
```

### 3.2 Cài Docker Engine (bản chính thức của Docker)
```bash
curl -fsSL https://get.docker.com -o get-docker.sh
sudo sh get-docker.sh
sudo usermod -aG docker $USER
exit
```
Lệnh `exit` đăng xuất khỏi server (quyền nhóm `docker` chỉ có hiệu lực sau khi đăng nhập lại). Chạy lại `ssh dang@192.168.8.10`, rồi kiểm tra:
```bash
docker version
docker compose version
docker run --rm hello-world
```
**Kết quả đúng:** `docker version` có cả phần *Client* và *Server*, phần *Server* ghi `Docker Engine - Community` và *OS/Arch* là `linux/amd64` (nếu thấy `Docker Desktop` hoặc `windows/amd64` là bạn đang gõ nhầm trên Windows); lệnh cuối in ra `Hello from Docker!`.

> Ghi vào báo cáo: user thuộc nhóm `docker` có quyền tương đương root, nên chỉ thêm tài khoản quản trị tin cậy.

---

## 4. Đưa mã nguồn lên server và nối với GitHub

### 4.1 Chép file zip từ Windows lên server
Mở **một cửa sổ PowerShell mới** (trên Windows, không phải cửa sổ SSH):
```powershell
scp "$HOME\Downloads\inventory-system.zip" dang@192.168.8.10:~/
```
Quay lại cửa sổ SSH:
```bash
unzip inventory-system.zip
cd ~/inventory-system
ls -a
```
**Kết quả đúng:** thấy `docker-compose.yml`, `app`, `db`, `nginx`, `scripts`, `.gitignore`…

### 4.2 Cấu hình Git và SSH key cho GitHub
```bash
git config --global user.name "Chu Hải Đăng - DTC245200879"
git config --global user.email "email-github-cua-ban@gmail.com"
ssh-keygen -t ed25519 -C "email-github-cua-ban@gmail.com"
cat ~/.ssh/id_ed25519.pub
```
Tên người commit có kèm MSSV để thầy nhìn lịch sử commit là nhận ra bạn; email nên là email của tài khoản GitHub để commit được gắn với tài khoản. Khi chạy `ssh-keygen`, **chỉ nhấn Enter 3 lần, không gõ gì** (câu đầu hỏi *tên file lưu khoá*, không phải mật khẩu – gõ chữ vào sẽ tạo khoá sai chỗ). Copy cả dòng `ssh-ed25519 AAAA…` vừa in ra → GitHub (đăng nhập tài khoản cá nhân của bạn) → *Settings* → *SSH and GPG keys* → *New SSH key* → dán vào ô *Key* → *Add SSH key*. Kiểm tra:
```bash
ssh -T git@github.com
```
Gõ `yes` khi được hỏi. **Kết quả đúng:** `Hi <tên-tài-khoản-cá-nhân>! You've successfully authenticated, but GitHub does not provide shell access.` (Bạn là chủ Organization nên tài khoản này push được vào repo của Organization.)

### 4.3 Khởi tạo repo Git
```bash
cd ~/inventory-system
git init -b main
git remote add origin git@github.com:DTC245200879/inventory-system.git
git remote -v
```

---

## 5. BƯỚC 1 – Web app + MySQL + phpMyAdmin + Nginx → **Commit 1**

### 5.1 Những gì đã có
- **Web app** (`app/app.py`, Flask): đăng nhập; Tổng quan (KPI + cảnh báo sắp hết hàng); Sản phẩm (CRUD, tìm kiếm); Nhà cung cấp (CRUD); phiếu **Nhập kho** / **Xuất kho** (xuất kho kiểm tra tồn, khoá dòng `SELECT … FOR UPDATE` để không bị âm kho); Lịch sử giao dịch.
- **CSDL** (`db/init/01-schema.sql`): 3 bảng `suppliers`, `products`, `stock_transactions` + dữ liệu mẫu. MySQL tự chạy các file trong `db/init/` ở **lần khởi động đầu tiên**.
- **User DB** (`db/init/02-users.sh`): tạo `inventory_app` (chỉ CRUD) và `exporter` (chỉ đọc thống kê).
- **Nginx** (`nginx/`): HTTP→HTTPS, reverse proxy `/` → app, `/phpmyadmin/` → phpMyAdmin, `/grafana/` → Grafana; security headers; rate-limit.

### 5.2 Chạy
```bash
cd ~/inventory-system
bash scripts/gen-env.sh
bash scripts/gen-cert.sh
docker compose up -d --build
```
- `gen-env.sh` in ra mật khẩu đăng nhập web app, phpMyAdmin, Grafana và dòng `PUBLIC_URL=https://192.168.8.10` (tự lấy theo IP server) → **ghi lại** (xem lại bất cứ lúc nào bằng `cat .env`). `gen-cert.sh` tạo chứng chỉ cho đúng IP đó.
- Lần đầu phải tải image MySQL, phpMyAdmin, Nginx, Python và build app nên mất vài phút.

Kiểm tra trạng thái (chạy lại vài lần trong 1–2 phút):
```bash
docker compose ps
```
**Kết quả đúng:** 4 container `inventory-db`, `inventory-app`, `inventory-phpmyadmin`, `inventory-nginx` đều *Up*; db, app, nginx có thêm *(healthy)*.

### 5.3 Kiểm tra & chụp ảnh cho báo cáo

| Kiểm tra | Cách làm | Kết quả đúng |
|---|---|---|
| Website | Trình duyệt **trên Windows** mở https://192.168.8.10 → *Advanced → Proceed to 192.168.8.10* | Trang đăng nhập; đăng nhập bằng `ADMIN_*` trong `.env` |
| Nghiệp vụ | Nhập kho 10 cái; xuất kho nhiều hơn số tồn | Báo "Không đủ hàng"; tồn kho cập nhật đúng |
| phpMyAdmin | https://192.168.8.10/phpmyadmin/ , đăng nhập `inventory_app` | Thấy DB `inventory_db` với 3 bảng |
| HTTP→HTTPS | `curl -I http://192.168.8.10` (trên server) | `301 Moved Permanently`, `Location: https://192.168.8.10/` |
| Security headers | `curl -kI https://192.168.8.10/login` | Có `Strict-Transport-Security`, `Content-Security-Policy`, `X-Frame-Options`, `X-Content-Type-Options`; `Server: nginx` không kèm version |
| Chứng chỉ | Bấm biểu tượng cảnh báo/ổ khoá trên thanh địa chỉ | CN=192.168.8.10, tự ký, hạn 1 năm |

📸 Chụp: `docker compose ps`, trang Tổng quan, Sản phẩm, phiếu xuất bị từ chối, phpMyAdmin, kết quả 2 lệnh `curl`.

### 5.4 Commit 1
```bash
git add .gitignore .gitattributes .env.example README.md docker-compose.yml app db nginx scripts docs/screenshots
git status
git commit -m "feat: trien khai web quan ly kho (Flask) + MySQL + phpMyAdmin + Nginx reverse proxy HTTPS"
git push -u origin main
```
⚠️ Trước khi commit, `git status` **không được** có `.env`, `server.key`, `server.crt` (đã được `.gitignore` chặn).

---

## 6. BƯỚC 2 – Giám sát Prometheus + Grafana → **Commit 2**

### 6.1 Thành phần

| Service | Thu thập gì | Cổng nội bộ |
|---|---|---|
| `prometheus` | Kéo (pull) metrics từ các target 15 giây/lần, lưu 7 ngày, có alert rules | 9090 (bind 127.0.0.1) |
| `cadvisor` | CPU/RAM/network **từng container** | 8080 |
| `node-exporter` | CPU/RAM/disk của server Ubuntu | 9100 |
| `mysqld-exporter` | Trạng thái MySQL: kết nối, query/s, traffic | 9104 |
| `nginx-exporter` | Đọc `stub_status` của Nginx: request, connection | 9113 |
| `app` `/metrics` | Request theo status, độ trễ, **số phiếu nhập/xuất**, đăng nhập lỗi, số SP sắp hết | 5000 |
| `grafana` | Datasource + dashboard được **provision tự động** | 3000 → /grafana/ |

### 6.2 Chạy
```bash
docker compose -f docker-compose.yml -f docker-compose.monitoring.yml up -d
docker compose -f docker-compose.yml -f docker-compose.monitoring.yml ps
```
**Kết quả đúng:** có thêm 6 container `prometheus`, `grafana`, `cadvisor`, `node-exporter`, `mysqld-exporter`, `nginx-exporter`, tất cả *Up*.

### 6.3 Kiểm tra
1. **Prometheus** chỉ mở bên trong server (`127.0.0.1:9090`), nên từ Windows phải đi qua **đường hầm SSH**. Mở một PowerShell mới và **giữ cửa sổ này mở** trong lúc xem:
   ```powershell
   ssh -L 9090:127.0.0.1:9090 dang@192.168.8.10
   ```
   Trên trình duyệt **Windows** mở http://localhost:9090/targets (`localhost` ở đây là máy Windows, đường hầm SSH chuyển tiếp sang server) → các job `inventory-app`, `cadvisor`, `node`, `mysql`, `nginx`, `prometheus` đều **UP** (`loki`, `promtail` DOWN là bình thường vì chưa làm bước 3).
2. **Grafana:** https://192.168.8.10/grafana/ → đăng nhập `GRAFANA_*` → *Dashboards → Inventory → "Inventory - Giám sát hệ thống"*: các hàng Tổng quan, Container, Web server & app, Database đều có số liệu.
3. Truy vấn thử trong Prometheus (tab *Graph*) để chụp ảnh:
   ```promql
   up
   sum by (name) (rate(container_cpu_usage_seconds_total{name=~"inventory-.+"}[1m])) * 100
   rate(nginx_http_requests_total[1m])
   mysql_global_status_threads_connected
   sum by (type) (inventory_stock_movements_total)
   ```
4. Tạo tải để biểu đồ có số liệu (trên server):
   ```bash
   for i in $(seq 1 300); do curl -sk -o /dev/null https://192.168.8.10/login; curl -sk -o /dev/null https://192.168.8.10/khong-ton-tai; done
   ```
5. (Tuỳ chọn, cộng điểm trình bày) Import dashboard cộng đồng: Grafana → *Dashboards → New → Import* ID **1860** (Node Exporter Full), **14057** (MySQL), **12708** (NGINX exporter).

📸 Chụp: Prometheus Targets, dashboard Grafana (đủ 3 nhóm container / web / DB), trang *Alerts* của Prometheus.

### 6.4 Commit 2
```bash
git add docker-compose.monitoring.yml monitoring
git commit -m "feat: giam sat he thong voi Prometheus + Grafana (cAdvisor, node/mysqld/nginx exporter, app metrics)"
git push
```

---

## 7. BƯỚC 3 – Log tập trung Loki + Promtail → **Commit 3**

### 7.1 Cách hoạt động

```
container (stdout/stderr) ──► Docker ──► Promtail (docker_sd qua docker.sock, chỉ đọc)
   gắn nhãn: container, service, stream, level (app), status_class (nginx)
                                   │ push HTTP
                                   ▼
                                 Loki (lưu 7 ngày, index theo nhãn)
                                   ▲ LogQL
                                 Grafana (Explore / panel log)
```

- Web app ghi log dạng **logfmt**: `level=info event=stock_out user=admin sku=LAP-001 qty=3 stock_after=9`
- Nginx ghi access log dạng **JSON**: `{"time":…,"method":"GET","uri":"/","status":200,…}`

### 7.2 Chạy
```bash
docker compose -f docker-compose.yml -f docker-compose.monitoring.yml -f docker-compose.logging.yml up -d
echo 'COMPOSE_FILE=docker-compose.yml:docker-compose.monitoring.yml:docker-compose.logging.yml' >> .env
docker compose ps
```
Dòng `echo` lưu danh sách 3 file compose vào `.env`; từ giờ chỉ cần gõ `docker compose ps`, `docker compose logs app`… là áp dụng cho cả hệ thống.

**Kết quả đúng:** `docker compose ps` liệt kê **12 container**, tất cả *Up*.

Vào web app thao tác vài lần (đăng nhập sai 2–3 lần, nhập kho, xuất kho) để có log.

### 7.3 Truy vấn LogQL (Grafana → Explore → chọn **Loki**)

| # | Mục đích | LogQL |
|---|---|---|
| 1 | Tất cả log của web app | `{service="app"}` |
| 2 | Các phiếu **xuất kho** (lọc theo trường) | `{service="app"} \| logfmt \| event="stock_out"` |
| 3 | Đăng nhập **thất bại** (phát hiện brute-force) | `{service="app"} \| logfmt \| event="login_failed"` |
| 4 | Request lỗi qua Nginx | `{service="nginx"} \| json \| status >= 400` |
| 5 | Đếm request theo nhóm status (metric query) | `sum by (status_class) (count_over_time({service="nginx", status_class=~".+"}[5m]))` |
| 6 | Top 5 URL được gọi nhiều nhất | `topk(5, sum by (uri) (count_over_time({service="nginx", stream="stdout"} \| json \| __error__="" [15m])))` |
| 7 | Log lỗi của mọi container | `{container=~"inventory-.+"} \|~ "(?i)error\|exception"` |

> Đề yêu cầu tối thiểu 2–3 query: nên trình bày #2, #3, #4 (log query) và #5 (metric query). Giải thích cú pháp: `{…}` là **stream selector**, `|=`/`|~` là **line filter**, `| json`/`| logfmt` là **parser**, `| status >= 400` là **label filter**, `count_over_time(…[5m])` là **range aggregation**.

Dashboard Grafana đã có sẵn hàng "Log tập trung (Loki)".

📸 Chụp: Explore với từng query, panel log trên dashboard, Prometheus target `loki`/`promtail` UP.

### 7.4 Commit 3
```bash
git add docker-compose.logging.yml logging
git commit -m "feat: log tap trung voi Loki + Promtail, truy van LogQL"
git push
```
Commit bổ sung (không bắt buộc): `git add README.md docs scripts .env.example && git commit -m "docs: cap nhat huong dan truy cap qua IP, hardening, anh minh chung" && git push`

### 7.5 Tắt/mở hệ thống những ngày sau
- **Tắt:** trên server chạy `sudo shutdown now`.
- **Mở lại:** mở VMware → chọn máy ảo → **Power on** → chờ khoảng 1 phút → `ssh dang@192.168.8.10` → `cd ~/inventory-system && docker compose ps`. Các container tự khởi động lại nhờ `restart: unless-stopped`. Khi đóng cửa sổ VMware mà máy ảo đang chạy, chọn **Run in Background** để máy ảo tiếp tục chạy nền.

---

## 8. Hardening – biện pháp và cách chứng minh

### 8.1 Tường lửa UFW trên Ubuntu
```bash
sudo ufw allow OpenSSH
sudo ufw allow 80/tcp
sudo ufw allow 443/tcp
sudo ufw enable
sudo ufw status verbose
```
⚠️ Phải `allow OpenSSH` **trước** `ufw enable`, nếu không sẽ mất kết nối SSH (khi đó đăng nhập trong cửa sổ VMware để sửa).

> Lưu ý khi trình bày: Docker tự thêm luật iptables cho các cổng được publish nên UFW không chặn được chúng. Dự án chỉ publish 80/443 (Nginx) và 9090 trên `127.0.0.1`, vì vậy không lộ thêm cổng nào – chứng minh bằng `sudo ss -tlnp`.

### 8.2 Bảng biện pháp (chạy lệnh trên server)

| # | Biện pháp | Cấu hình ở đâu | Lệnh kiểm chứng → kết quả đúng |
|---|---|---|---|
| 1 | **Non-root container** | `app/Dockerfile` (`USER 10001`), image `nginx-unprivileged`, `user:` trong compose | `docker exec inventory-app id` → `uid=10001`; `docker exec inventory-nginx id` → `uid=101` |
| 2 | **Read-only filesystem + bỏ capabilities** | `read_only: true`, `cap_drop: [ALL]`, `no-new-privileges` | `docker exec inventory-app touch /app/x` → *Read-only file system*; `docker inspect inventory-app --format '{{.HostConfig.ReadonlyRootfs}} {{.HostConfig.CapDrop}} {{.HostConfig.SecurityOpt}}'` |
| 3 | **Network isolation** | 3 network; `backend` là `internal: true`; DB không publish port | `docker network inspect inventory_backend --format '{{.Internal}}'` → `true`; `docker exec inventory-nginx wget -qO- -T2 http://db:3306` → *bad address 'db:3306'* (Nginx không thấy DB); `docker run --rm --network inventory_backend alpine ping -c1 -W2 8.8.8.8` → *Network unreachable* |
| 4 | **Mật khẩu mạnh, không lộ bí mật** | `scripts/gen-env.sh` (24–32 ký tự ngẫu nhiên), `.env` trong `.gitignore`, mật khẩu admin app được hash | Repo GitHub không có `.env`; `ls -l .env` → `-rw-------` |
| 5 | **Hạn chế quyền DB** | `db/init/02-users.sh`, `MYSQL_ROOT_HOST=localhost` | phpMyAdmin login `inventory_app` → thử `DROP TABLE products;` → **#1142 DROP command denied**; login `root` → bị từ chối; `docker exec inventory-db sh -c 'mysql -uroot -p"$MYSQL_ROOT_PASSWORD" -e "SHOW GRANTS FOR inventory_app"'` → chỉ có `SELECT, INSERT, UPDATE, DELETE` |
| 6 | **HTTPS + security headers** | `nginx/snippets/*.conf`, `server_tokens off`, TLS 1.2/1.3 | `curl -kI https://192.168.8.10/login` |
| 7 | **Rate limit chống brute-force** | `limit_req_zone … rate=10r/m` cho `/login` | `for i in $(seq 1 15); do curl -sk -o /dev/null -w "%{http_code} " https://192.168.8.10/login; done` → xuất hiện `429` |
| 8 | **Giấu endpoint nội bộ** | `/metrics` trả 404 qua Nginx; Prometheus bind `127.0.0.1`; stub_status chỉ ở cổng nội bộ | `curl -sk -o /dev/null -w "%{http_code}\n" https://192.168.8.10/metrics` → `404`; `sudo ss -tlnp` → ra ngoài chỉ có 22, 80, 443; 9090 nằm trên `127.0.0.1` |
| 9 | **Giới hạn tài nguyên & xoay vòng log** | `mem_limit`, `pids_limit`, log `max-size: 10m` | `docker stats --no-stream` |
| 10 | **Bảo mật ứng dụng** | CSRF token, cookie `Secure/HttpOnly/SameSite`, chống open-redirect | Trình duyệt → F12 → *Application* → *Cookies* |
| 11 | **Hardening hệ điều hành** | UFW chỉ mở 22/80/443; máy ảo nằm trong mạng NAT nội bộ VMnet8 (chỉ máy host truy cập được); SSH key cho GitHub; cập nhật bảo mật tự động | `sudo ufw status`; `sudo sshd -T \| grep -i permitrootlogin` → `without-password`; `systemctl is-active unattended-upgrades` → `active` |

> Lưu ý trung thực trong báo cáo: **Promtail** và **cAdvisor** cần đọc Docker (`docker.sock`, thư mục hệ thống) nên không chạy hoàn toàn non-root được. Đây là đánh đổi phổ biến; rủi ro đã được giảm bằng mount chỉ đọc (`:ro`) và đặt trong mạng `monitoring` riêng.

### 8.3 Một lệnh lấy toàn bộ minh chứng
Sau khi đã bật UFW (8.1) và chạy đủ 3 phần, chạy:
```bash
cd ~/inventory-system
bash scripts/kiem-chung.sh
```
Script hỏi mật khẩu sudo một lần (để đọc UFW và cấu hình SSH), rồi in 9 nhóm kiểm tra – container, Prometheus targets, LogQL, non-root/read-only, cô lập mạng, HTTPS/headers/rate-limit, quyền DB, bí mật, cổng mở/UFW – mỗi dòng đánh dấu **[ĐẠT]** hoặc **[CHƯA ĐẠT]**. Script chỉ đọc trạng thái, không đổi cấu hình và không in mật khẩu. Lần đầu nó tải image `busybox` (rất nhỏ) để thử mạng `backend` có ra Internet được không.

**Kết quả đúng:** dòng cuối `KẾT QUẢ: … mục đạt, 0 mục chưa đạt`. Chụp ảnh từng nhóm để đưa vào chương 4 của báo cáo. (Phần thử rate-limit làm `/login` trả 429 trong khoảng 1 phút, chỉ với chính server; trình duyệt trên Windows không bị ảnh hưởng.)

---

## 9. Kịch bản demo (≈ 7 phút)

1. VMware: máy ảo đang chạy. PowerShell: `ssh dang@192.168.8.10` → `cd ~/inventory-system && docker compose ps` – 12 container *Up*, db/app/nginx *healthy*.
2. GitHub: 3 commit có nội dung rõ ràng, README, không có `.env`.
3. Website (trình duyệt Windows): đăng nhập → Tổng quan → nhập kho → xuất kho vượt tồn bị chặn → lịch sử.
4. phpMyAdmin: bảng `stock_transactions` vừa có dòng mới; thử `DROP TABLE` bị từ chối.
5. Trên server: `curl -I http://192.168.8.10` (301) và `curl -kI https://192.168.8.10/login` (headers).
6. SSH tunnel → Prometheus Targets → Grafana dashboard (container / Nginx / MySQL / nghiệp vụ).
7. Grafana Explore → chạy 3–4 câu LogQL ở mục 7.3 (đăng nhập sai trước để có log `login_failed`).
8. Hardening: `bash scripts/kiem-chung.sh` – giải thích từng nhóm khi kết quả hiện ra (non-root, read-only, mạng internal, quyền DB, headers, rate-limit 429, UFW).

---

## 10. Dàn ý báo cáo (≥ 10 trang)

**Bìa** (theo mẫu báo cáo thực tập): trường/khoa, tên môn, tên đề tài "Triển khai và quản trị Hệ thống Quản lý Kho hàng", họ tên, MSSV, lớp, GVHD, năm.

1. **Chương 1 – Giới thiệu** (1 trang): bài toán quản lý kho, mục tiêu, phạm vi, yêu cầu của đề.
2. **Chương 2 – Cơ sở lý thuyết** (2 trang): ảo hoá và VMware Workstation (mạng NAT VMnet8, IP tĩnh); Linux server và SSH; Docker & Docker Compose; reverse proxy & TLS; mô hình pull của Prometheus, exporter, PromQL; Grafana; Loki/Promtail và LogQL; nguyên tắc hardening (least privilege, defense in depth).
3. **Chương 3 – Thiết kế hệ thống** (2 trang): mô hình triển khai (Windows → VMware Workstation → Ubuntu Server 24.04 → Docker Engine → 12 container); cấu hình máy ảo (2 vCPU, 4 GB RAM, 20 GB, IP tĩnh `192.168.8.10` trong mạng NAT VMnet8); sơ đồ kiến trúc container (lấy từ README); 3 network; bảng service/cổng; ERD 3 bảng; chức năng web app.
4. **Chương 4 – Triển khai và kết quả** (5+ trang) – mỗi mục: cấu hình chính (trích đoạn ngắn) + ảnh + giải thích
   - 4.1 Cài đặt server (VMware, Ubuntu, Docker Engine)
   - 4.2 Quản lý mã nguồn GitHub (ảnh danh sách commit, README)
   - 4.3 Triển khai web app + MySQL + phpMyAdmin
   - 4.4 Nginx reverse proxy, HTTPS, security headers
   - 4.5 Giám sát Prometheus + Grafana
   - 4.6 Log tập trung Loki + LogQL (ảnh 3+ query, giải thích từng query)
   - 4.7 Hardening mức container và mức hệ điều hành (bảng mục 8 + ảnh minh chứng)
5. **Chương 5 – Kết luận** (1 trang): kết quả đạt được; hạn chế (chứng chỉ tự ký, một server, chưa có Alertmanager/backup); hướng phát triển (Let's Encrypt + tên miền, backup DB định kỳ bằng cron, CI/CD GitHub Actions, Alertmanager gửi Telegram/Email, Docker secrets, Fail2ban cho SSH).
6. **Tài liệu tham khảo**: docs.docker.com, ubuntu.com/server/docs, nginx.org, prometheus.io, grafana.com/docs/loki…

**Danh sách ảnh cần chụp (~18 ảnh):** VMware Virtual Network Editor (VMnet8) + cấu hình máy ảo · `hostnamectl` + `docker version` · `docker compose ps` · GitHub commits · 3–4 trang web app · phpMyAdmin · lỗi #1142 · chứng chỉ · `curl -I` 301 · `curl -kI` headers · Prometheus Targets · Grafana dashboard (2 ảnh) · 3 ảnh LogQL · kết quả `bash scripts/kiem-chung.sh` (3–4 ảnh).

---

## 11. Lỗi thường gặp

| Hiện tượng | Nguyên nhân / cách xử lý |
|---|---|
| Gõ `sudo`, `df`, `unzip`, `ip`… báo *not recognized* / *Command not found* | Đang gõ trong PowerShell của Windows (dấu nhắc `PS C:\…>`). Gõ `ssh dang@192.168.8.10` trước, thấy `dang@<tên-server>:~$` rồi mới dán lệnh |
| `docker version` hiện `Docker Desktop` / `windows/amd64`, hoặc lỗi `dockerDesktopLinuxEngine` | Lệnh đang chạy trên Windows (Docker Desktop), không phải trên server. SSH vào server rồi chạy lại |
| `Please type 'yes', 'no' or the fingerprint` lặp mãi | Bộ gõ tiếng Việt đang ở Telex nên `yes` bị biến thành chữ khác. Chuyển EVKey/Unikey sang **E** rồi gõ lại |
| VMware báo *Operating System not found* / *Network boot from Intel E1000* | Máy ảo chưa gắn ISO: *VM → Settings → CD/DVD (SATA)* → *Use ISO image file* → chọn file ISO, tick *Connect at power on*. Nếu báo *Cannot connect file … as a CD*: Windows đang mở ISO thành ổ đĩa ảo → *Eject* ổ đó |
| VMware báo lỗi *Virtualized Intel VT-x/EPT is not supported* hoặc nhắc tới Hyper-V | *VM → Settings → Processors* → bỏ tick *Virtualize Intel VT-x/EPT or AMD-V/RVI* → OK |
| `ssh: … Connection timed out` | Sai IP (máy ảo đã đổi IP – xem dòng dưới) hoặc máy ảo chưa bật |
| `ssh: … Connection refused` | Máy ảo chưa có/chưa chạy OpenSSH: trong cửa sổ VMware chạy `sudo apt install -y openssh-server` rồi `sudo systemctl enable --now ssh.socket` |
| IP của máy ảo bị đổi (lúc cài là `.132`, sau lại là `.133`…) | Do để nhận IP tự động (DHCP). Đặt IP tĩnh: SSH vào bằng IP hiện tại (`hostname -I`), tạo file `/etc/netplan/99-static.yaml` với `dhcp4: false`, `addresses: [192.168.8.10/24]`, `routes: [{to: default, via: 192.168.8.2}]`, `nameservers: {addresses: [192.168.8.2, 8.8.8.8]}` → `sudo chmod 600` file đó → `sudo netplan apply` → SSH lại bằng `192.168.8.10` |
| `WARNING: REMOTE HOST IDENTIFICATION HAS CHANGED!` (sau khi cài lại máy ảo) | Trên Windows chạy `ssh-keygen -R 192.168.8.10` rồi SSH lại |
| Cài Ubuntu báo lỗi ở bước *mirror*, hoặc `apt update` không tải được | Sai Gateway/DNS khi đặt IP tĩnh: Gateway phải là `192.168.8.2`, Subnet `192.168.8.0/24` |
| `df -h /` chỉ khoảng một nửa ổ đĩa | Lúc cài để LVM → `sudo lvextend -r -l +100%FREE /dev/ubuntu-vg/ubuntu-lv` |
| `permission denied while trying to connect to the docker API at unix:///var/run/docker.sock` | Chưa đăng nhập lại sau `usermod -aG docker` → `exit` rồi SSH lại |
| `ssh-keygen` tạo khoá tên lạ (vd. `25022006`) trong thư mục dự án | Câu hỏi đầu là *tên file*, không phải mật khẩu. Xoá 2 file khoá sai (`rm -f ~/inventory-system/<tên> ~/inventory-system/<tên>.pub`) rồi chạy lại `ssh-keygen`, nhấn Enter 3 lần |
| `git push`: `ERROR: Repository not found` | Repo chưa tồn tại đúng chỗ: phải có repo trống `inventory-system` với *Owner* là Organization `DTC245200879` (mục 1) |
| `git push`: `Permission denied (publickey)` | Chưa thêm SSH key vào GitHub, hoặc remote đang dùng `https://`. Kiểm tra `ssh -T git@github.com` và `git remote -v` (phải là `git@github.com:DTC245200879/inventory-system.git`) |
| App không vào được DB / `Access denied` sau khi sửa `.env` | Script tạo user DB chỉ chạy ở lần đầu. Xoá dữ liệu rồi chạy lại: `docker compose down -v` → `docker compose up -d` |
| 502 Bad Gateway | App chưa sẵn sàng: `docker compose ps`, `docker compose logs app` |
| phpMyAdmin/Grafana chuyển hướng sai địa chỉ | `PUBLIC_URL` trong `.env` phải là `https://192.168.8.10` → sửa rồi `docker compose up -d` |
| Các panel container trên Grafana trống | Xem `docker logs inventory-cadvisor`. Phải dùng image `ghcr.io/google/cadvisor:v0.60.5` (bản cũ không đọc được container của Docker 29). Nếu log báo *permission denied*, thêm `privileged: true` vào service `cadvisor` rồi `docker compose up -d` |
| Grafana báo Loki "no data" | Chưa làm bước 3, hoặc chưa thao tác web để sinh log; chỉnh khoảng thời gian về *Last 15 minutes* |
| `no space left on device` | `df -h` để xem dung lượng; dọn image không dùng: `docker image prune -a` |
| Quên mật khẩu đăng nhập | `cat ~/inventory-system/.env` |

---

## 12. Câu hỏi vấn đáp thường gặp

- **Vì sao dùng reverse proxy?** Một điểm vào duy nhất, kết thúc TLS, thêm headers bảo mật, rate-limit, ẩn các service phía sau (DB, Grafana không lộ cổng).
- **Máy ảo kết nối mạng thế nào?** Card mạng của máy ảo gắn vào mạng **NAT VMnet8** của VMware: máy ảo ra Internet qua NAT để tải image; máy Windows chứa nó truy cập trực tiếp `192.168.8.10` qua card ảo VMnet8; các máy khác trong mạng Wi-Fi không thấy máy ảo → ít lộ diện.
- **Vì sao máy ảo cần IP tĩnh?** Nếu để DHCP, VMware có thể cấp IP khác sau mỗi lần cài lại/khởi động, mọi địa chỉ truy cập (SSH, website, `PUBLIC_URL`) sẽ sai. IP `.10` nằm ngoài dải tự cấp `.128–.254` nên không bao giờ trùng máy ảo khác.
- **SSH tunnel (`ssh -L 9090:127.0.0.1:9090`) là gì?** Mở cổng 9090 trên Windows; mọi kết nối tới đó được mã hoá qua SSH rồi chuyển tới `127.0.0.1:9090` của server → xem Prometheus mà không phải mở cổng ra ngoài.
- **Prometheus lấy dữ liệu thế nào?** Mô hình *pull*: định kỳ gọi HTTP `/metrics` của các target (exporter) theo `scrape_interval`.
- **Exporter là gì?** Chương trình chuyển số liệu của hệ thống (MySQL, Nginx, container) sang định dạng metrics của Prometheus.
- **Vì sao phải dùng cAdvisor v0.60.5?** Docker Engine 29 mặc định lưu image bằng *containerd image store*; cAdvisor bản cũ tìm layer theo cách lưu cũ nên không nhận ra container. Từ v0.54, cAdvisor hỏi trực tiếp containerd.
- **Loki khác Elasticsearch?** Loki chỉ đánh index **nhãn** (label), không index toàn bộ nội dung log → nhẹ, rẻ; lọc nội dung bằng LogQL lúc truy vấn.
- **Promtail lấy log ở đâu?** Từ Docker Engine qua `docker.sock` (chỉ đọc), tự phát hiện các container có nhãn project `inventory`.
- **Network `internal: true` nghĩa là gì?** Mạng không có gateway ra ngoài; chỉ container cùng mạng nói chuyện được với nhau, host cũng không truy cập trực tiếp được.
- **Vì sao UFW không chặn được cổng của Docker?** Docker ghi luật iptables riêng (chain `DOCKER`) xử lý trước luật của UFW → phải tự kiểm soát cổng publish trong file compose (chỉ Nginx publish; Prometheus bind `127.0.0.1`).
- **Vì sao app không dùng root của MySQL?** Nguyên tắc đặc quyền tối thiểu: nếu app bị khai thác SQL injection, kẻ tấn công cũng không DROP/ALTER/GRANT được.
- **Vì sao container non-root quan trọng?** Nếu thoát khỏi container (container escape), tiến trình chỉ có quyền thấp trên host thay vì root.
- **CSP có tác dụng gì?** Chỉ cho phép tải script/style từ chính website → giảm nguy cơ XSS.
- **Vì sao web app viết bằng Python Flask mà đề gợi ý PHP/Node.js?** Stack trong đề là *gợi ý*; em chọn Flask vì quen ngôn ngữ, các thành phần hạ tầng (MySQL, phpMyAdmin, Nginx, Prometheus, Grafana, Loki) giữ đúng stack gợi ý.
