"""
Tính hình học cho biểu đồ SVG vẽ phía server.

Biểu đồ được vẽ thành SVG ngay trong template (không cần thư viện JS, không cần
style nội tuyến) nên hoạt động với Content-Security-Policy chặt của Nginx và in ra
giấy vẫn rõ nét. Module này chỉ tính toạ độ; màu sắc nằm trong style.css.
"""
import math
from datetime import date, datetime, timedelta


# ---------------------------------------------------------------- tiện ích số
def nice_ceiling(value, ticks=4):
    """Làm tròn giá trị lớn nhất lên một mốc "đẹp" chia hết cho số vạch chia."""
    if value <= 0:
        return ticks
    raw_step = value / ticks
    mag = 10 ** math.floor(math.log10(raw_step))
    for m in (1, 2, 2.5, 5, 10):
        step = m * mag
        if step >= raw_step:
            break
    return step * ticks


def pct_change(current, previous):
    """% thay đổi so với kỳ trước; None nếu kỳ trước bằng 0 (không so sánh được)."""
    current, previous = float(current or 0), float(previous or 0)
    if previous == 0:
        return None
    return (current - previous) / abs(previous) * 100


def short_money(value):
    """277630000 -> ('277,6', 'triệu ₫'); dùng cho chữ giữa biểu đồ tròn."""
    v = float(value or 0)
    for div, unit in ((1e9, "tỷ ₫"), (1e6, "triệu ₫"), (1e3, "nghìn ₫")):
        if abs(v) >= div:
            return f"{v / div:,.1f}".replace(",", "X").replace(".", ",").replace("X", "."), unit
    return f"{v:,.0f}".replace(",", "."), "₫"


# ---------------------------------------------------------------- sparkline
def sparkline(values, width=120, height=36, pad=3):
    """Trả về path đường và path vùng tô cho một chuỗi số."""
    vals = [float(v) for v in values] or [0.0]
    if len(vals) == 1:
        vals = vals * 2
    lo, hi = min(vals), max(vals)
    span = hi - lo
    n = len(vals) - 1
    pts = []
    for i, v in enumerate(vals):
        x = i / n * width
        y = height / 2 if span == 0 else pad + (1 - (v - lo) / span) * (height - 2 * pad)
        pts.append((round(x, 1), round(y, 1)))
    line = "M" + " L".join(f"{x} {y}" for x, y in pts)
    area = f"{line} L{width} {height} L0 {height} Z"
    last = pts[-1]
    return {"line": line, "area": area, "w": width, "h": height, "last_x": last[0], "last_y": last[1]}


# ---------------------------------------------------------------- biểu đồ cột
def bar_chart(labels, series_in, series_out, titles=None, width=640, height=320):
    """Biểu đồ cột nhóm Nhập/Xuất. Trả về toạ độ cột, lưới và nhãn trục."""
    left, right, top, bottom = 52, 12, 14, 30
    plot_w, plot_h = width - left - right, height - top - bottom
    top_val = nice_ceiling(max(list(series_in) + list(series_out) + [1]))
    n = max(len(labels), 1)
    group = plot_w / n
    bar_w = min(20.0, group * 0.3)
    gap = 3
    grid = []
    for i in range(5):
        val = top_val * i / 4
        y = top + plot_h - plot_h * i / 4
        grid.append({"y": round(y, 1), "label": f"{val:,.0f}".replace(",", ".")})
    groups = []
    for i, label in enumerate(labels):
        cx = left + group * (i + 0.5)
        bars = []
        for kind, val, x in (("in", series_in[i], cx - bar_w - gap / 2), ("out", series_out[i], cx + gap / 2)):
            h = plot_h * float(val) / top_val
            bars.append({"kind": kind, "value": val, "x": round(x, 1), "y": round(top + plot_h - h, 1),
                         "w": round(bar_w, 1), "h": round(max(h, 0), 1)})
        groups.append({"label": label, "title": (titles or labels)[i], "cx": round(cx, 1), "bars": bars})
    return {"w": width, "h": height, "left": left, "right": width - right, "base_y": top + plot_h,
            "label_y": height - 9, "grid": grid, "groups": groups,
            "total_in": sum(series_in), "total_out": sum(series_out)}


# ---------------------------------------------------------------- biểu đồ tròn (donut)
def donut(items, radius=62, stroke=22, max_slices=5):
    """items: [(nhãn, giá trị)] -> các cung tròn dùng stroke-dasharray."""
    items = sorted(((k or "Chưa phân loại", float(v)) for k, v in items if float(v) > 0),
                   key=lambda kv: kv[1], reverse=True)
    if len(items) > max_slices:
        rest = sum(v for _, v in items[max_slices - 1:])
        items = items[:max_slices - 1] + [("Khác", rest)]
    total = sum(v for _, v in items)
    circ = 2 * math.pi * radius
    slices, acc = [], 0.0
    for i, (label, val) in enumerate(items):
        frac = val / total if total else 0
        length = max(circ * frac - (2 if len(items) > 1 else 0), 0.5)
        slices.append({"label": label, "value": val, "pct": frac * 100, "tone": i,
                       "dash": f"{length:.2f} {circ - length:.2f}",
                       "offset": f"{circ * 0.25 - acc:.2f}"})
        acc += circ * frac
    size = (radius + stroke) * 2 + 4
    return {"slices": slices, "total": total, "r": radius, "stroke": stroke,
            "size": size, "c": size / 2}


# ---------------------------------------------------------------- chuỗi thời gian
def day_range(end: date, days: int):
    return [end - timedelta(days=days - 1 - i) for i in range(days)]


def week_start(d: date):
    return d - timedelta(days=d.weekday())


def month_start(d: date):
    return d.replace(day=1)


def add_months(d: date, months: int):
    y, m = divmod(d.month - 1 + months, 12)
    return date(d.year + y, m + 1, 1)


def as_date(v):
    return v.date() if isinstance(v, datetime) else v
