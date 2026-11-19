CREATE TABLE users (
 id BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
 phone VARCHAR(20) NOT NULL UNIQUE,
 password_hash VARCHAR(255) NOT NULL,
 name VARCHAR(100) NOT NULL,
 role ENUM('pet_owner','store_owner','admin') NOT NULL
) ENGINE=InnoDB;

CREATE TABLE sessions (
 token_hash CHAR(64) PRIMARY KEY,
 user_id BIGINT UNSIGNED NOT NULL,
 expires_at DATETIME(6) NOT NULL,
 FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE
) ENGINE=InnoDB;

CREATE TABLE user_bans (
 id BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
 user_id BIGINT UNSIGNED NOT NULL,
 admin_id BIGINT UNSIGNED NOT NULL,
 starts_at DATETIME(6) NOT NULL DEFAULT (UTC_TIMESTAMP(6)),
 ends_at DATETIME(6) NOT NULL,
 FOREIGN KEY (user_id) REFERENCES users(id),
 FOREIGN KEY (admin_id) REFERENCES users(id),
 INDEX active_bans (user_id, ends_at),
 CHECK (ends_at > starts_at)
) ENGINE=InnoDB;

CREATE TABLE files (
 id BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
 owner_id BIGINT UNSIGNED NOT NULL,
 purpose ENUM('product','license') NOT NULL,
 storage_key CHAR(64) NOT NULL UNIQUE,
 filename VARCHAR(255) NOT NULL,
 mime_type VARCHAR(80) NOT NULL,
 FOREIGN KEY (owner_id) REFERENCES users(id)
) ENGINE=InnoDB;

CREATE TABLE stores (
 id BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
 owner_id BIGINT UNSIGNED NOT NULL,
 name VARCHAR(100) NOT NULL,
 status ENUM('pending','approved','rejected') NOT NULL DEFAULT 'pending',
 FOREIGN KEY (owner_id) REFERENCES users(id),
 INDEX stores_owner (owner_id),
 INDEX stores_status (status, name)
) ENGINE=InnoDB;

CREATE TABLE store_applications (
 id BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
 store_id BIGINT UNSIGNED NOT NULL UNIQUE,
 license_id BIGINT UNSIGNED NOT NULL,
 reviewed_by BIGINT UNSIGNED,
 decision ENUM('pending','approved','rejected') NOT NULL DEFAULT 'pending',
 submitted_at DATETIME(6) NOT NULL DEFAULT (UTC_TIMESTAMP(6)),
 reviewed_at DATETIME(6),
 FOREIGN KEY (store_id) REFERENCES stores(id),
 FOREIGN KEY (license_id) REFERENCES files(id),
 FOREIGN KEY (reviewed_by) REFERENCES users(id),
 CHECK ((decision = 'pending' AND reviewed_at IS NULL AND reviewed_by IS NULL)
     OR (decision <> 'pending' AND reviewed_at IS NOT NULL AND reviewed_by IS NOT NULL))
) ENGINE=InnoDB;

CREATE TABLE categories (
 id BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
 name VARCHAR(80) NOT NULL UNIQUE
) ENGINE=InnoDB;

CREATE TABLE products (
 id BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
 store_id BIGINT UNSIGNED NOT NULL,
 category_id BIGINT UNSIGNED,
 photo_id BIGINT UNSIGNED,
 name VARCHAR(100) NOT NULL,
 description VARCHAR(2000) NOT NULL,
 price_minor INT UNSIGNED NOT NULL,
 archived_at DATETIME(6),
 FOREIGN KEY (store_id) REFERENCES stores(id),
 FOREIGN KEY (category_id) REFERENCES categories(id) ON DELETE SET NULL,
 FOREIGN KEY (photo_id) REFERENCES files(id),
 UNIQUE KEY product_store (id, store_id),
 INDEX products_store (store_id, archived_at),
 CHECK (price_minor > 0)
) ENGINE=InnoDB;

CREATE TABLE inventory (
 product_id BIGINT UNSIGNED PRIMARY KEY,
 quantity INT UNSIGNED NOT NULL DEFAULT 0,
 FOREIGN KEY (product_id) REFERENCES products(id),
 CHECK (quantity <= 1000000000)
) ENGINE=InnoDB;

CREATE TABLE orders (
 id BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
 store_id BIGINT UNSIGNED NOT NULL,
 buyer_id BIGINT UNSIGNED NOT NULL,
 checkout_key VARCHAR(100) NOT NULL,
 checkout_hash CHAR(64) NOT NULL,
 status ENUM('placed','confirmed','on_delivery','delivered') NOT NULL DEFAULT 'placed',
 created_at DATETIME(6) NOT NULL DEFAULT (UTC_TIMESTAMP(6)),
 FOREIGN KEY (store_id) REFERENCES stores(id),
 FOREIGN KEY (buyer_id) REFERENCES users(id),
 UNIQUE KEY checkout_once (buyer_id, checkout_key),
 UNIQUE KEY order_store (id, store_id),
 INDEX buyer_orders (buyer_id, id),
 INDEX store_orders (store_id, id)
) ENGINE=InnoDB;

CREATE TABLE order_items (
 order_id BIGINT UNSIGNED NOT NULL,
 store_id BIGINT UNSIGNED NOT NULL,
 product_id BIGINT UNSIGNED NOT NULL,
 product_name VARCHAR(100) NOT NULL,
 unit_price_minor INT UNSIGNED NOT NULL,
 quantity INT UNSIGNED NOT NULL,
 PRIMARY KEY (order_id, product_id),
 FOREIGN KEY (order_id, store_id) REFERENCES orders(id, store_id),
 FOREIGN KEY (product_id, store_id) REFERENCES products(id, store_id),
 CHECK (quantity BETWEEN 1 AND 1000000000),
 CHECK (unit_price_minor > 0)
) ENGINE=InnoDB;

CREATE TABLE stock_movements (
 id BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
 product_id BIGINT UNSIGNED NOT NULL,
 actor_id BIGINT UNSIGNED NOT NULL,
 order_id BIGINT UNSIGNED,
 delta INT NOT NULL,
 reason ENUM('restock','adjustment','confirmation') NOT NULL,
 created_at DATETIME(6) NOT NULL DEFAULT (UTC_TIMESTAMP(6)),
 FOREIGN KEY (product_id) REFERENCES inventory(product_id),
 FOREIGN KEY (actor_id) REFERENCES users(id),
 FOREIGN KEY (order_id) REFERENCES orders(id),
 UNIQUE KEY order_deduction (order_id, product_id),
 CHECK (delta <> 0)
) ENGINE=InnoDB;
