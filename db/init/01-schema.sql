-- =========================================================
-- Hệ thống Quản lý Kho hàng - Schema + dữ liệu mẫu
-- File này được MySQL tự chạy ở lần khởi động đầu tiên
-- (khi volume db_data còn trống).
-- =========================================================
SET NAMES utf8mb4;
SET time_zone = '+07:00';

USE inventory_db;

-- Nhà cung cấp
CREATE TABLE IF NOT EXISTS suppliers (
    id          INT AUTO_INCREMENT PRIMARY KEY,
    name        VARCHAR(150) NOT NULL,
    phone       VARCHAR(30),
    email       VARCHAR(120),
    address     VARCHAR(255),
    created_at  DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- Sản phẩm (quantity = số lượng tồn kho hiện tại)
CREATE TABLE IF NOT EXISTS products (
    id           INT AUTO_INCREMENT PRIMARY KEY,
    sku          VARCHAR(50)  NOT NULL UNIQUE,
    name         VARCHAR(150) NOT NULL,
    category     VARCHAR(80),
    unit         VARCHAR(20)  NOT NULL DEFAULT 'cái',
    price        DECIMAL(12,2) NOT NULL DEFAULT 0,
    quantity     INT NOT NULL DEFAULT 0,
    min_stock    INT NOT NULL DEFAULT 5,
    supplier_id  INT NULL,
    created_at   DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at   DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    CONSTRAINT fk_products_supplier FOREIGN KEY (supplier_id)
        REFERENCES suppliers(id) ON DELETE SET NULL,
    CONSTRAINT chk_products_quantity CHECK (quantity >= 0)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- Phiếu nhập / xuất kho
CREATE TABLE IF NOT EXISTS stock_transactions (
    id           INT AUTO_INCREMENT PRIMARY KEY,
    product_id   INT NOT NULL,
    type         ENUM('IN','OUT') NOT NULL,
    quantity     INT NOT NULL,
    unit_price   DECIMAL(12,2) NOT NULL DEFAULT 0,
    supplier_id  INT NULL,
    note         VARCHAR(255),
    created_by   VARCHAR(50),
    created_at   DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT fk_tx_product  FOREIGN KEY (product_id)  REFERENCES products(id)  ON DELETE RESTRICT,
    CONSTRAINT fk_tx_supplier FOREIGN KEY (supplier_id) REFERENCES suppliers(id) ON DELETE SET NULL,
    CONSTRAINT chk_tx_quantity CHECK (quantity > 0),
    INDEX idx_tx_created (created_at),
    INDEX idx_tx_type (type)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- ---------------- Dữ liệu mẫu ----------------
INSERT INTO suppliers (name, phone, email, address) VALUES
 ('Công ty TNHH Thiết bị Minh Phát', '0901234567', 'sales@minhphat.vn',  'Q. Cầu Giấy, Hà Nội'),
 ('Công ty CP Văn phòng phẩm Hồng Hà', '0912345678', 'contact@hongha.vn', 'Q. Hoàn Kiếm, Hà Nội'),
 ('Nhà phân phối Điện tử An Khang',  '0987654321', 'info@ankhang.vn',   'TP. Thủ Đức, TP.HCM');

INSERT INTO products (sku, name, category, unit, price, quantity, min_stock, supplier_id) VALUES
 ('LAP-001', 'Laptop Dell Latitude 5440',   'Thiết bị IT',  'cái',  18500000, 12, 3, 1),
 ('MOU-001', 'Chuột không dây Logitech M331','Phụ kiện',     'cái',    350000, 45, 10, 3),
 ('KEY-001', 'Bàn phím cơ Akko 3087',        'Phụ kiện',     'cái',    990000,  4, 5, 3),
 ('MON-001', 'Màn hình LG 24 inch IPS',      'Thiết bị IT',  'cái',   2900000,  8, 3, 1),
 ('PAP-001', 'Giấy A4 Double A 80gsm',       'Văn phòng phẩm','ram',     75000, 120, 30, 2),
 ('PEN-001', 'Bút bi Thiên Long TL-027',     'Văn phòng phẩm','hộp',     60000,  2, 10, 2),
 ('CAB-001', 'Cáp HDMI 2.0 dài 1.5m',        'Phụ kiện',     'sợi',    120000, 30, 10, 3),
 ('PRN-001', 'Máy in HP LaserJet M211dw',    'Thiết bị IT',  'cái',   3600000,  0, 2, 1);

INSERT INTO stock_transactions (product_id, type, quantity, unit_price, supplier_id, note, created_by) VALUES
 (1, 'IN',  15, 17800000, 1, 'Nhập lô đầu kỳ',             'admin'),
 (1, 'OUT',  3, 18500000, NULL, 'Cấp cho phòng Kế toán',     'admin'),
 (2, 'IN',  50,   300000, 3, 'Nhập lô đầu kỳ',             'admin'),
 (2, 'OUT',  5,   350000, NULL, 'Xuất cho phòng Kinh doanh', 'admin'),
 (5, 'IN', 120,    70000, 2, 'Nhập văn phòng phẩm quý 4',  'admin');
