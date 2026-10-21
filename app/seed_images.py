"""Gắn ảnh minh hoạ có sẵn (thư mục seed_images/, đặt tên theo mã SKU) cho các sản phẩm chưa có ảnh.

Chạy trên server:
    docker exec inventory-app python seed_images.py          # chỉ gắn cho sản phẩm CHƯA có ảnh
    docker exec inventory-app python seed_images.py --force  # ghi đè cả ảnh đã có

Ảnh trong seed_images/ là ảnh minh hoạ do AI tạo (không phải ảnh chính hãng), dùng cho dữ liệu demo.
Ảnh thật của từng sản phẩm tải lên ở trang Sửa sản phẩm.
"""
import logging
import os
import sys

import media
from app import Product, create_app, log_event

SEED_DIR = os.path.join(os.path.dirname(os.path.abspath(__file__)), "seed_images")


class _File:
    """Giả lập FileStorage để dùng lại đúng hàm kiểm tra ảnh tải lên."""

    def __init__(self, path):
        self._f = open(path, "rb")

    def read(self, n=-1):
        return self._f.read(n)

    def close(self):
        self._f.close()


def main(force=False):
    files = {os.path.splitext(n)[0].upper(): os.path.join(SEED_DIR, n)
             for n in sorted(os.listdir(SEED_DIR)) if n.lower().endswith((".jpg", ".jpeg", ".png", ".webp"))}
    done = skipped = 0
    with create_app().app_context():
        for p in Product.query.order_by(Product.sku).all():
            path = files.get(p.sku.upper())
            if not path:
                continue
            if media.image_version(p.id) and not force:
                print(f"  bỏ qua  {p.sku:<10} {p.name} (đã có ảnh)")
                skipped += 1
                continue
            f = _File(path)
            try:
                media.save_product_image(p.id, media.process_upload(f))
            finally:
                f.close()
            log_event(logging.INFO, "product_image_updated", sku=p.sku, product_id=p.id, source="seed")
            print(f"  đã gắn  {p.sku:<10} {p.name}")
            done += 1
    print(f"Xong: gắn {done} ảnh, bỏ qua {skipped}. Có ảnh mẫu cho: {', '.join(files) or '(không có)'}")


if __name__ == "__main__":
    main(force="--force" in sys.argv[1:])
