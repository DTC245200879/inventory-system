# ---------- Inventory web app ----------
FROM python:3.12-slim

ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1 \
    PIP_NO_CACHE_DIR=1 \
    PIP_DISABLE_PIP_VERSION_CHECK=1

WORKDIR /app

# Hardening: tạo user thường (UID 10001), không chạy bằng root
RUN groupadd --system --gid 10001 app \
 && useradd --system --uid 10001 --gid app --home-dir /app --shell /usr/sbin/nologin app

COPY requirements.txt .
RUN pip install -r requirements.txt

# Code thuộc root, user "app" chỉ đọc được -> không sửa được mã nguồn nếu bị tấn công
COPY . .

USER 10001:10001
EXPOSE 5000

HEALTHCHECK --interval=30s --timeout=5s --start-period=20s --retries=3 \
  CMD python -c "import urllib.request; urllib.request.urlopen('http://127.0.0.1:5000/health', timeout=4)" || exit 1

# 1 worker + 4 threads: đủ cho demo và giữ /metrics nhất quán (1 process)
CMD ["gunicorn", "--bind", "0.0.0.0:5000", "--workers", "1", "--threads", "4", \
     "--worker-tmp-dir", "/tmp", "--access-logfile", "-", \
     "--access-logformat", "level=info event=http_request method=%(m)s path=%(U)s status=%(s)s duration_us=%(D)s ip=%({x-real-ip}i)s", \
     "wsgi:app"]
