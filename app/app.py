"""
Hệ thống Quản lý Kho hàng (Inventory) - Flask + MySQL
- Quản lý sản phẩm, nhà cung cấp
- Nhập kho / xuất kho, lịch sử giao dịch, cảnh báo tồn kho thấp
- /metrics cho Prometheus, log dạng logfmt cho Loki
"""
import logging
import os
import sys
from datetime import datetime
from decimal import Decimal, InvalidOperation
from functools import wraps

from flask import (Flask, abort, flash, redirect, render_template, request,
                   session, url_for)
from flask_sqlalchemy import SQLAlchemy
from flask_wtf.csrf import CSRFProtect
from prometheus_client import Counter, Gauge
from prometheus_flask_exporter import PrometheusMetrics
from sqlalchemy import func, or_
from sqlalchemy.exc import IntegrityError
from werkzeug.middleware.proxy_fix import ProxyFix
from werkzeug.security import check_password_hash, generate_password_hash

db = SQLAlchemy()
csrf = CSRFProtect()

# ---------------------------------------------------------------- logging
class LogfmtFormatter(logging.Formatter):
    """Ghi log dạng: ts=... level=info event=stock_in product=LAP-001 qty=5
    -> LogQL lọc dễ bằng `| logfmt | event="stock_in"`"""

    def format(self, record):
        fields = {
            "ts": datetime.now().astimezone().isoformat(timespec="seconds"),
            "level": record.levelname.lower(),
            "logger": record.name,
            "msg": record.getMessage(),
        }
        fields.update(getattr(record, "extra_fields", {}))
        parts = []
        for k, v in fields.items():
            v = str(v)
            if not v or any(c in v for c in ' ="'):
                v = '"' + v.replace('"', "'") + '"'
            parts.append(f"{k}={v}")
        return " ".join(parts)


def get_logger():
    logger = logging.getLogger("inventory")
    if not logger.handlers:
        h = logging.StreamHandler(sys.stdout)
        h.setFormatter(LogfmtFormatter())
        logger.addHandler(h)
        logger.setLevel(os.getenv("LOG_LEVEL", "INFO"))
        logger.propagate = False
    return logger


log = get_logger()


def log_event(level, event, msg="", **kw):
    kw = {"event": event, "user": session.get("user", "-") if _has_request() else "-", **kw}
    if _has_request():
        kw.setdefault("ip", request.remote_addr)
    log.log(level, msg or event, extra={"extra_fields": kw})


def _has_request():
    from flask import has_request_context
    return has_request_context()


# ---------------------------------------------------------------- models
class Supplier(db.Model):
    __tablename__ = "suppliers"
    id = db.Column(db.Integer, primary_key=True)
    name = db.Column(db.String(150), nullable=False)
    phone = db.Column(db.String(30))
    email = db.Column(db.String(120))
    address = db.Column(db.String(255))
    created_at = db.Column(db.DateTime, nullable=False, default=datetime.now, server_default=func.now())


class Product(db.Model):
    __tablename__ = "products"
    id = db.Column(db.Integer, primary_key=True)
    sku = db.Column(db.String(50), unique=True, nullable=False)
    name = db.Column(db.String(150), nullable=False)
    category = db.Column(db.String(80))
    unit = db.Column(db.String(20), nullable=False, default="cái")
    price = db.Column(db.Numeric(12, 2), nullable=False, default=0)
    quantity = db.Column(db.Integer, nullable=False, default=0)
    min_stock = db.Column(db.Integer, nullable=False, default=5)
    supplier_id = db.Column(db.Integer, db.ForeignKey("suppliers.id", ondelete="SET NULL"))
    created_at = db.Column(db.DateTime, nullable=False, default=datetime.now, server_default=func.now())
    updated_at = db.Column(db.DateTime, nullable=False, default=datetime.now, onupdate=datetime.now,
                           server_default=func.now())
    supplier = db.relationship("Supplier", backref="products")

    @property
    def is_low(self):
        return self.quantity <= self.min_stock


class StockTransaction(db.Model):
    __tablename__ = "stock_transactions"
    id = db.Column(db.Integer, primary_key=True)
    product_id = db.Column(db.Integer, db.ForeignKey("products.id", ondelete="RESTRICT"), nullable=False)
    type = db.Column(db.Enum("IN", "OUT", name="tx_type"), nullable=False)
    quantity = db.Column(db.Integer, nullable=False)
    unit_price = db.Column(db.Numeric(12, 2), nullable=False, default=0)
    supplier_id = db.Column(db.Integer, db.ForeignKey("suppliers.id", ondelete="SET NULL"))
    note = db.Column(db.String(255))
    created_by = db.Column(db.String(50))
    created_at = db.Column(db.DateTime, nullable=False, default=datetime.now, server_default=func.now())
    product = db.relationship("Product", backref="transactions")
    supplier = db.relationship("Supplier")


# ---------------------------------------------------------------- metrics
STOCK_MOVES = Counter("inventory_stock_movements_total",
                      "Số phiếu nhập/xuất kho đã tạo", ["type"])
STOCK_UNITS = Counter("inventory_stock_units_total",
                      "Tổng số lượng hàng nhập/xuất", ["type"])
LOGIN_ATTEMPTS = Counter("inventory_login_attempts_total",
                         "Số lần đăng nhập", ["result"])
LOW_STOCK = Gauge("inventory_low_stock_products",
                  "Số sản phẩm đang dưới mức tồn tối thiểu (cập nhật khi mở dashboard)")


# ---------------------------------------------------------------- helpers
def login_required(view):
    @wraps(view)
    def wrapped(*args, **kwargs):
        if not session.get("user"):
            return redirect(url_for("login", next=request.path))
        return view(*args, **kwargs)
    return wrapped


def to_int(value, default=0, minimum=None):
    try:
        v = int(value)
    except (TypeError, ValueError):
        return default
    if minimum is not None and v < minimum:
        return default
    return v


def to_money(value):
    try:
        v = Decimal(str(value or "0").replace(",", ""))
        return v if v >= 0 else Decimal("0")
    except InvalidOperation:
        return Decimal("0")


def clean(value, maxlen):
    return (value or "").strip()[:maxlen] or None


# ---------------------------------------------------------------- factory
def create_app(test_config=None):
    app = Flask(__name__)

    db_url = os.getenv("DATABASE_URL")
    if not db_url:
        db_url = "mysql+pymysql://{u}:{p}@{h}:{port}/{n}?charset=utf8mb4".format(
            u=os.getenv("DB_USER", "inventory_app"),
            p=os.getenv("DB_PASSWORD", ""),
            h=os.getenv("DB_HOST", "db"),
            port=os.getenv("DB_PORT", "3306"),
            n=os.getenv("DB_NAME", "inventory_db"),
        )

    secure_cookie = os.getenv("SESSION_COOKIE_SECURE", "true").lower() == "true"
    app.config.update(
        SECRET_KEY=os.getenv("SECRET_KEY") or os.urandom(32),
        SQLALCHEMY_DATABASE_URI=db_url,
        SQLALCHEMY_ENGINE_OPTIONS={"pool_pre_ping": True, "pool_recycle": 280},
        SESSION_COOKIE_HTTPONLY=True,
        SESSION_COOKIE_SAMESITE="Lax",
        SESSION_COOKIE_SECURE=secure_cookie,
        PERMANENT_SESSION_LIFETIME=3600,
        ADMIN_USERNAME=os.getenv("ADMIN_USERNAME", "admin"),
        # Không đặt ADMIN_PASSWORD -> không ai đăng nhập được (fail-safe)
        ADMIN_PASSWORD_HASH=(generate_password_hash(os.environ["ADMIN_PASSWORD"])
                             if os.getenv("ADMIN_PASSWORD") else None),
    )
    if test_config:
        app.config.update(test_config)

    # Tin header X-Forwarded-* từ đúng 1 proxy phía trước (Nginx)
    app.wsgi_app = ProxyFix(app.wsgi_app, x_for=1, x_proto=1, x_host=1)

    db.init_app(app)
    csrf.init_app(app)

    if not app.config.get("TESTING"):
        metrics = PrometheusMetrics(app, group_by="endpoint")
        metrics.info("inventory_app_info", "Thông tin ứng dụng", version="1.0.0")

    # ------------------------------------------------ auth
    @app.route("/login", methods=["GET", "POST"])
    def login():
        if request.method == "POST":
            username = request.form.get("username", "")
            password = request.form.get("password", "")
            pw_hash = app.config["ADMIN_PASSWORD_HASH"]
            if (username == app.config["ADMIN_USERNAME"] and pw_hash
                    and check_password_hash(pw_hash, password)):
                session.clear()
                session["user"] = username
                session.permanent = True
                LOGIN_ATTEMPTS.labels("success").inc()
                log_event(logging.INFO, "login_success")
                nxt = request.args.get("next", "")
                return redirect(nxt if nxt.startswith("/") and not nxt.startswith("//") else url_for("dashboard"))
            LOGIN_ATTEMPTS.labels("failed").inc()
            log_event(logging.WARNING, "login_failed", attempted_user=username[:50])
            flash("Sai tên đăng nhập hoặc mật khẩu", "error")
        return render_template("login.html")

    @app.route("/logout", methods=["POST"])
    def logout():
        log_event(logging.INFO, "logout")
        session.clear()
        return redirect(url_for("login"))

    # ------------------------------------------------ health
    @app.route("/health")
    def health():
        try:
            db.session.execute(db.text("SELECT 1"))
            return {"status": "ok", "db": "up"}, 200
        except Exception as e:  # noqa: BLE001
            log_event(logging.ERROR, "db_health_failed", error=type(e).__name__)
            return {"status": "degraded", "db": "down"}, 503

    # ------------------------------------------------ dashboard
    @app.route("/")
    @login_required
    def dashboard():
        total_products = db.session.query(func.count(Product.id)).scalar() or 0
        total_units = db.session.query(func.coalesce(func.sum(Product.quantity), 0)).scalar() or 0
        stock_value = db.session.query(
            func.coalesce(func.sum(Product.quantity * Product.price), 0)).scalar() or 0
        total_suppliers = db.session.query(func.count(Supplier.id)).scalar() or 0
        low_stock = (Product.query.filter(Product.quantity <= Product.min_stock)
                     .order_by(Product.quantity).all())
        LOW_STOCK.set(len(low_stock))
        recent = (StockTransaction.query.order_by(StockTransaction.created_at.desc(),
                                                  StockTransaction.id.desc()).limit(8).all())
        return render_template("dashboard.html", total_products=total_products,
                               total_units=total_units, stock_value=stock_value,
                               total_suppliers=total_suppliers, low_stock=low_stock,
                               recent=recent)

    # ------------------------------------------------ products
    @app.route("/products")
    @login_required
    def products():
        q = request.args.get("q", "").strip()
        only_low = request.args.get("low") == "1"
        query = Product.query
        if q:
            like = f"%{q}%"
            query = query.filter(or_(Product.name.like(like), Product.sku.like(like),
                                     Product.category.like(like)))
        if only_low:
            query = query.filter(Product.quantity <= Product.min_stock)
        items = query.order_by(Product.name).all()
        return render_template("products.html", items=items, q=q, only_low=only_low)

    @app.route("/products/new", methods=["GET", "POST"])
    @app.route("/products/<int:pid>/edit", methods=["GET", "POST"])
    @login_required
    def product_form(pid=None):
        product = db.session.get(Product, pid) if pid else Product(quantity=0, min_stock=5, unit="cái")
        if pid and not product:
            abort(404)
        if request.method == "POST":
            sku = clean(request.form.get("sku"), 50)
            name = clean(request.form.get("name"), 150)
            if not sku or not name:
                flash("Mã SKU và tên sản phẩm là bắt buộc", "error")
                return render_template("product_form.html", p=product, suppliers=Supplier.query.all())
            product.sku = sku.upper()
            product.name = name
            product.category = clean(request.form.get("category"), 80)
            product.unit = clean(request.form.get("unit"), 20) or "cái"
            product.price = to_money(request.form.get("price"))
            product.min_stock = to_int(request.form.get("min_stock"), 5, minimum=0)
            sid = to_int(request.form.get("supplier_id"), 0)
            product.supplier_id = sid or None
            if not pid:
                # Số lượng ban đầu chỉ nhập khi tạo mới; sau đó phải qua phiếu nhập/xuất
                product.quantity = to_int(request.form.get("quantity"), 0, minimum=0)
                db.session.add(product)
            try:
                db.session.commit()
            except IntegrityError:
                db.session.rollback()
                flash(f"Mã SKU {product.sku} đã tồn tại", "error")
                return render_template("product_form.html", p=product, suppliers=Supplier.query.all())
            log_event(logging.INFO, "product_updated" if pid else "product_created",
                      sku=product.sku, product_id=product.id)
            flash("Đã lưu sản phẩm", "success")
            return redirect(url_for("products"))
        return render_template("product_form.html", p=product, suppliers=Supplier.query.order_by(Supplier.name).all())

    @app.route("/products/<int:pid>/delete", methods=["POST"])
    @login_required
    def product_delete(pid):
        product = db.session.get(Product, pid) or abort(404)
        if StockTransaction.query.filter_by(product_id=pid).first():
            flash("Không thể xoá: sản phẩm đã có lịch sử nhập/xuất", "error")
            return redirect(url_for("products"))
        sku = product.sku
        db.session.delete(product)
        db.session.commit()
        log_event(logging.INFO, "product_deleted", sku=sku, product_id=pid)
        flash("Đã xoá sản phẩm", "success")
        return redirect(url_for("products"))

    # ------------------------------------------------ suppliers
    @app.route("/suppliers")
    @login_required
    def suppliers():
        items = Supplier.query.order_by(Supplier.name).all()
        return render_template("suppliers.html", items=items)

    @app.route("/suppliers/new", methods=["GET", "POST"])
    @app.route("/suppliers/<int:sid>/edit", methods=["GET", "POST"])
    @login_required
    def supplier_form(sid=None):
        supplier = db.session.get(Supplier, sid) if sid else Supplier()
        if sid and not supplier:
            abort(404)
        if request.method == "POST":
            name = clean(request.form.get("name"), 150)
            if not name:
                flash("Tên nhà cung cấp là bắt buộc", "error")
                return render_template("supplier_form.html", s=supplier)
            supplier.name = name
            supplier.phone = clean(request.form.get("phone"), 30)
            supplier.email = clean(request.form.get("email"), 120)
            supplier.address = clean(request.form.get("address"), 255)
            if not sid:
                db.session.add(supplier)
            db.session.commit()
            log_event(logging.INFO, "supplier_updated" if sid else "supplier_created",
                      supplier_id=supplier.id)
            flash("Đã lưu nhà cung cấp", "success")
            return redirect(url_for("suppliers"))
        return render_template("supplier_form.html", s=supplier)

    @app.route("/suppliers/<int:sid>/delete", methods=["POST"])
    @login_required
    def supplier_delete(sid):
        supplier = db.session.get(Supplier, sid) or abort(404)
        Product.query.filter_by(supplier_id=sid).update({"supplier_id": None})
        StockTransaction.query.filter_by(supplier_id=sid).update({"supplier_id": None})
        db.session.delete(supplier)
        db.session.commit()
        log_event(logging.INFO, "supplier_deleted", supplier_id=sid)
        flash("Đã xoá nhà cung cấp", "success")
        return redirect(url_for("suppliers"))

    # ------------------------------------------------ stock in / out
    @app.route("/stock/<direction>", methods=["GET", "POST"])
    @login_required
    def stock(direction):
        if direction not in ("in", "out"):
            abort(404)
        tx_type = "IN" if direction == "in" else "OUT"
        all_products = Product.query.order_by(Product.name).all()
        all_suppliers = Supplier.query.order_by(Supplier.name).all()

        if request.method == "POST":
            pid = to_int(request.form.get("product_id"))
            qty = to_int(request.form.get("quantity"), 0, minimum=1)
            if not pid or qty <= 0:
                flash("Chọn sản phẩm và nhập số lượng > 0", "error")
                return render_template("stock_form.html", direction=direction,
                                       products=all_products, suppliers=all_suppliers)
            # Khoá dòng sản phẩm để tránh 2 phiếu xuất cùng lúc làm âm kho
            product = (db.session.query(Product).filter_by(id=pid)
                       .with_for_update().first())
            if not product:
                abort(404)
            if tx_type == "OUT" and qty > product.quantity:
                db.session.rollback()
                log_event(logging.WARNING, "stock_out_rejected", sku=product.sku,
                          requested=qty, available=product.quantity)
                flash(f"Không đủ hàng: {product.name} chỉ còn {product.quantity} {product.unit}", "error")
                return render_template("stock_form.html", direction=direction,
                                       products=all_products, suppliers=all_suppliers)

            unit_price = request.form.get("unit_price")
            tx = StockTransaction(
                product_id=product.id, type=tx_type, quantity=qty,
                unit_price=to_money(unit_price) if unit_price else product.price,
                supplier_id=(to_int(request.form.get("supplier_id")) or None) if tx_type == "IN" else None,
                note=clean(request.form.get("note"), 255),
                created_by=session.get("user"),
            )
            product.quantity += qty if tx_type == "IN" else -qty
            db.session.add(tx)
            db.session.commit()

            STOCK_MOVES.labels(tx_type).inc()
            STOCK_UNITS.labels(tx_type).inc(qty)
            log_event(logging.INFO, f"stock_{direction}", sku=product.sku, product_id=product.id,
                      qty=qty, stock_after=product.quantity, tx_id=tx.id)
            if product.is_low:
                log_event(logging.WARNING, "low_stock", sku=product.sku,
                          quantity=product.quantity, min_stock=product.min_stock)
            flash(f"Đã {'nhập' if tx_type == 'IN' else 'xuất'} {qty} {product.unit} {product.name}. "
                  f"Tồn kho: {product.quantity}", "success")
            return redirect(url_for("transactions"))

        return render_template("stock_form.html", direction=direction,
                               products=all_products, suppliers=all_suppliers,
                               selected=to_int(request.args.get("product_id")))

    @app.route("/transactions")
    @login_required
    def transactions():
        tx_type = request.args.get("type", "")
        query = StockTransaction.query
        if tx_type in ("IN", "OUT"):
            query = query.filter_by(type=tx_type)
        items = query.order_by(StockTransaction.created_at.desc(),
                               StockTransaction.id.desc()).limit(200).all()
        return render_template("transactions.html", items=items, tx_type=tx_type)

    # ------------------------------------------------ errors & filters
    @app.errorhandler(404)
    def not_found(_):
        return render_template("error.html", code=404, message="Không tìm thấy trang"), 404

    @app.errorhandler(500)
    def server_error(e):
        log_event(logging.ERROR, "server_error", error=type(e).__name__)
        return render_template("error.html", code=500, message="Lỗi máy chủ"), 500

    @app.template_filter("money")
    def money(v):
        try:
            return f"{Decimal(v):,.0f} ₫".replace(",", ".")
        except Exception:  # noqa: BLE001
            return v

    @app.template_filter("dt")
    def dt(v):
        return v.strftime("%d/%m/%Y %H:%M") if v else ""

    @app.context_processor
    def inject_user():
        return {"current_user": session.get("user")}

    return app
