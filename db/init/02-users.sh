#!/bin/bash
# ---------------------------------------------------------------
# Tạo tài khoản DB theo nguyên tắc "đặc quyền tối thiểu" (hardening):
#  - APP_DB_USER  : chỉ được SELECT/INSERT/UPDATE/DELETE trên inventory_db
#                   (không DROP/ALTER/GRANT) -> app bị chiếm cũng không xoá được bảng
#  - exporter     : chỉ đọc số liệu thống kê cho mysqld-exporter
# root chỉ đăng nhập được từ localhost (MYSQL_ROOT_HOST=localhost)
# ---------------------------------------------------------------
# (Không dùng "set -u": nếu file không có quyền thực thi, entrypoint MySQL sẽ "source" nó)
set -e

mysql --protocol=socket -uroot -p"${MYSQL_ROOT_PASSWORD}" <<-EOSQL
    CREATE USER IF NOT EXISTS '${APP_DB_USER}'@'%' IDENTIFIED BY '${APP_DB_PASSWORD}';
    GRANT SELECT, INSERT, UPDATE, DELETE ON \`${MYSQL_DATABASE}\`.* TO '${APP_DB_USER}'@'%';

    CREATE USER IF NOT EXISTS 'exporter'@'%' IDENTIFIED BY '${EXPORTER_DB_PASSWORD}' WITH MAX_USER_CONNECTIONS 3;
    GRANT PROCESS, REPLICATION CLIENT, SELECT ON *.* TO 'exporter'@'%';

    FLUSH PRIVILEGES;
EOSQL

echo "[init] Created users: ${APP_DB_USER} (CRUD on ${MYSQL_DATABASE}), exporter (metrics read-only)"
