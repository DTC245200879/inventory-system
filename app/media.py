"""Ảnh sản phẩm: kiểm tra, chuẩn hoá và lưu trên volume riêng.

Mã nguồn của container vẫn chỉ đọc (read_only); chỉ thư mục MEDIA_DIR là volume
ghi được. Mọi ảnh tải lên đều được Pillow giải mã rồi mã hoá lại thành WebP:
  - chỉ nhận JPEG / PNG / WebP / GIF thật (kiểm tra nội dung, không tin đuôi file);
  - chặn ảnh "bom giải nén" (quá nhiều điểm ảnh);
  - xoay đúng chiều theo EXIF rồi bỏ toàn bộ metadata (vị trí GPS, máy chụp...);
  - thu nhỏ còn tối đa 800 px nên trang tải nhanh.
Tên file do server đặt theo id sản phẩm (<id>.webp), không dùng tên người dùng gửi lên.
"""
import io
import os
import tempfile
import warnings

from PIL import Image, ImageOps, UnidentifiedImageError

MEDIA_DIR = os.getenv("MEDIA_DIR", "/data/media")
ALLOWED_FORMATS = {"JPEG", "PNG", "WEBP", "GIF", "MPO"}  # MPO: ảnh JPEG từ một số điện thoại
MAX_BYTES = 8 * 1024 * 1024
MAX_SIDE = 800
# Giới hạn độ phân giải để container (giới hạn RAM 384 MB) không bị hết bộ nhớ khi giải mã.
# JPEG được giải mã thu nhỏ sẵn (draft) nên cho phép lớn hơn; PNG/WebP/GIF phải giải mã đủ.
MAX_PIXELS_JPEG = 100_000_000
MAX_PIXELS_OTHER = 12_000_000

Image.MAX_IMAGE_PIXELS = MAX_PIXELS_JPEG


class ImageError(ValueError):
    """Ảnh không hợp lệ; thông điệp hiển thị được cho người dùng."""


def _folder():
    return os.path.join(MEDIA_DIR, "products")


def product_path(pid):
    return os.path.join(_folder(), f"{int(pid)}.webp")


def image_version(pid):
    """Thời điểm sửa ảnh (dùng làm ?v= để trình duyệt tải lại khi đổi ảnh); None nếu chưa có ảnh."""
    try:
        return int(os.stat(product_path(pid)).st_mtime)
    except (FileNotFoundError, NotADirectoryError):
        return None


def process_upload(storage):
    """Đọc file tải lên (werkzeug FileStorage) và trả về bytes WebP đã chuẩn hoá."""
    data = storage.read(MAX_BYTES + 1)
    if not data:
        raise ImageError("File ảnh rỗng")
    if len(data) > MAX_BYTES:
        raise ImageError("Ảnh lớn hơn 8 MB")
    try:
        with warnings.catch_warnings():
            warnings.simplefilter("error", Image.DecompressionBombWarning)
            im = Image.open(io.BytesIO(data))
            if im.format not in ALLOWED_FORMATS:
                raise ImageError("Chỉ nhận ảnh JPG, PNG, WEBP hoặc GIF")
            is_jpeg = im.format in ("JPEG", "MPO")
            if im.width * im.height > (MAX_PIXELS_JPEG if is_jpeg else MAX_PIXELS_OTHER):
                raise ImageError("Ảnh có độ phân giải quá lớn, hãy thu nhỏ ảnh rồi tải lại")
            if is_jpeg:
                im.draft("RGB", (MAX_SIDE * 2, MAX_SIDE * 2))  # giải mã nhỏ hơn -> tốn ít RAM
            im.load()
            # Đưa về hệ màu chuẩn rồi thu nhỏ ngay để các bước sau chỉ làm trên ảnh nhỏ
            if im.mode == "P":
                im = im.convert("RGBA" if "transparency" in im.info else "RGB")
            elif im.mode not in ("RGB", "RGBA", "L", "LA"):
                im = im.convert("RGB")  # CMYK, 16-bit...
            im.thumbnail((MAX_SIDE, MAX_SIDE), Image.Resampling.LANCZOS, reducing_gap=3.0)
            im = ImageOps.exif_transpose(im)
    except ImageError:
        raise
    except (UnidentifiedImageError, Image.DecompressionBombError, Image.DecompressionBombWarning):
        raise ImageError("File không phải ảnh hợp lệ hoặc ảnh quá lớn") from None
    except (OSError, SyntaxError, ValueError):
        raise ImageError("Không đọc được file ảnh") from None

    if im.mode in ("RGBA", "LA"):
        im = im.convert("RGBA")
        bg = Image.new("RGB", im.size, (255, 255, 255))  # nền trong suốt -> nền trắng
        bg.paste(im, mask=im.getchannel("A"))
        im = bg
    else:
        im = im.convert("RGB")

    out = io.BytesIO()
    im.save(out, "WEBP", quality=85, method=4)
    return out.getvalue()


def save_product_image(pid, webp_bytes):
    """Ghi ảnh nguyên tử: ghi ra file tạm rồi đổi tên, không bao giờ để lại ảnh ghi dở."""
    folder = _folder()
    os.makedirs(folder, exist_ok=True)
    fd, tmp = tempfile.mkstemp(dir=folder, suffix=".tmp")
    try:
        with os.fdopen(fd, "wb") as f:
            f.write(webp_bytes)
        os.replace(tmp, product_path(pid))
    except BaseException:
        try:
            os.unlink(tmp)
        except FileNotFoundError:
            pass
        raise


def delete_product_image(pid):
    try:
        os.unlink(product_path(pid))
        return True
    except FileNotFoundError:
        return False
