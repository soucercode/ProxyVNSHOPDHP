# ============================================================
# SHOP DHP KEY PANEL — SERVER 5050
# ============================================================

from __future__ import annotations

import os
import re
import secrets
import sqlite3
from datetime import datetime, timedelta, timezone
from functools import wraps
from pathlib import Path

from flask import Flask, Response, jsonify, redirect, render_template_string, request, session, url_for
from werkzeug.security import check_password_hash, generate_password_hash

BASE_DIR = Path(__file__).resolve().parent
DB_PATH = BASE_DIR / "shopdhp_keys.sqlite3"
SECRET_KEY_FILE = BASE_DIR / ".secret_key"

app = Flask(__name__)


def get_or_create_secret_key() -> str:
    """Ưu tiên biến môi trường. Nếu không có, dùng 1 file cố định trên đĩa
    để SECRET_KEY không đổi mỗi lần restart server (tránh mất session /
    'Phiên đăng nhập đã hết hạn' ngẫu nhiên)."""
    env_key = os.environ.get("SHOPDHP_SECRET_KEY")
    if env_key:
        return env_key
    try:
        if SECRET_KEY_FILE.exists():
            existing = SECRET_KEY_FILE.read_text(encoding="utf-8").strip()
            if existing:
                return existing
    except OSError:
        pass
    new_key = secrets.token_hex(32)
    try:
        SECRET_KEY_FILE.write_text(new_key, encoding="utf-8")
    except OSError:
        pass
    return new_key


app.config["SECRET_KEY"] = get_or_create_secret_key()
# Session sống lâu (12 tiếng) + cấu hình cookie ổn định để tránh bị đăng xuất
# ngẫu nhiên giữa chừng khi thao tác trên dashboard.
app.config["PERMANENT_SESSION_LIFETIME"] = timedelta(hours=12)
app.config["SESSION_COOKIE_SAMESITE"] = "Lax"
app.config["SESSION_COOKIE_HTTPONLY"] = True
app.config["JSON_AS_ASCII"] = False

HOST = os.environ.get("SHOPDHP_HOST", "0.0.0.0")
PORT = int(os.environ.get("SHOPDHP_PORT", "5050"))

# Đặt tài khoản quản trị bằng biến môi trường khi chạy VPS.
# PowerShell:
#   $env:SHOPDHP_ADMIN_USER="SHOPDHP"
#   $env:SHOPDHP_ADMIN_PASS="MAT_KHAU_CUA_BAN"
ADMIN_USER = os.environ.get("SHOPDHP_ADMIN_USER", "SHOPDHP")
ADMIN_PASS = os.environ.get("SHOPDHP_ADMIN_PASS", "Shopdhp@123")

DEFAULT_TYPE_CODE = "vip"
DEFAULT_TYPE_NAME = "KEY IPA Proxy - DHP"

DURATIONS = {
    "1h": ("1 giờ", timedelta(hours=1)),
    "2h": ("2 giờ", timedelta(hours=2)),
    "1d": ("1 ngày", timedelta(days=1)),
    "7d": ("1 tuần", timedelta(days=7)),
    "1m": ("1 tháng", timedelta(days=30)),
    "3m": ("3 tháng", timedelta(days=90)),
    "1y": ("1 năm", timedelta(days=365)),
    "permanent": ("Vĩnh viễn", None),
}

# Thời hạn mà seller được phép chọn khi tạo key (giới hạn nhỏ hơn admin)
SELLER_ALLOWED_DURATIONS = ["2h", "1d", "7d", "1m"]

# Giới hạn hạn mức tạo key của seller
SELLER_MAX_PER_CREATE = 10          # mỗi lần bấm "Tạo Key" tối đa 10 key
SELLER_DEFAULT_DAILY_QUOTA = 500    # tổng số key seller được tạo trong 1 ngày

BAN_REASON_DEFAULT = (
    "⚠️ key đã bị admin Đỗ Hồng Phúc khoá\n"
    "do vi phạm chính sách quy định hãy liên hệ 0888924907 để được mở!"
)


def db():
    conn = sqlite3.connect(DB_PATH)
    conn.row_factory = sqlite3.Row
    return conn


def init_db():
    conn = db()
    conn.execute("""
        CREATE TABLE IF NOT EXISTS keys (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            key TEXT NOT NULL UNIQUE,
            type TEXT NOT NULL DEFAULT 'vip',
            type_name TEXT NOT NULL DEFAULT 'KEY IPA Proxy - DHP',
            duration_code TEXT NOT NULL,
            duration_label TEXT NOT NULL,
            created_by TEXT NOT NULL,
            created_at TEXT NOT NULL,
            expires_at TEXT,
            max_devices INTEGER NOT NULL DEFAULT 1,
            device TEXT NOT NULL DEFAULT '',
            ip TEXT NOT NULL DEFAULT '',
            banned INTEGER NOT NULL DEFAULT 0,
            locked INTEGER NOT NULL DEFAULT 0,
            ban_reason TEXT NOT NULL DEFAULT ''
        )
    """)

    conn.execute("""
        CREATE TABLE IF NOT EXISTS sellers (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            username TEXT NOT NULL UNIQUE,
            password_hash TEXT NOT NULL,
            created_at TEXT NOT NULL,
            expires_at TEXT,
            banned INTEGER NOT NULL DEFAULT 0,
            daily_quota INTEGER NOT NULL DEFAULT 500,
            daily_created INTEGER NOT NULL DEFAULT 0,
            daily_date TEXT NOT NULL DEFAULT ''
        )
    """)

    # ------------------------------------------------------------
    # Migration an toàn cho DB CŨ (tạo từ bản trước, thiếu cột mới).
    # Đây là nguyên nhân gây lỗi "IndexError: No item with that key"
    # (VD cột 'daily_date' chưa tồn tại trong bảng sellers cũ).
    # Tự động rà soát và bổ sung MỌI cột còn thiếu cho cả 2 bảng.
    # ------------------------------------------------------------
    _migrate_table_columns(conn, "keys", {
        "type": "TEXT NOT NULL DEFAULT 'vip'",
        "type_name": f"TEXT NOT NULL DEFAULT '{DEFAULT_TYPE_NAME}'",
        "duration_code": "TEXT NOT NULL DEFAULT ''",
        "duration_label": "TEXT NOT NULL DEFAULT ''",
        "created_by": "TEXT NOT NULL DEFAULT ''",
        "created_at": "TEXT NOT NULL DEFAULT ''",
        "expires_at": "TEXT",
        "max_devices": "INTEGER NOT NULL DEFAULT 1",
        "device": "TEXT NOT NULL DEFAULT ''",
        "ip": "TEXT NOT NULL DEFAULT ''",
        "banned": "INTEGER NOT NULL DEFAULT 0",
        "locked": "INTEGER NOT NULL DEFAULT 0",
        "ban_reason": "TEXT NOT NULL DEFAULT ''",
    })
    _migrate_table_columns(conn, "sellers", {
        "created_at": "TEXT NOT NULL DEFAULT ''",
        "expires_at": "TEXT",
        "banned": "INTEGER NOT NULL DEFAULT 0",
        "daily_quota": f"INTEGER NOT NULL DEFAULT {SELLER_DEFAULT_DAILY_QUOTA}",
        "daily_created": "INTEGER NOT NULL DEFAULT 0",
        "daily_date": "TEXT NOT NULL DEFAULT ''",
    })

    conn.commit()
    conn.close()


def _migrate_table_columns(conn, table: str, columns: dict[str, str]):
    """Rà soát bảng `table`, tự động ALTER TABLE ADD COLUMN cho mọi cột
    trong `columns` mà bảng hiện tại còn thiếu. Giúp DB cũ (tạo từ phiên
    bản code trước) luôn tương thích với code mới mà không cần xoá DB."""
    existing = {r["name"] for r in conn.execute(f"PRAGMA table_info({table})").fetchall()}
    for name, decl in columns.items():
        if name not in existing:
            try:
                conn.execute(f"ALTER TABLE {table} ADD COLUMN {name} {decl}")
            except sqlite3.OperationalError:
                # Cột có thể đã được thêm bởi 1 lần chạy song song khác — bỏ qua an toàn.
                pass


def now_utc():
    return datetime.now(timezone.utc)


def iso(dt):
    return dt.isoformat(timespec="seconds") if dt else None


def today_str():
    return now_utc().date().isoformat()


def make_key(prefix: str | None = None):
    """Sinh key ngẫu nhiên. Nếu có prefix thì key = PREFIX-XXXXXX."""
    alphabet = "ABCDEFGHJKLMNPQRSTUVWXYZ23456789"

    base = (prefix or "DHP-IPA").strip().upper()
    base = re.sub(r"[^A-Z0-9\-]", "", base) or "DHP-IPA"
    base = base.strip("-") or "DHP-IPA"

    while True:
        value = base + "-" + "".join(secrets.choice(alphabet) for _ in range(6))
        conn = db()
        found = conn.execute("SELECT 1 FROM keys WHERE key=?", (value,)).fetchone()
        conn.close()
        if not found:
            return value


def get_devices(row) -> list[str]:
    """Trả về danh sách UDID thiết bị đã gắn với key (lưu dạng CSV trong cột device)."""
    raw = (row["device"] or "").strip()
    if not raw:
        return []
    return [d.strip() for d in raw.split(",") if d.strip()]


def devices_to_str(devices: list[str]) -> str:
    return ",".join(devices)


def row_get(row, key: str, default=None):
    """Đọc 1 cột từ sqlite3.Row một cách an toàn — không crash nếu DB cũ
    (được tạo từ 1 bản code trước) thiếu cột này. Luôn nên dùng hàm này
    thay vì row["ten_cot"] trực tiếp ở những chỗ đọc dữ liệu người dùng."""
    try:
        return row[key]
    except (IndexError, KeyError):
        return default


# ============================================================
# AUTH DECORATORS
# ============================================================

def admin_required(fn):
    @wraps(fn)
    def wrapper(*args, **kwargs):
        if not session.get("admin_logged_in"):
            if request.path.startswith("/admin/api/"):
                return jsonify(ok=False, error="Phiên đăng nhập đã hết hạn"), 401
            return redirect(url_for("admin_login"))
        return fn(*args, **kwargs)
    return wrapper


def get_seller_row(username: str):
    conn = db()
    row = conn.execute("SELECT * FROM sellers WHERE username=?", (username,)).fetchone()
    conn.close()
    return row


def seller_required(fn):
    @wraps(fn)
    def wrapper(*args, **kwargs):
        is_api = request.path.startswith("/seller/api/")

        if not session.get("seller_logged_in"):
            if is_api:
                return jsonify(ok=False, error="Phiên đăng nhập đã hết hạn"), 401
            return redirect(url_for("seller_login"))

        row = get_seller_row(session.get("seller_user", ""))
        if not row:
            session.clear()
            if is_api:
                return jsonify(ok=False, error="Tài khoản không tồn tại"), 403
            return redirect(url_for("seller_login"))

        if row_get(row, "banned", 0):
            session.clear()
            if is_api:
                return jsonify(ok=False, error="Tài khoản seller đã bị khoá"), 403
            return redirect(url_for("seller_login"))

        seller_expires = row_get(row, "expires_at")
        if seller_expires:
            try:
                if datetime.fromisoformat(seller_expires) <= now_utc():
                    session.clear()
                    if is_api:
                        return jsonify(ok=False, error="Tài khoản seller đã hết hạn"), 403
                    return redirect(url_for("seller_login"))
            except ValueError:
                pass

        return fn(*args, **kwargs)
    return wrapper


# ============================================================
# LOGIN PAGE (dùng chung cho admin & seller)
# ============================================================

LOGIN_HTML = r"""
<!doctype html>
<html lang="vi">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1">
<title>SHOP DHP · Đăng nhập</title>
<style>
*{box-sizing:border-box}
body{margin:0;min-height:100vh;display:grid;place-items:center;background:#050509;color:#fff;font-family:-apple-system,BlinkMacSystemFont,"Segoe UI",Arial}
.card{width:min(420px,92vw);padding:24px;border:1px solid #30264f;border-radius:18px;background:#0b0b11;box-shadow:0 20px 70px #000}
h1{margin:0 0 8px;font-size:22px}
p{color:#8e8da1;font-size:13px}
input{width:100%;padding:12px;margin:7px 0;border-radius:10px;border:1px solid #332957;background:#111117;color:#fff;outline:none}
button{width:100%;padding:12px;margin-top:10px;border:0;border-radius:10px;background:linear-gradient(90deg,#8b5cf6,#3b82f6);color:#fff;font-weight:900;cursor:pointer}
.err{margin-top:10px;color:#fca5a5;font-size:12px}
</style>
</head>
<body>
<form class="card" method="post" action="{{ action }}">
<h1>{{ title }}</h1>
<p>{{ subtitle }}</p>
<input name="username" autocomplete="username" placeholder="Tài khoản" required>
<input name="password" type="password" autocomplete="current-password" placeholder="Mật khẩu" required>
<button>Đăng nhập</button>
{% if error %}<div class="err">{{ error }}</div>{% endif %}
</form>
</body>
</html>
"""


@app.route("/admin/login", methods=["GET", "POST"])
def admin_login():
    if request.method == "POST":
        username = request.form.get("username", "")
        password = request.form.get("password", "")
        if secrets.compare_digest(username, ADMIN_USER) and secrets.compare_digest(password, ADMIN_PASS):
            session.clear()
            session.permanent = True
            session["admin_logged_in"] = True
            session["admin_user"] = username
            return redirect(url_for("admin_root"))
        return render_template_string(
            LOGIN_HTML, error="Sai tài khoản hoặc mật khẩu.",
            title="ADMIN DASHBOARD", subtitle="Đăng nhập quản trị SHOP DHP",
            action=url_for("admin_login"),
        )
    return render_template_string(
        LOGIN_HTML, error=None,
        title="ADMIN DASHBOARD", subtitle="Đăng nhập quản trị SHOP DHP",
        action=url_for("admin_login"),
    )


@app.route("/admin/logout")
def admin_logout():
    session.clear()
    return redirect(url_for("admin_login"))


@app.route("/serveripa/login", methods=["GET", "POST"])
def seller_login():
    if request.method == "POST":
        username = request.form.get("username", "")
        password = request.form.get("password", "")
        row = get_seller_row(username)

        common = dict(
            title="SELLER DASHBOARD", subtitle="Đăng nhập tài khoản Seller SHOP DHP",
            action=url_for("seller_login"),
        )

        if not row or not check_password_hash(row_get(row, "password_hash", ""), password):
            return render_template_string(LOGIN_HTML, error="Sai tài khoản hoặc mật khẩu.", **common)

        if row_get(row, "banned", 0):
            return render_template_string(LOGIN_HTML, error="Tài khoản seller đã bị khoá.", **common)

        seller_expires = row_get(row, "expires_at")
        if seller_expires:
            try:
                if datetime.fromisoformat(seller_expires) <= now_utc():
                    return render_template_string(LOGIN_HTML, error="Tài khoản seller đã hết hạn.", **common)
            except ValueError:
                pass

        session.clear()
        session.permanent = True
        session["seller_logged_in"] = True
        session["seller_user"] = username
        return redirect(url_for("seller_root"))

    return render_template_string(
        LOGIN_HTML, error=None,
        title="SELLER DASHBOARD", subtitle="Đăng nhập tài khoản Seller SHOP DHP",
        action=url_for("seller_login"),
    )


@app.route("/serveripa/logout")
def seller_logout():
    session.clear()
    return redirect(url_for("seller_login"))


def key_status(row):
    if row["banned"]:
        return "banned"
    if row["expires_at"]:
        try:
            if datetime.fromisoformat(row["expires_at"]) <= now_utc():
                return "expired"
        except ValueError:
            pass
    if row["locked"]:
        return "banned"
    return "active" if row["device"] else "unused"


# ============================================================
# ADMIN API — KEYS
# ============================================================

@app.route("/admin/api/keys/all")
@admin_required
def api_keys_all():
    q = request.args.get("q", "").strip().lower()
    status_filter = request.args.get("status", "all")
    type_filter = request.args.get("type", "all")
    seller_filter = request.args.get("seller", "all")

    conn = db()
    rows = conn.execute("SELECT * FROM keys ORDER BY id DESC").fetchall()
    items = []

    for row in rows:
        status = key_status(row)
        haystack = " ".join([
            row["key"] or "", row["device"] or "", row["ip"] or "",
            row["created_by"] or "", row["type_name"] or ""
        ]).lower()

        if q and q not in haystack:
            continue
        if status_filter != "all" and status != status_filter:
            continue
        if type_filter != "all" and row["type"] != type_filter:
            continue
        if seller_filter != "all" and row["created_by"] != seller_filter:
            continue

        devices = get_devices(row)
        items.append({
            "key": row["key"],
            "type": row["type"],
            "type_name": row["type_name"],
            "duration_label": row["duration_label"],
            "status": status,
            "banned": bool(row["banned"]),
            "locked": bool(row["locked"]),
            "ban_reason": row["ban_reason"] or (BAN_REASON_DEFAULT if row["banned"] else ""),
            "device": row["device"] or "",
            "devices": devices,
            "device_count": len(devices),
            "ip": row["ip"] or "",
            "created_by": row["created_by"],
            "expires": row["expires_at"] or "Vĩnh viễn",
            "max_devices": row["max_devices"],
        })

    types = [{"code": DEFAULT_TYPE_CODE, "name": DEFAULT_TYPE_NAME}]
    sellers = sorted({x["created_by"] for x in items if x["created_by"]})
    conn.close()

    return jsonify(ok=True, items=items, total=len(items), types=types, sellers=sellers)


@app.route("/admin/api/keys/create_custom", methods=["POST"])
@admin_required
def api_create_custom():
    data = request.get_json(silent=True) or {}
    duration = str(data.get("time_value", "1h"))
    mode = str(data.get("mode", "auto"))  # auto | prefix | custom

    try:
        qty = max(1, min(int(data.get("qty", 1)), 10000))
        max_devices = max(1, min(int(data.get("max_devices", 1)), 1_000_000))
    except (TypeError, ValueError):
        return jsonify(ok=False, error="Số lượng không hợp lệ"), 400

    # Thời hạn theo số giờ tuỳ chỉnh (chỉ admin mới có, nhập số giờ bất kỳ)
    if duration == "custom_hours":
        try:
            hours = float(data.get("custom_hours", 0))
        except (TypeError, ValueError):
            return jsonify(ok=False, error="Số giờ không hợp lệ"), 400
        if hours <= 0 or hours > 24 * 366 * 5:
            return jsonify(ok=False, error="Số giờ phải lớn hơn 0 và hợp lý"), 400
        if hours == int(hours):
            label = f"{int(hours)} giờ (tuỳ chỉnh)"
        else:
            label = f"{hours:g} giờ (tuỳ chỉnh)"
        delta = timedelta(hours=hours)
    elif duration not in DURATIONS:
        return jsonify(ok=False, error="Thời hạn không hợp lệ"), 400
    else:
        label, delta = DURATIONS[duration]

    created_at = now_utc()
    expires_at = iso(created_at + delta) if delta else None
    created = []

    conn = db()
    try:
        if mode == "custom":
            # Tạo key tự do, đúng y chang chuỗi nhập vào (VD: DHPDEPTRAI), chỉ 1 key/lần
            raw = str(data.get("custom_key", "")).strip().upper()
            raw = re.sub(r"[^A-Z0-9\-_]", "", raw)
            if not raw:
                conn.close()
                return jsonify(ok=False, error="Vui lòng nhập key tuỳ chỉnh"), 400
            exists = conn.execute("SELECT 1 FROM keys WHERE key=?", (raw,)).fetchone()
            if exists:
                conn.close()
                return jsonify(ok=False, error="Key này đã tồn tại, vui lòng chọn key khác"), 400
            conn.execute("""
                INSERT INTO keys
                (key,type,type_name,duration_code,duration_label,created_by,
                 created_at,expires_at,max_devices)
                VALUES (?,?,?,?,?,?,?,?,?)
            """, (
                raw, DEFAULT_TYPE_CODE, DEFAULT_TYPE_NAME, duration, label,
                session.get("admin_user", "admin"), iso(created_at),
                expires_at, max_devices
            ))
            created.append(raw)

        else:
            prefix = None
            if mode == "prefix":
                # Tạo key với tiền tố tự chọn, phần đuôi random: PREFIX-XXXXXX
                prefix = str(data.get("prefix", "")).strip().upper()
                prefix = re.sub(r"[^A-Z0-9]", "", prefix)
                if not prefix:
                    conn.close()
                    return jsonify(ok=False, error="Vui lòng nhập tiền tố key"), 400

            for _ in range(qty):
                value = make_key(prefix)
                conn.execute("""
                    INSERT INTO keys
                    (key,type,type_name,duration_code,duration_label,created_by,
                     created_at,expires_at,max_devices)
                    VALUES (?,?,?,?,?,?,?,?,?)
                """, (
                    value, DEFAULT_TYPE_CODE, DEFAULT_TYPE_NAME, duration, label,
                    session.get("admin_user", "admin"), iso(created_at),
                    expires_at, max_devices
                ))
                created.append(value)

        conn.commit()
    except Exception:
        conn.rollback()
        raise
    finally:
        conn.close()

    return jsonify(ok=True, keys=created, count=len(created))


@app.route("/admin/api/keys/ban", methods=["POST"])
@admin_required
def api_ban():
    data = request.get_json(silent=True) or {}
    keys = data.get("keys") or []
    reason = str(data.get("reason") or BAN_REASON_DEFAULT)
    conn = db()
    conn.executemany(
        "UPDATE keys SET banned=1, ban_reason=? WHERE key=?",
        [(reason, str(k)) for k in keys]
    )
    conn.commit()
    conn.close()
    return jsonify(ok=True)


@app.route("/admin/api/keys/unban", methods=["POST"])
@admin_required
def api_unban():
    data = request.get_json(silent=True) or {}
    keys = data.get("keys") or []
    conn = db()
    conn.executemany(
        "UPDATE keys SET banned=0, ban_reason='' WHERE key=?",
        [(str(k),) for k in keys]
    )
    conn.commit()
    conn.close()
    return jsonify(ok=True)


@app.route("/admin/api/keys/lock", methods=["POST"])
@admin_required
def api_lock():
    data = request.get_json(silent=True) or {}
    key = str(data.get("key", ""))
    if not key:
        return jsonify(ok=False, error="Thiếu key cần khoá"), 400

    conn = db()
    conn.execute(
        "UPDATE keys SET locked=1, ban_reason=? WHERE key=?",
        (BAN_REASON_DEFAULT, key)
    )
    conn.commit()
    conn.close()
    return jsonify(ok=True, message="Đã khoá key")


@app.route("/admin/api/keys/unlock", methods=["POST"])
@admin_required
def api_unlock():
    data = request.get_json(silent=True) or {}
    key = str(data.get("key", ""))
    conn = db()
    conn.execute("UPDATE keys SET locked=0 WHERE key=?", (key,))
    conn.commit()
    conn.close()
    return jsonify(ok=True)


@app.route("/admin/api/keys/reset", methods=["POST"])
@admin_required
def api_admin_reset_key():
    """Reset key về trạng thái CHƯA DÙNG (gỡ thiết bị/IP đã gắn)."""
    data = request.get_json(silent=True) or {}
    keys = data.get("keys") or ([data["key"]] if data.get("key") else [])
    if not keys:
        return jsonify(ok=False, error="Thiếu key cần reset"), 400
    conn = db()
    conn.executemany("UPDATE keys SET device='', ip='' WHERE key=?", [(str(k),) for k in keys])
    conn.commit()
    conn.close()
    return jsonify(ok=True)


@app.route("/admin/api/keys/delete", methods=["POST"])
@admin_required
def api_delete_key():
    data = request.get_json(silent=True) or {}
    keys = data.get("keys") or ([data["key"]] if data.get("key") else [])
    if not keys:
        return jsonify(ok=False, error="Thiếu key cần xoá"), 400
    conn = db()
    conn.executemany("DELETE FROM keys WHERE key=?", [(str(k),) for k in keys])
    conn.commit()
    conn.close()
    return jsonify(ok=True)


@app.route("/admin/api/keys/delete_all", methods=["POST"])
@admin_required
def api_delete_all_keys():
    conn = db()
    conn.execute("DELETE FROM keys")
    conn.commit()
    conn.close()
    return jsonify(ok=True)


@app.route("/admin/api/keys/bulk_extend", methods=["POST"])
@admin_required
def api_bulk_extend():
    """Cộng thêm thời hạn cho TẤT CẢ key phù hợp bộ lọc (loại key, thời hạn hiện tại, trạng thái)."""
    data = request.get_json(silent=True) or {}

    unit = str(data.get("unit", "1d"))
    if unit not in DURATIONS:
        return jsonify(ok=False, error="Đơn vị thời gian không hợp lệ"), 400

    try:
        multiplier = max(1, min(int(data.get("multiplier", 1)), 999))
    except (TypeError, ValueError):
        return jsonify(ok=False, error="Số lượng cộng không hợp lệ"), 400

    type_filter = str(data.get("type", "all"))
    current_duration_filter = str(data.get("current_duration", "all"))
    activity_filter = str(data.get("activity", "all"))  # all | active | unused

    _, unit_delta = DURATIONS[unit]

    conn = db()
    rows = conn.execute("SELECT * FROM keys").fetchall()

    matched = 0
    updated = 0
    now = now_utc()

    for row in rows:
        if type_filter != "all" and row["type"] != type_filter:
            continue
        if current_duration_filter != "all" and row["duration_code"] != current_duration_filter:
            continue

        status = key_status(row)
        if activity_filter == "active" and status != "active":
            continue
        if activity_filter == "unused" and status != "unused":
            continue

        matched += 1

        if unit == "permanent":
            # Cộng "Vĩnh viễn" nghĩa là biến key đó thành vĩnh viễn (bỏ hạn dùng)
            conn.execute("UPDATE keys SET expires_at=NULL WHERE key=?", (row["key"],))
            updated += 1
            continue

        if row["expires_at"] is None:
            # Key đang vĩnh viễn thì không có gì để cộng thêm
            continue

        try:
            current_expiry = datetime.fromisoformat(row["expires_at"])
        except ValueError:
            current_expiry = now

        base = current_expiry if current_expiry > now else now
        new_expiry = base + (unit_delta * multiplier)

        conn.execute("UPDATE keys SET expires_at=? WHERE key=?", (iso(new_expiry), row["key"]))
        updated += 1

    conn.commit()
    conn.close()

    return jsonify(ok=True, matched=matched, updated=updated)


@app.route("/admin/api/stats/overview")
@admin_required
def api_stats():
    conn = db()
    total_keys = conn.execute("SELECT COUNT(*) FROM keys").fetchone()[0]
    total_users = conn.execute(
        "SELECT COUNT(DISTINCT device) FROM keys WHERE device <> ''"
    ).fetchone()[0]
    conn.close()
    return jsonify(ok=True, total_keys=total_keys, today={"total": total_users})


@app.route("/admin/api/sellers/list")
@admin_required
def api_sellers_list_legacy():
    """Danh sách tên seller đã từng tạo key (giữ để tương thích ngược)."""
    conn = db()
    rows = conn.execute(
        "SELECT DISTINCT created_by FROM keys WHERE created_by <> ''"
    ).fetchall()
    conn.close()
    return jsonify(ok=True, items=[{"username": r["created_by"]} for r in rows])


# ============================================================
# ADMIN API — SELLER ACCOUNT MANAGEMENT
# ============================================================

@app.route("/admin/api/sellers/create", methods=["POST"])
@admin_required
def api_sellers_create():
    data = request.get_json(silent=True) or {}
    username = str(data.get("username", "")).strip()
    password = str(data.get("password", "")).strip()

    try:
        days = int(data.get("days", 30))
    except (TypeError, ValueError):
        return jsonify(ok=False, error="Thời hạn không hợp lệ"), 400

    if not username or not password:
        return jsonify(ok=False, error="Vui lòng nhập tài khoản và mật khẩu"), 400
    if len(password) < 4:
        return jsonify(ok=False, error="Mật khẩu tối thiểu 4 ký tự"), 400

    conn = db()
    try:
        exists = conn.execute("SELECT 1 FROM sellers WHERE username=?", (username,)).fetchone()
        if exists:
            return jsonify(ok=False, error="Tài khoản seller đã tồn tại"), 400

        created_at = now_utc()
        expires_at = iso(created_at + timedelta(days=days)) if days > 0 else None

        conn.execute("""
            INSERT INTO sellers
            (username,password_hash,created_at,expires_at,banned,daily_quota,daily_created,daily_date)
            VALUES (?,?,?,?,0,?,0,'')
        """, (
            username, generate_password_hash(password), iso(created_at), expires_at,
            SELLER_DEFAULT_DAILY_QUOTA
        ))
        conn.commit()
    except Exception as exc:
        conn.rollback()
        return jsonify(ok=False, error=f"Không tạo được seller: {exc}"), 500
    finally:
        conn.close()

    return jsonify(ok=True)


@app.route("/admin/api/sellers/all")
@admin_required
def api_sellers_all():
    conn = db()
    try:
        rows = conn.execute("SELECT * FROM sellers ORDER BY id DESC").fetchall()
        today = today_str()

        items = []
        for r in rows:
            daily_quota = row_get(r, "daily_quota", SELLER_DEFAULT_DAILY_QUOTA) or SELLER_DEFAULT_DAILY_QUOTA
            daily_created = row_get(r, "daily_created", 0) or 0
            daily_date = row_get(r, "daily_date", "") or ""
            expires_at = row_get(r, "expires_at")
            username = row_get(r, "username", "")

            created_today = daily_created if daily_date == today else 0
            remaining = max(0, daily_quota - created_today)

            device_count = conn.execute(
                "SELECT COUNT(*) FROM keys WHERE created_by=? AND device<>''", (username,)
            ).fetchone()[0]
            key_count = conn.execute(
                "SELECT COUNT(*) FROM keys WHERE created_by=?", (username,)
            ).fetchone()[0]

            expired = False
            if expires_at:
                try:
                    expired = datetime.fromisoformat(expires_at) <= now_utc()
                except ValueError:
                    pass

            items.append({
                "id": row_get(r, "id"),
                "username": username,
                "created_at": row_get(r, "created_at", "") or "",
                "expires_at": expires_at or "Vĩnh viễn",
                "banned": bool(row_get(r, "banned", 0)),
                "expired": expired,
                "remaining": remaining,
                "quota": daily_quota,
                "device_count": device_count,
                "key_count": key_count,
            })

        return jsonify(ok=True, items=items, total=len(items))
    except Exception as exc:
        return jsonify(ok=False, error=f"Lỗi máy chủ khi tải danh sách seller: {exc}"), 500
    finally:
        conn.close()


@app.route("/admin/api/sellers/ban_keys", methods=["POST"])
@admin_required
def api_sellers_ban_keys():
    """Admin khoá TOÀN BỘ key của 1 seller."""
    data = request.get_json(silent=True) or {}
    username = str(data.get("username", ""))
    if not username:
        return jsonify(ok=False, error="Thiếu username"), 400
    conn = db()
    conn.execute(
        "UPDATE keys SET banned=1, ban_reason=? WHERE created_by=?",
        (BAN_REASON_DEFAULT, username)
    )
    conn.commit()
    conn.close()
    return jsonify(ok=True)


@app.route("/admin/api/sellers/toggle_ban", methods=["POST"])
@admin_required
def api_sellers_toggle_ban():
    data = request.get_json(silent=True) or {}
    username = str(data.get("username", ""))
    banned = 1 if data.get("banned") else 0
    conn = db()
    conn.execute("UPDATE sellers SET banned=? WHERE username=?", (banned, username))
    conn.commit()
    conn.close()
    return jsonify(ok=True)


@app.route("/admin/api/sellers/delete", methods=["POST"])
@admin_required
def api_sellers_delete():
    data = request.get_json(silent=True) or {}
    username = str(data.get("username", ""))
    conn = db()
    conn.execute("DELETE FROM sellers WHERE username=?", (username,))
    conn.commit()
    conn.close()
    return jsonify(ok=True)


# ============================================================
# SELLER API — chỉ thao tác trên key của chính seller đó
# ============================================================

@app.route("/seller/api/keys/mine")
@seller_required
def api_seller_keys_mine():
    username = session.get("seller_user")
    q = request.args.get("q", "").strip().lower()
    status_filter = request.args.get("status", "all")

    conn = db()
    rows = conn.execute(
        "SELECT * FROM keys WHERE created_by=? ORDER BY id DESC", (username,)
    ).fetchall()

    items = []
    for row in rows:
        status = key_status(row)
        haystack = " ".join([row["key"] or "", row["device"] or "", row["ip"] or ""]).lower()

        if q and q not in haystack:
            continue
        if status_filter != "all" and status != status_filter:
            continue

        devices = get_devices(row)
        items.append({
            "key": row["key"],
            "type_name": row["type_name"],
            "duration_label": row["duration_label"],
            "status": status,
            "banned": bool(row["banned"]),
            "ban_reason": row["ban_reason"] or (BAN_REASON_DEFAULT if row["banned"] else ""),
            "device": row["device"] or "",
            "devices": devices,
            "device_count": len(devices),
            "max_devices": row["max_devices"],
            "created_by": row["created_by"],
            "expires": row["expires_at"] or "Vĩnh viễn",
        })

    conn.close()
    return jsonify(ok=True, items=items, total=len(items))


@app.route("/seller/api/keys/create", methods=["POST"])
@seller_required
def api_seller_create_keys():
    username = session.get("seller_user")
    data = request.get_json(silent=True) or {}
    duration = str(data.get("time_value", "2h"))

    if duration not in SELLER_ALLOWED_DURATIONS:
        return jsonify(ok=False, error="Thời hạn không hợp lệ"), 400

    try:
        qty = int(data.get("qty", 1))
    except (TypeError, ValueError):
        return jsonify(ok=False, error="Số lượng không hợp lệ"), 400

    if qty < 1 or qty > SELLER_MAX_PER_CREATE:
        return jsonify(ok=False, error=f"Mỗi lần chỉ được tạo tối đa {SELLER_MAX_PER_CREATE} key"), 400

    conn = db()
    row = conn.execute("SELECT * FROM sellers WHERE username=?", (username,)).fetchone()
    if not row:
        conn.close()
        return jsonify(ok=False, error="Tài khoản không tồn tại"), 403

    today = today_str()
    daily_quota = row_get(row, "daily_quota", SELLER_DEFAULT_DAILY_QUOTA) or SELLER_DEFAULT_DAILY_QUOTA
    daily_created = row_get(row, "daily_created", 0) or 0
    daily_date = row_get(row, "daily_date", "") or ""
    created_today = daily_created if daily_date == today else 0
    remaining = daily_quota - created_today

    if qty > remaining:
        conn.close()
        return jsonify(
            ok=False,
            error=f"Bạn chỉ còn tạo được {max(0, remaining)} key trong hôm nay "
                  f"(giới hạn {daily_quota} key/ngày)"
        ), 400

    label, delta = DURATIONS[duration]
    created_at = now_utc()
    expires_at = iso(created_at + delta) if delta else None
    created = []
    created_details = []

    try:
        for _ in range(qty):
            value = make_key()
            conn.execute("""
                INSERT INTO keys
                (key,type,type_name,duration_code,duration_label,created_by,
                 created_at,expires_at,max_devices)
                VALUES (?,?,?,?,?,?,?,?,?)
            """, (
                value, DEFAULT_TYPE_CODE, DEFAULT_TYPE_NAME, duration, label,
                username, iso(created_at), expires_at, 1
            ))
            created.append(value)
            created_details.append({
                "key": value,
                "duration_label": label,
                "expires_at": expires_at or "Vĩnh viễn",
                "status": "unused",
                "max_devices": 1,
            })

        conn.execute(
            "UPDATE sellers SET daily_created=?, daily_date=? WHERE username=?",
            (created_today + qty, today, username)
        )
        conn.commit()
    except Exception:
        conn.rollback()
        conn.close()
        raise

    conn.close()
    return jsonify(ok=True, keys=created, items=created_details, count=len(created), remaining=max(0, remaining - qty))


@app.route("/seller/api/keys/reset", methods=["POST"])
@seller_required
def api_seller_reset_key():
    """Seller chỉ được reset (đưa về chưa dùng) key do chính mình tạo. Không được ban/unban."""
    username = session.get("seller_user")
    data = request.get_json(silent=True) or {}
    key = str(data.get("key", ""))

    conn = db()
    row = conn.execute(
        "SELECT * FROM keys WHERE key=? AND created_by=?", (key, username)
    ).fetchone()
    if not row:
        conn.close()
        return jsonify(ok=False, error="Không tìm thấy key hoặc key không thuộc về bạn"), 404

    if row["banned"]:
        conn.close()
        return jsonify(ok=False, error="Key đã bị admin khoá, không thể reset. Vui lòng liên hệ admin."), 403

    conn.execute("UPDATE keys SET device='', ip='' WHERE key=?", (key,))
    conn.commit()
    conn.close()
    return jsonify(ok=True)


@app.route("/seller/api/stats")
@seller_required
def api_seller_stats():
    username = session.get("seller_user")
    conn = db()
    try:
        row = conn.execute("SELECT * FROM sellers WHERE username=?", (username,)).fetchone()
        if not row:
            return jsonify(ok=False, error="Tài khoản không tồn tại"), 403

        today = today_str()
        daily_quota = row_get(row, "daily_quota", SELLER_DEFAULT_DAILY_QUOTA) or SELLER_DEFAULT_DAILY_QUOTA
        daily_created = row_get(row, "daily_created", 0) or 0
        daily_date = row_get(row, "daily_date", "") or ""
        created_today = daily_created if daily_date == today else 0
        total_keys = conn.execute(
            "SELECT COUNT(*) FROM keys WHERE created_by=?", (username,)
        ).fetchone()[0]

        return jsonify(
            ok=True,
            username=username,
            quota=daily_quota,
            created_today=created_today,
            remaining=max(0, daily_quota - created_today),
            total_keys=total_keys,
            max_per_create=SELLER_MAX_PER_CREATE,
            expires_at=row_get(row, "expires_at") or "Vĩnh viễn",
        )
    except Exception as exc:
        return jsonify(ok=False, error=f"Lỗi máy chủ: {exc}"), 500
    finally:
        conn.close()


# ============================================================
# PUBLIC API — kích hoạt key trên thiết bị (nhập UDID)
# ============================================================

@app.route("/api/keys/activate", methods=["POST"])
def api_key_activate():
    """Client (app / thiết bị) gọi API này khi người dùng nhập key để dùng.
    UDID thiết bị sẽ được gắn vào key và hiển thị ở cột 'Thiết bị' trên dashboard."""
    data = request.get_json(silent=True) or {}
    key = str(data.get("key", "")).strip()
    udid = str(data.get("udid") or data.get("device_id") or "").strip()
    device_name = str(data.get("device_name", "")).strip()
    ip = request.headers.get("X-Forwarded-For", request.remote_addr) or ""
    ip = ip.split(",")[0].strip()

    if not key:
        return jsonify(ok=False, error="Thiếu key"), 400
    if not udid:
        return jsonify(ok=False, error="Thiếu UDID thiết bị"), 400

    conn = db()
    row = conn.execute("SELECT * FROM keys WHERE key=?", (key,)).fetchone()
    if not row:
        conn.close()
        return jsonify(ok=False, error="Key không tồn tại"), 404

    status = key_status(row)
    if status == "banned":
        conn.close()
        return jsonify(ok=False, error=row["ban_reason"] or BAN_REASON_DEFAULT), 403
    if status == "expired":
        conn.close()
        return jsonify(ok=False, error="Key đã hết hạn"), 403

    devices = get_devices(row)
    label = f"{udid}" + (f" ({device_name})" if device_name else "")
    existing_udids = [d.split(" (")[0] for d in devices]

    if udid in existing_udids:
        conn.execute("UPDATE keys SET ip=? WHERE key=?", (ip, key))
        conn.commit()
        conn.close()
        return jsonify(
            ok=True, message="Thiết bị đã được kích hoạt trước đó",
            expires_at=row["expires_at"] or "Vĩnh viễn",
            device_count=len(devices), max_devices=row["max_devices"],
        )

    if len(devices) >= row["max_devices"]:
        conn.close()
        if row["max_devices"] == 1:
            return jsonify(ok=False, error="Key đã sử dụng cho thiết bị khác", code="DEVICE_BOUND"), 403
        return jsonify(ok=False, error="Key đã đạt giới hạn số thiết bị được phép dùng chung", code="DEVICE_LIMIT"), 403

    devices.append(label)
    conn.execute("UPDATE keys SET device=?, ip=? WHERE key=?", (devices_to_str(devices), ip, key))
    conn.commit()
    conn.close()

    return jsonify(
        ok=True, message="Kích hoạt key thành công",
        expires_at=row["expires_at"] or "Vĩnh viễn",
        device_count=len(devices), max_devices=row["max_devices"],
    )


@app.route("/api/keys/verify", methods=["POST"])
def api_key_verify():
    """Kiểm tra trạng thái key (không gắn thiết bị mới)."""
    data = request.get_json(silent=True) or {}
    key = str(data.get("key", "")).strip()
    if not key:
        return jsonify(ok=False, error="Thiếu key"), 400

    conn = db()
    row = conn.execute("SELECT * FROM keys WHERE key=?", (key,)).fetchone()
    conn.close()
    if not row:
        return jsonify(ok=False, status="not_found", error="Key không tồn tại"), 404

    status = key_status(row)
    if status == "banned":
        error = row["ban_reason"] or BAN_REASON_DEFAULT
    elif status == "expired":
        error = "Key đã hết hạn"
    else:
        error = ""

    return jsonify(
        ok=(status not in ("banned", "expired")),
        status=status,
        error=error,
        expires_at=row["expires_at"] or "Vĩnh viễn",
        device_count=len(get_devices(row)),
        max_devices=row["max_devices"],
        ban_reason=row["ban_reason"] if status == "banned" else "",
    )


# Trả JSON thay vì trang lỗi HTML cho mọi API khi có exception ngoài ý muốn
@app.errorhandler(500)
def handle_500(err):
    if request.path.startswith(("/admin/api/", "/seller/api/", "/api/")):
        return jsonify(ok=False, error="Lỗi máy chủ, vui lòng thử lại"), 500
    return err


# ============================================================
# ADMIN DASHBOARD
# ============================================================

ADMIN_DASHBOARD_HTML = r"""
<!doctype html>
<html lang="vi">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1,maximum-scale=1,user-scalable=no">
<title>SHOP DHP · Admin Dashboard</title>
<style>
:root{
    --bg:#050509;--panel:#09090d;--panel2:#0d0d13;--line:#30264f;--text:#f5f5f7;--muted:#8e8da1;
    --purple:#8b5cf6;--blue:#3b82f6;--cyan:#06b6d4;--green:#22c55e;--yellow:#f59e0b;--red:#ef4444;--pink:#ec4899;
}
*{box-sizing:border-box}
html,body{margin:0;padding:0;min-height:100%;
    background:radial-gradient(circle at 15% 0%,rgba(124,92,255,.13),transparent 32%),
               radial-gradient(circle at 90% 10%,rgba(236,72,153,.09),transparent 28%),var(--bg);
    color:var(--text);font-family:-apple-system,BlinkMacSystemFont,"Segoe UI",Roboto,Arial,sans-serif}
button,input,select{font:inherit}
button{cursor:pointer}
.wrap{width:min(1400px,96vw);margin:auto;padding:22px 0 50px}
.header{display:flex;align-items:center;justify-content:space-between;gap:15px;margin-bottom:18px;flex-wrap:wrap}
.brand{font-size:23px;font-weight:900;font-style:italic;letter-spacing:1px;
    background:linear-gradient(90deg,#a78bfa,#60a5fa,#ec4899);-webkit-background-clip:text;background-clip:text;color:transparent}
.headerbtns{display:flex;gap:8px}
.logout{border:0;border-radius:9px;padding:9px 15px;color:white;font-size:12px;font-weight:800;background:linear-gradient(90deg,#ef4444,#f97316)}
.linkbtn{border:1px solid #332957;border-radius:9px;padding:9px 15px;color:#c9c6ff;font-size:12px;font-weight:800;background:#111117;text-decoration:none;display:inline-block}
.card{background:linear-gradient(145deg,rgba(255,255,255,.035),rgba(255,255,255,.012));
    border:1px solid rgba(139,92,246,.40);border-radius:17px;padding:16px;margin-bottom:15px;box-shadow:0 18px 50px rgba(0,0,0,.25)}
.card-title{display:flex;align-items:center;justify-content:space-between;gap:10px;margin-bottom:13px;flex-wrap:wrap}
.card-title h2,.card-title h3{margin:0;font-size:15px;font-weight:900}
.stats{display:grid;grid-template-columns:repeat(auto-fit,minmax(150px,1fr));gap:9px}
.stat{min-height:74px;padding:12px;border-radius:13px;background:#08080d;border:1px solid var(--line);display:flex;flex-direction:column;justify-content:center}
.stat .label{color:var(--muted);font-size:9px;font-weight:800;letter-spacing:1.4px;text-transform:uppercase}
.stat .value{margin-top:3px;font-size:21px;line-height:1;font-weight:900}
.stat .sub{margin-top:5px;color:#777687;font-size:10px}
.stat.blue{border-color:rgba(59,130,246,.65)} .stat.purple{border-color:rgba(139,92,246,.65)}
.stat.cyan{border-color:rgba(6,182,212,.65)} .stat.green{border-color:rgba(34,197,94,.65)}
.stat.yellow{border-color:rgba(245,158,11,.65)} .stat.red{border-color:rgba(239,68,68,.65)}
.stat.pink{border-color:rgba(236,72,153,.65)}
.field{display:flex;flex-direction:column;gap:5px;min-width:0}
.field label{font-size:10px;font-weight:800;color:var(--muted);text-transform:uppercase;letter-spacing:.6px}
.create-grid{display:grid;grid-template-columns:repeat(auto-fit,minmax(150px,1fr));gap:10px;align-items:end}
.seller-grid{display:grid;grid-template-columns:repeat(auto-fit,minmax(150px,1fr));gap:10px;align-items:end}
.extend-grid{display:grid;grid-template-columns:repeat(auto-fit,minmax(150px,1fr));gap:10px;align-items:end}
.subcard{border:1px solid rgba(139,92,246,.28);border-radius:14px;padding:14px;margin-bottom:14px;background:rgba(255,255,255,.015)}
.subcard:last-child{margin-bottom:0}
.subcard-head{display:flex;align-items:center;gap:8px;margin-bottom:11px}
.subcard-head .stitle{font-size:13px;font-weight:900}
.subcard-head .stag{font-size:9px;font-weight:800;color:#c4b5fd;background:rgba(139,92,246,.15);border:1px solid rgba(139,92,246,.4);border-radius:6px;padding:3px 7px;text-transform:uppercase;letter-spacing:.5px}
.device-box{margin-top:12px;padding:13px;border-radius:12px;border:1px dashed rgba(139,92,246,.45);background:rgba(139,92,246,.05)}
.device-box .field label{color:#c4b5fd}
.device-box .hint{margin-top:7px}
.input,.select{width:100%;min-height:39px;border-radius:9px;border:1px solid #332957;background:#111117;color:#eee;padding:9px 11px;outline:none}
.input:focus,.select:focus{border-color:var(--purple);box-shadow:0 0 0 2px rgba(139,92,246,.12)}
.btn{min-height:39px;border:0;border-radius:9px;padding:8px 13px;color:#fff;font-weight:800;font-size:12px}
.btn-primary{background:linear-gradient(90deg,#8b5cf6,#3b82f6)}
.btn-green{background:linear-gradient(90deg,#16a34a,#22c55e)}
.btn-red{background:linear-gradient(90deg,#dc2626,#ef4444)}
.btn-blue{background:linear-gradient(90deg,#2563eb,#0ea5e9)}
.btn-pink{background:linear-gradient(90deg,#db2777,#ec4899)}
.btn-cyan{background:linear-gradient(90deg,#0891b2,#06b6d4)}
.btn-gray{background:#24242d;border:1px solid #3b3946}
.btn:hover{filter:brightness(1.12)}
.btn-full{width:100%}
.output{width:100%;min-height:70px;margin-top:10px;resize:vertical;border-radius:10px;border:1px solid #332957;background:#0d0d12;color:#d7d4ff;padding:11px;font-family:ui-monospace,SFMono-Regular,Menlo,monospace}
.hint{color:#777687;font-size:11px;margin-top:8px;line-height:1.5}
.qty-display{margin-top:10px;padding:10px 13px;border-radius:12px;background:rgba(139,92,246,.10);border:1px solid rgba(139,92,246,.4);display:flex;align-items:center;justify-content:space-between;gap:10px;flex-wrap:wrap}
.qty-display .qlabel{font-size:11px;color:var(--muted);font-weight:800;text-transform:uppercase;letter-spacing:.6px}
.qty-display .qvalue{font-size:22px;font-weight:900;color:#fff}
.filters{display:grid;grid-template-columns:repeat(auto-fit,minmax(150px,1fr));gap:8px}
.danger-note{margin-top:12px;padding:11px 13px;border-radius:10px;background:rgba(239,68,68,.08);border:1px solid rgba(239,68,68,.35);color:#fca5a5;font-size:11px;line-height:1.6}
.status-tabs{display:flex;gap:7px;flex-wrap:wrap;margin-bottom:12px}
.status-tab{border:1px solid #30264f;background:#0b0b10;color:#a9a6b8;border-radius:8px;padding:8px 12px;font-size:11px;font-weight:800}
.status-tab.active{color:#fff;border-color:#8b5cf6;background:linear-gradient(90deg,rgba(139,92,246,.28),rgba(59,130,246,.18))}
.table-wrap{overflow:auto;border-radius:11px;border:1px solid rgba(255,255,255,.06)}
.table-wrap.keys-scroll{max-height:640px;overflow-y:auto}
.table-wrap.keys-scroll thead th{position:sticky;top:0;background:#09090e;z-index:2;box-shadow:0 1px 0 rgba(255,255,255,.06)}
table{width:100%;min-width:1050px;border-collapse:collapse}
thead{background:#09090e}
th{padding:11px 10px;color:#77758a;font-size:9px;font-weight:900;text-transform:uppercase;letter-spacing:1px;text-align:left;white-space:nowrap}
td{padding:11px 10px;border-top:1px solid rgba(255,255,255,.055);font-size:11px;vertical-align:middle}
tbody tr:hover{background:rgba(139,92,246,.045)}
.key{color:#fff;font-family:ui-monospace,SFMono-Regular,Menlo,monospace;font-weight:900}
.device{max-width:190px;color:#aaa8b8;overflow:hidden;text-overflow:ellipsis;white-space:nowrap}
.device-count{display:inline-block;margin-left:6px;font-size:9px;color:#c4b5fd;background:rgba(139,92,246,.14);border:1px solid rgba(139,92,246,.35);border-radius:6px;padding:1px 5px}
.actions{display:flex;gap:5px;flex-wrap:wrap}
.badge{display:inline-flex;align-items:center;border-radius:6px;padding:4px 7px;font-size:9px;font-weight:900;white-space:nowrap}
.badge.active{color:#86efac;background:rgba(34,197,94,.12);border:1px solid rgba(34,197,94,.35)}
.badge.unused{color:#93c5fd;background:rgba(59,130,246,.12);border:1px solid rgba(59,130,246,.35)}
.badge.expired{color:#fcd34d;background:rgba(245,158,11,.12);border:1px solid rgba(245,158,11,.35)}
.badge.banned{color:#fca5a5;background:rgba(239,68,68,.12);border:1px solid rgba(239,68,68,.35)}
.ban-note{display:block;margin-top:4px;font-size:9px;color:#fca5a5;max-width:170px}
.empty{padding:30px;text-align:center;color:#777687}
.loading{padding:30px;text-align:center;color:#8b5cf6}

.created-key-info{margin-top:10px;gap:7px}
.created-key-row{display:flex;align-items:center;justify-content:space-between;gap:10px;padding:10px 12px;border:1px solid rgba(139,92,246,.22);border-radius:10px;background:rgba(139,92,246,.07)}
.created-key-value{font-family:ui-monospace,SFMono-Regular,Menlo,monospace;font-size:12px;font-weight:900;color:#fff;word-break:break-all}
.created-key-meta{margin-top:3px;font-size:10px;color:#9f9bad}
@media(max-width:800px){
    .wrap{width:94vw;padding-top:14px}
    .create-grid,.filters,.seller-grid{grid-template-columns:1fr}
    .stats{grid-template-columns:repeat(2,minmax(0,1fr))}
    .header{align-items:flex-start}
}
@media(max-width:480px){
    .stats{grid-template-columns:1fr 1fr}
    .card{padding:12px}
    .brand{font-size:19px}
}
</style>
</head>
<body>
<div class="wrap">

    <div class="header">
        <div class="brand">ADMIN DASHBOARD</div>
        <div class="headerbtns">
            <a class="linkbtn" href="/serveripa" target="_blank">🧑‍💼 Xem panel Seller</a>
            <button class="logout" onclick="location.href='/admin/logout'">Đăng xuất</button>
        </div>
    </div>

    <!-- THỐNG KÊ -->
    <div class="card">
        <div class="card-title">
            <h3>📊 Tổng quan hệ thống</h3>
            <button class="btn btn-gray" onclick="loadAll()">🔄 Làm mới</button>
        </div>
        <div class="stats">
            <div class="stat blue"><div class="label">Tổng User</div><div class="value" id="st_users">0</div><div class="sub">Người dùng hệ thống</div></div>
            <div class="stat purple"><div class="label">Tổng Seller</div><div class="value" id="st_sellers">0</div><div class="sub">Tài khoản seller</div></div>
            <div class="stat cyan"><div class="label">Tổng Key</div><div class="value" id="st_keys">0</div><div class="sub">Key toàn hệ thống</div></div>
            <div class="stat green"><div class="label">Đã dùng</div><div class="value" id="st_active">0</div><div class="sub">Key đang hoạt động</div></div>
            <div class="stat yellow"><div class="label">Chưa dùng</div><div class="value" id="st_unused">0</div><div class="sub">Key chưa kích hoạt</div></div>
            <div class="stat red"><div class="label">Hết hạn / khoá</div><div class="value" id="st_locked">0</div><div class="sub">Cần kiểm tra</div></div>
        </div>
    </div>

    <!-- TẠO KEY -->
    <div class="card">
        <div class="card-title"><h3>✨ Tạo Key Mới</h3></div>

        <!-- Khung 1: Random chuẩn -->
        <div class="subcard">
            <div class="subcard-head"><span class="stitle">🎲 Tạo Key Random Chuẩn</span><span class="stag">DHP-IPA-XXXXXX</span></div>
            <div class="create-grid">
                <div class="field">
                    <label>Thời hạn key</label>
                    <select class="select" id="r_duration">
                        <option value="1h">1 giờ</option>
                        <option value="2h">2 giờ</option>
                        <option value="1d">1 ngày</option>
                        <option value="7d">1 tuần</option>
                        <option value="1m">1 tháng</option>
                        <option value="3m">3 tháng</option>
                        <option value="1y">1 năm</option>
                        <option value="permanent">Vĩnh viễn</option>
                    </select>
                </div>
                <div class="field">
                    <label>Số lượng key</label>
                    <input class="input" id="r_qty" type="number" min="1" value="1" placeholder="VD: 10">
                </div>
                <div class="field">
                    <label>Số thiết bị / key</label>
                    <input class="input" id="r_devices" type="number" min="1" value="1" placeholder="VD: 1">
                </div>
                <div class="field">
                    <button class="btn btn-primary btn-full" onclick="createRandomKeys()">🔑 Tạo Key</button>
                </div>
            </div>
            <div class="hint">Key sinh ngẫu nhiên dạng DHP-IPA-XXXXXX, không cần nhập gì thêm.</div>
            <textarea id="out_random" class="output" readonly placeholder="Key vừa tạo sẽ hiển thị ở đây..."></textarea>
            <div class="qty-display"><span class="qlabel">Số lượng vừa tạo</span><span class="qvalue" id="qty_random">0</span></div>
            <div style="margin-top:8px"><button class="btn btn-gray" onclick="copyOut('out_random')">📋 Sao chép</button></div>
        </div>

        <!-- Khung 2: Tiền tố tự chọn -->
        <div class="subcard">
            <div class="subcard-head"><span class="stitle">🔤 Tạo Key Với Tiền Tố Tự Chọn</span><span class="stag">PREFIX-XXXXXX</span></div>
            <div class="create-grid">
                <div class="field">
                    <label>Tiền tố key</label>
                    <input class="input" id="p_prefix" placeholder="VD: DHPDEPTRAI">
                </div>
                <div class="field">
                    <label>Thời hạn key</label>
                    <select class="select" id="p_duration">
                        <option value="1h">1 giờ</option>
                        <option value="2h">2 giờ</option>
                        <option value="1d">1 ngày</option>
                        <option value="7d">1 tuần</option>
                        <option value="1m">1 tháng</option>
                        <option value="3m">3 tháng</option>
                        <option value="1y">1 năm</option>
                        <option value="permanent">Vĩnh viễn</option>
                    </select>
                </div>
                <div class="field">
                    <label>Số lượng key</label>
                    <input class="input" id="p_qty" type="number" min="1" value="1" placeholder="VD: 10">
                </div>
                <div class="field">
                    <label>Số thiết bị / key</label>
                    <input class="input" id="p_devices" type="number" min="1" value="1" placeholder="VD: 1">
                </div>
                <div class="field">
                    <button class="btn btn-blue btn-full" onclick="createPrefixKeys()">🔑 Tạo Key</button>
                </div>
            </div>
            <div class="hint">Nhập tiền tố, phần đuôi 6 ký tự random tự động. VD: DHPDEPTRAI → DHPDEPTRAI-XXXXXX. Có thể tạo nhiều key cùng lúc.</div>
            <textarea id="out_prefix" class="output" readonly placeholder="Key vừa tạo sẽ hiển thị ở đây..."></textarea>
            <div class="qty-display"><span class="qlabel">Số lượng vừa tạo</span><span class="qvalue" id="qty_prefix">0</span></div>
            <div style="margin-top:8px"><button class="btn btn-gray" onclick="copyOut('out_prefix')">📋 Sao chép</button></div>
        </div>

        <!-- Khung 3: Key tự do -->
        <div class="subcard">
            <div class="subcard-head"><span class="stitle">✍️ Tạo Key Tự Do (Nhập Tay)</span><span class="stag">1 key / lần</span></div>
            <div class="create-grid">
                <div class="field">
                    <label>Key tự do (giữ nguyên, không random)</label>
                    <input class="input" id="c_key" placeholder="VD: DHPDEPTRAI">
                </div>
                <div class="field">
                    <label>Thời hạn key</label>
                    <select class="select" id="c_duration">
                        <option value="1h">1 giờ</option>
                        <option value="2h">2 giờ</option>
                        <option value="1d">1 ngày</option>
                        <option value="7d">1 tuần</option>
                        <option value="1m">1 tháng</option>
                        <option value="3m">3 tháng</option>
                        <option value="1y">1 năm</option>
                        <option value="permanent">Vĩnh viễn</option>
                    </select>
                </div>
                <div class="field">
                    <label>Số thiết bị / key</label>
                    <input class="input" id="c_devices" type="number" min="1" value="1" placeholder="VD: 1">
                </div>
                <div class="field">
                    <button class="btn btn-pink btn-full" onclick="createCustomKey()">🔑 Tạo Key</button>
                </div>
            </div>
            <div class="hint">Key tự do: giữ nguyên chuỗi bạn nhập, không random, chỉ tạo được 1 key/lần.</div>
            <textarea id="out_custom" class="output" readonly placeholder="Key vừa tạo sẽ hiển thị ở đây..."></textarea>
            <div style="margin-top:8px"><button class="btn btn-gray" onclick="copyOut('out_custom')">📋 Sao chép</button></div>
        </div>

        <!-- Khung 4: Theo số giờ tuỳ chỉnh (chỉ Admin) -->
        <div class="subcard">
            <div class="subcard-head"><span class="stitle">⏱️ Tạo Key Theo Số Giờ Tuỳ Chỉnh</span><span class="stag">Chỉ Admin</span></div>
            <div class="create-grid">
                <div class="field">
                    <label>Số giờ tuỳ chỉnh</label>
                    <input class="input" id="h_hours" type="number" min="0.5" step="0.5" value="5" placeholder="VD: 5 (5 giờ)">
                </div>
                <div class="field">
                    <label>Số lượng key</label>
                    <input class="input" id="h_qty" type="number" min="1" value="1" placeholder="VD: 10">
                </div>
                <div class="field">
                    <label>Số thiết bị / key</label>
                    <input class="input" id="h_devices" type="number" min="1" value="1" placeholder="VD: 1">
                </div>
                <div class="field">
                    <button class="btn btn-cyan btn-full" onclick="createHourKeys()">🔑 Tạo Key</button>
                </div>
            </div>
            <div class="hint">Tạo key với thời hạn tính theo số giờ bất kỳ do admin nhập (VD: 5 giờ, 36 giờ, 12.5 giờ...), key dạng DHP-IPA-XXXXXX.</div>
            <textarea id="out_hours" class="output" readonly placeholder="Key vừa tạo sẽ hiển thị ở đây..."></textarea>
            <div class="qty-display"><span class="qlabel">Số lượng vừa tạo</span><span class="qvalue" id="qty_hours">0</span></div>
            <div style="margin-top:8px"><button class="btn btn-gray" onclick="copyOut('out_hours')">📋 Sao chép</button></div>
        </div>

        <!-- Khung riêng: số thiết bị -->
        <div class="device-box">
            <div class="hint" style="margin-top:0">📱 Mỗi khung tạo key ở trên đều có ô riêng "Số thiết bị / key" — nhập 1 nếu chỉ muốn 1 thiết bị dùng 1 key, nhập lớn hơn (VD: 1000) nếu muốn nhiều thiết bị dùng chung 1 key. UDID thiết bị sẽ tự động hiện ở cột "Thiết bị" trong bảng danh sách key khi thiết bị đó nhập key để kích hoạt.</div>
        </div>
    </div>

    <!-- CỘNG THỜI GIAN CHO ALL KEY -->
    <div class="card">
        <div class="card-title"><h3>⏰ Cộng Thời Gian Cho ALL Key</h3></div>
        <div class="hint" style="margin-top:0">Cộng thêm thời hạn cho tất cả key trong hệ thống. Có thể lọc theo loại key và theo thời hạn key hiện tại.</div>

        <div class="extend-grid" style="margin-top:12px">
            <div class="field">
                <label>Thời gian cộng</label>
                <select class="select" id="extend_unit">
                    <option value="1h">1 giờ</option>
                    <option value="2h" selected>2 giờ</option>
                    <option value="1d">1 ngày</option>
                    <option value="7d">1 tuần</option>
                    <option value="1m">1 tháng</option>
                    <option value="3m">3 tháng</option>
                    <option value="1y">1 năm</option>
                    <option value="permanent">Vĩnh viễn</option>
                </select>
            </div>

            <div class="field">
                <label>Số lần cộng</label>
                <input class="input" id="extend_multiplier" type="number" min="1" value="1" placeholder="VD: 1">
            </div>

            <div class="field">
                <label>Loại key</label>
                <select class="select" id="extend_type">
                    <option value="all">-- Tất cả --</option>
                    <option value="vip">KEY IPA Proxy - DHP</option>
                </select>
            </div>

            <div class="field">
                <label>Key còn thời hạn</label>
                <select class="select" id="extend_current_duration">
                    <option value="all">-- Tất cả --</option>
                    <option value="1h">1 giờ</option>
                    <option value="2h">2 giờ</option>
                    <option value="1d">1 ngày</option>
                    <option value="7d">1 tuần</option>
                    <option value="1m">1 tháng</option>
                    <option value="3m">3 tháng</option>
                    <option value="1y">1 năm</option>
                    <option value="permanent">Vĩnh viễn</option>
                </select>
            </div>
        </div>

        <div class="extend-grid" style="margin-top:10px">
            <div class="field">
                <label>Áp dụng cho</label>
                <select class="select" id="extend_activity">
                    <option value="all">Tất cả</option>
                    <option value="active">Chỉ key đang Active</option>
                    <option value="unused">Chỉ key chưa dùng</option>
                </select>
            </div>

            <div class="field">
                <button class="btn btn-pink btn-full" onclick="bulkExtend()">➕ Cộng ALL</button>
            </div>
        </div>

        <div class="danger-note">⚠️ Vùng nguy hiểm: hành động này áp dụng ngay lập tức cho tất cả key phù hợp với bộ lọc phía trên và không thể hoàn tác. Hãy kiểm tra bộ lọc kỹ trước khi bấm "Cộng ALL".</div>
    </div>

    <!-- QUẢN LÝ SELLER -->
    <div class="card">
        <div class="card-title">
            <h3>🧑‍💼 Quản Lý Tài Khoản Seller</h3>
            <button class="btn btn-gray" onclick="loadSellers()">🔄 Làm mới</button>
        </div>

        <div class="seller-grid">
            <input class="input" id="seller_username" placeholder="TÀI KHOẢN">
            <input class="input" id="seller_password" type="text" placeholder="MẬT KHẨU">
            <input class="input" id="seller_days" type="number" min="0" value="30" placeholder="THỜI HẠN (ngày, 0 = vĩnh viễn)">
            <button class="btn btn-primary" onclick="createSeller()">TẠO</button>
        </div>
        <div id="seller_create_msg" class="hint" style="margin-top:6px"></div>

        <div class="table-wrap" style="margin-top:13px">
            <table>
                <thead>
                    <tr>
                        <th>Tên Seller</th>
                        <th>UID</th>
                        <th>Thiết bị</th>
                        <th>Còn (hôm nay)</th>
                        <th>Trạng thái</th>
                        <th>Ngày hết hạn</th>
                        <th>Ngày tạo</th>
                        <th>Hành động</th>
                    </tr>
                </thead>
                <tbody id="sellers_body">
                    <tr><td colspan="8" class="loading">Đang tải dữ liệu...</td></tr>
                </tbody>
            </table>
        </div>
    </div>

    <!-- DANH SÁCH KEY -->
    <div class="card">
        <div class="card-title">
            <h3>📋 Danh Sách Key <span id="key_total" style="color:#777;font-size:11px">(0)</span></h3>
            <div class="actions">
                <button class="btn btn-gray" onclick="loadKeys()">🔄 Làm mới</button>
                <button class="btn btn-red" onclick="deleteAllKeys()">🗑️ Xoá all key</button>
            </div>
        </div>

        <div class="status-tabs">
            <button class="status-tab active" data-status="all" onclick="setStatus('all',this)">Tất cả</button>
            <button class="status-tab" data-status="active" onclick="setStatus('active',this)">Đang Active</button>
            <button class="status-tab" data-status="unused" onclick="setStatus('unused',this)">Chưa dùng</button>
            <button class="status-tab" data-status="expired" onclick="setStatus('expired',this)">Hết hạn</button>
            <button class="status-tab" data-status="banned" onclick="setStatus('banned',this)">Đã khoá</button>
        </div>

        <div class="filters">
            <input class="input" id="filter_q" placeholder="Tìm key / IP / thiết bị / seller" onkeydown="if(event.key==='Enter')loadKeys()">
            <select class="select" id="filter_type"><option value="all">-- Tất cả loại --</option></select>
            <select class="select" id="filter_seller"><option value="all">-- Tất cả người tạo --</option></select>
            <button class="btn btn-primary" onclick="loadKeys()">🔎 Lọc</button>
            <button class="btn btn-gray" onclick="resetFilters()">Xoá lọc</button>
        </div>

        <div class="table-wrap keys-scroll" style="margin-top:13px">
            <table>
                <thead>
                    <tr>
                        <th>Key</th><th>Loại</th><th>Thời hạn</th><th>Trạng thái</th>
                        <th>Thiết bị</th><th>Người tạo</th><th>Hết hạn</th><th>Hành động</th>
                    </tr>
                </thead>
                <tbody id="keys_body">
                    <tr><td colspan="8" class="loading">Đang tải dữ liệu...</td></tr>
                </tbody>
            </table>
        </div>
    </div>

    <div style="text-align:center;color:#555;font-size:10px;padding:10px">SHOP DHP · /admin</div>
</div>

<script>
let currentStatus = "all";
let keyCache = [];

async function api(url, options={}){
    const response = await fetch(url, Object.assign({credentials:"same-origin",headers:{"Content-Type":"application/json"}}, options));
    const contentType = response.headers.get("content-type") || "";
    if(!contentType.includes("application/json")){
        if(response.status === 401 || response.redirected){
            throw new Error("Phiên đăng nhập đã hết hạn, vui lòng đăng nhập lại.");
        }
        throw new Error("Phản hồi không hợp lệ từ máy chủ (mã "+response.status+")");
    }
    const payload = await response.json();
    if(response.status === 401){
        throw new Error(payload.error || "Phiên đăng nhập đã hết hạn, vui lòng đăng nhập lại.");
    }
    return payload;
}
async function post(url,data={}){ return api(url,{method:"POST",body:JSON.stringify(data)}); }

function copyOut(id){
    const output = document.getElementById(id);
    if(!output.value) return;
    navigator.clipboard.writeText(output.value).then(()=>alert("Đã sao chép key.")).catch(()=>{ output.select(); document.execCommand("copy"); });
}

/* ============== TẠO KEY: 4 khung riêng biệt ============== */
async function createRandomKeys(){
    const duration = document.getElementById("r_duration").value;
    const qty = Math.max(1, parseInt(document.getElementById("r_qty").value) || 1);
    const devices = Math.max(1, parseInt(document.getElementById("r_devices").value) || 1);
    const output = document.getElementById("out_random");
    output.value = "Đang tạo key...";
    try{
        const result = await post("/admin/api/keys/create_custom", { time_value: duration, qty, max_devices: devices, mode: "auto" });
        if(!result.ok){ output.value = result.error || "Không tạo được key"; return; }
        output.value = (result.keys || []).join("\n");
        document.getElementById("qty_random").textContent = result.count ?? (result.keys||[]).length;
        await loadKeys();
    } catch(error){ output.value = "Lỗi: "+error.message; }
}

async function createPrefixKeys(){
    const prefix = document.getElementById("p_prefix").value.trim();
    const duration = document.getElementById("p_duration").value;
    const qty = Math.max(1, parseInt(document.getElementById("p_qty").value) || 1);
    const devices = Math.max(1, parseInt(document.getElementById("p_devices").value) || 1);
    const output = document.getElementById("out_prefix");
    if(!prefix){ output.value = "Vui lòng nhập tiền tố key"; return; }
    output.value = "Đang tạo key...";
    try{
        const result = await post("/admin/api/keys/create_custom", { time_value: duration, qty, max_devices: devices, mode: "prefix", prefix });
        if(!result.ok){ output.value = result.error || "Không tạo được key"; return; }
        output.value = (result.keys || []).join("\n");
        document.getElementById("qty_prefix").textContent = result.count ?? (result.keys||[]).length;
        await loadKeys();
    } catch(error){ output.value = "Lỗi: "+error.message; }
}

async function createCustomKey(){
    const customKey = document.getElementById("c_key").value.trim();
    const duration = document.getElementById("c_duration").value;
    const devices = Math.max(1, parseInt(document.getElementById("c_devices").value) || 1);
    const output = document.getElementById("out_custom");
    if(!customKey){ output.value = "Vui lòng nhập key tuỳ chỉnh"; return; }
    output.value = "Đang tạo key...";
    try{
        const result = await post("/admin/api/keys/create_custom", { time_value: duration, qty: 1, max_devices: devices, mode: "custom", custom_key: customKey });
        if(!result.ok){ output.value = result.error || "Không tạo được key"; return; }
        output.value = (result.keys || []).join("\n");
        await loadKeys();
    } catch(error){ output.value = "Lỗi: "+error.message; }
}

async function createHourKeys(){
    const hours = parseFloat(document.getElementById("h_hours").value);
    const qty = Math.max(1, parseInt(document.getElementById("h_qty").value) || 1);
    const devices = Math.max(1, parseInt(document.getElementById("h_devices").value) || 1);
    const output = document.getElementById("out_hours");
    if(!hours || hours <= 0){ output.value = "Vui lòng nhập số giờ hợp lệ"; return; }
    output.value = "Đang tạo key...";
    try{
        const result = await post("/admin/api/keys/create_custom", { time_value: "custom_hours", custom_hours: hours, qty, max_devices: devices, mode: "auto" });
        if(!result.ok){ output.value = result.error || "Không tạo được key"; return; }
        output.value = (result.keys || []).join("\n");
        document.getElementById("qty_hours").textContent = result.count ?? (result.keys||[]).length;
        await loadKeys();
    } catch(error){ output.value = "Lỗi: "+error.message; }
}

/* ============== CỘNG THỜI GIAN CHO ALL KEY ============== */
async function bulkExtend(){
    const unit = document.getElementById("extend_unit").value;
    const multiplier = Math.max(1, parseInt(document.getElementById("extend_multiplier").value) || 1);
    const type = document.getElementById("extend_type").value;
    const currentDuration = document.getElementById("extend_current_duration").value;
    const activity = document.getElementById("extend_activity").value;

    const unitLabels = {"1h":"1 giờ","2h":"2 giờ","1d":"1 ngày","7d":"1 tuần","1m":"1 tháng","3m":"3 tháng","1y":"1 năm","permanent":"Vĩnh viễn"};
    const msg = unit === "permanent"
        ? `Chuyển TẤT CẢ key phù hợp bộ lọc thành Vĩnh viễn?`
        : `Cộng thêm ${multiplier} x ${unitLabels[unit]} cho tất cả key phù hợp bộ lọc?`;
    if(!confirm(msg)) return;

    try{
        const result = await post("/admin/api/keys/bulk_extend", {
            unit, multiplier, type, current_duration: currentDuration, activity
        });
        if(!result.ok){ alert(result.error || "Không thể cộng thời gian"); return; }
        alert(`Đã cộng thời gian cho ${result.updated}/${result.matched} key phù hợp bộ lọc.`);
        await loadKeys();
    } catch(error){ alert(error.message); }
}

/* ============== STATUS / FILTER ============== */
function setStatus(status,element){
    currentStatus = status;
    document.querySelectorAll(".status-tab").forEach(x=>x.classList.remove("active"));
    element.classList.add("active");
    loadKeys();
}

async function loadKeys(){
    const body = document.getElementById("keys_body");
    body.innerHTML = `<tr><td colspan="8" class="loading">Đang tải...</td></tr>`;
    try{
        const q = document.getElementById("filter_q").value.trim();
        const type = document.getElementById("filter_type").value;
        const seller = document.getElementById("filter_seller").value;
        const params = new URLSearchParams({ q, status: currentStatus, type, seller });
        const data = await api("/admin/api/keys/all?"+params.toString());
        if(!data.ok) throw new Error(data.error || "Không tải được key");
        keyCache = data.items || [];
        document.getElementById("key_total").textContent = "("+(data.total||0)+")";
        updateFilterOptions(data);
        renderKeys(data.items || []);
        updateStats(data.items || []);
    } catch(error){
        body.innerHTML = `<tr><td colspan="8" class="empty">❌ ${escapeHtml(error.message)}</td></tr>`;
        console.error(error);
    }
}

function updateFilterOptions(data){
    const type = document.getElementById("filter_type");
    if(type.options.length <= 1 && Array.isArray(data.types)){
        data.types.forEach(item=>{
            const option = document.createElement("option");
            option.value = item.code; option.textContent = item.name;
            type.appendChild(option);
        });
    }
    const seller = document.getElementById("filter_seller");
    if(seller.options.length <= 1 && Array.isArray(data.sellers)){
        data.sellers.forEach(name=>{
            const option = document.createElement("option");
            option.value = name; option.textContent = name;
            seller.appendChild(option);
        });
    }
}

function renderKeys(items){
    const body = document.getElementById("keys_body");
    if(!items.length){ body.innerHTML = `<tr><td colspan="8" class="empty">Không có key phù hợp.</td></tr>`; return; }

    body.innerHTML = items.map(item=>{
        const statusClass = {active:"active",unused:"unused",expired:"expired",banned:"banned"}[item.status] || "banned";
        const statusText = {active:"Đang Active",unused:"Chưa dùng",expired:"Hết hạn",banned:"Đã khoá"}[item.status] || item.status;
        const deviceList = (item.devices && item.devices.length) ? item.devices.join(" | ") : "-";
        const deviceCount = item.device_count || 0;
        const maxDev = item.max_devices || 1;
        const banNote = item.banned ? `<span class="ban-note">${escapeHtml(item.ban_reason || "Key đã bị admin khoá do vi phạm quy định.")}</span>` : "";

        return `
            <tr>
                <td><div class="key">${escapeHtml(item.key)}</div></td>
                <td>${escapeHtml(item.type_name || "-")}</td>
                <td>${escapeHtml(item.duration_label || "-")}</td>
                <td><span class="badge ${statusClass}">${escapeHtml(statusText)}</span>${banNote}</td>
                <td><div class="device" title="${escapeHtml(deviceList)}">${escapeHtml(deviceList)}</div><span class="device-count">${deviceCount}/${maxDev}</span></td>
                <td>${escapeHtml(item.created_by || "-")}</td>
                <td>${escapeHtml(item.expires || "-")}</td>
                <td>
                    <div class="actions">
                        ${item.banned
                            ? `<button class="btn btn-green" onclick="unbanKey('${escapeJs(item.key)}')">Mở khoá</button>`
                            : `<button class="btn btn-red" onclick="banKey('${escapeJs(item.key)}')">Khoá</button>`}
                        ${item.locked
                            ? `<button class="btn btn-green" onclick="unlockKey('${escapeJs(item.key)}')">Mở khoá thường</button>`
                            : `<button class="btn btn-gray" onclick="lockKey('${escapeJs(item.key)}')">Khoá thường</button>`}
                        <button class="btn btn-blue" onclick="resetKey('${escapeJs(item.key)}')">↺ Reset</button>
                        <button class="btn btn-red" onclick="deleteKey('${escapeJs(item.key)}')">Xoá</button>
                    </div>
                </td>
            </tr>`;
    }).join("");
}

async function banKey(key){
    if(!confirm("Khoá key này?")) return;
    try{
        const result = await post("/admin/api/keys/ban", { keys:[key], reason:"Key đã bị admin khoá do vi phạm quy định." });
        if(!result.ok){ alert(result.error || "Không thể khoá key"); return; }
        await loadKeys();
    } catch(error){ alert(error.message); }
}
async function unbanKey(key){
    try{
        const result = await post("/admin/api/keys/unban", { keys:[key] });
        if(!result.ok){ alert(result.error || "Không thể mở khoá"); return; }
        await loadKeys();
    } catch(error){ alert(error.message); }
}
async function lockKey(key){
    if(!confirm("Khoá key này?")) return;
    try{
        const result = await post("/admin/api/keys/lock", { key });
        if(!result.ok){ alert(result.error || "Không thể khoá"); return; }
        await loadKeys();
    } catch(error){ alert(error.message); }
}
async function unlockKey(key){
    try{
        const result = await post("/admin/api/keys/unlock", { key });
        if(!result.ok){ alert(result.error || "Không thể mở khoá"); return; }
        await loadKeys();
    } catch(error){ alert(error.message); }
}
async function resetKey(key){
    if(!confirm("Reset key này về trạng thái CHƯA DÙNG? (gỡ thiết bị đã gắn)")) return;
    try{
        const result = await post("/admin/api/keys/reset", { key });
        if(!result.ok){ alert(result.error || "Không thể reset key"); return; }
        await loadKeys();
    } catch(error){ alert(error.message); }
}
async function deleteKey(key){
    if(!confirm("Xoá vĩnh viễn key này khỏi hệ thống?")) return;
    try{
        const result = await post("/admin/api/keys/delete", { key });
        if(!result.ok){ alert(result.error || "Không thể xoá key"); return; }
        await loadKeys();
    } catch(error){ alert(error.message); }
}
async function deleteAllKeys(){
    if(!confirm("⚠️ XOÁ TOÀN BỘ KEY trong hệ thống? Hành động này không thể hoàn tác!")) return;
    if(!confirm("Xác nhận lần 2: bạn chắc chắn muốn xoá TẤT CẢ key?")) return;
    try{
        const result = await post("/admin/api/keys/delete_all", {});
        if(!result.ok){ alert(result.error || "Không thể xoá"); return; }
        await loadKeys();
    } catch(error){ alert(error.message); }
}

function resetFilters(){
    document.getElementById("filter_q").value = "";
    document.getElementById("filter_type").value = "all";
    document.getElementById("filter_seller").value = "all";
    currentStatus = "all";
    document.querySelectorAll(".status-tab").forEach(x=>x.classList.remove("active"));
    const first = document.querySelector(".status-tab[data-status='all']");
    if(first) first.classList.add("active");
    loadKeys();
}

function updateStats(items){
    const total = items.length;
    const active = items.filter(x=>x.status==="active").length;
    const unused = items.filter(x=>x.status==="unused").length;
    const locked = items.filter(x=>x.status==="expired"||x.status==="banned").length;
    document.getElementById("st_keys").textContent = total;
    document.getElementById("st_active").textContent = active;
    document.getElementById("st_unused").textContent = unused;
    document.getElementById("st_locked").textContent = locked;
}

async function loadStats(){
    try{
        const data = await api("/admin/api/stats/overview");
        if(!data.ok) return;
        document.getElementById("st_keys").textContent = data.total_keys || 0;
        document.getElementById("st_users").textContent = (data.today||{}).total || 0;
    } catch(error){ console.error(error); }
}

/* ============== SELLER MANAGEMENT ============== */
async function loadSellers(){
    const body = document.getElementById("sellers_body");
    body.innerHTML = `<tr><td colspan="8" class="loading">Đang tải...</td></tr>`;
    try{
        const data = await api("/admin/api/sellers/all");
        if(!data.ok) throw new Error(data.error || "Không tải được seller");
        document.getElementById("st_sellers").textContent = data.total || 0;
        renderSellers(data.items || []);
    } catch(error){
        body.innerHTML = `<tr><td colspan="8" class="empty">❌ ${escapeHtml(error.message)}</td></tr>`;
    }
}

function renderSellers(items){
    const body = document.getElementById("sellers_body");
    if(!items.length){ body.innerHTML = `<tr><td colspan="8" class="empty">Chưa có seller nào.</td></tr>`; return; }

    body.innerHTML = items.map(s=>{
        let statusHtml;
        if(s.banned) statusHtml = `<span class="badge banned">Đã khoá</span>`;
        else if(s.expired) statusHtml = `<span class="badge expired">Hết hạn</span>`;
        else statusHtml = `<span class="badge active">Hoạt động</span>`;

        return `
            <tr>
                <td>${escapeHtml(s.username)}</td>
                <td>#${s.id}</td>
                <td>${s.device_count}</td>
                <td>${s.remaining}/${s.quota}</td>
                <td>${statusHtml}</td>
                <td>${escapeHtml(s.expires_at)}</td>
                <td>${escapeHtml(s.created_at)}</td>
                <td>
                    <div class="actions">
                        ${s.banned
                            ? `<button class="btn btn-green" onclick="toggleBanSeller('${escapeJs(s.username)}',false)">Mở khoá</button>`
                            : `<button class="btn btn-red" onclick="toggleBanSeller('${escapeJs(s.username)}',true)">Khoá TK</button>`}
                        <button class="btn btn-red" onclick="banAllSellerKeys('${escapeJs(s.username)}')">Khoá all key</button>
                        <button class="btn btn-gray" onclick="deleteSeller('${escapeJs(s.username)}')">Xoá seller</button>
                    </div>
                </td>
            </tr>`;
    }).join("");
}

async function createSeller(){
    const username = document.getElementById("seller_username").value.trim();
    const password = document.getElementById("seller_password").value.trim();
    const days = parseInt(document.getElementById("seller_days").value);
    const msg = document.getElementById("seller_create_msg");
    msg.textContent = "";
    if(!username || !password){ msg.textContent = "⚠️ Vui lòng nhập tài khoản và mật khẩu"; return; }
    try{
        const result = await post("/admin/api/sellers/create", { username, password, days: isNaN(days)?30:days });
        if(!result.ok){ msg.textContent = "❌ "+(result.error || "Không tạo được seller"); return; }
        document.getElementById("seller_username").value = "";
        document.getElementById("seller_password").value = "";
        msg.textContent = "✅ Đã tạo tài khoản seller: "+username;
        await loadSellers();
    } catch(error){ msg.textContent = "❌ "+error.message; }
}

async function toggleBanSeller(username, banned){
    if(!confirm(banned ? "Khoá tài khoản seller này?" : "Mở khoá tài khoản seller này?")) return;
    try{
        const result = await post("/admin/api/sellers/toggle_ban", { username, banned });
        if(!result.ok){ alert(result.error || "Thất bại"); return; }
        await loadSellers();
    } catch(error){ alert(error.message); }
}

async function banAllSellerKeys(username){
    if(!confirm(`Khoá TOÀN BỘ key do seller "${username}" tạo?`)) return;
    try{
        const result = await post("/admin/api/sellers/ban_keys", { username });
        if(!result.ok){ alert(result.error || "Thất bại"); return; }
        await loadKeys();
        alert("Đã khoá toàn bộ key của seller "+username);
    } catch(error){ alert(error.message); }
}

async function deleteSeller(username){
    if(!confirm(`Xoá tài khoản seller "${username}"? (Key đã tạo trước đó vẫn giữ nguyên)`)) return;
    try{
        const result = await post("/admin/api/sellers/delete", { username });
        if(!result.ok){ alert(result.error || "Thất bại"); return; }
        await loadSellers();
    } catch(error){ alert(error.message); }
}

function escapeHtml(value){
    return String(value ?? "").replace(/[&<>"']/g, c=>({"&":"&amp;","<":"&lt;",">":"&gt;",'"':"&quot;","'":"&#39;"}[c]));
}
function escapeJs(value){ return String(value ?? "").replace(/\\/g,"\\\\").replace(/'/g,"\\'"); }

async function loadAll(){ await Promise.all([loadStats(), loadSellers(), loadKeys()]); }
loadAll();
setInterval(loadAll, 30000);
</script>
</body>
</html>
"""


# ============================================================
# SELLER DASHBOARD
# ============================================================

SELLER_DASHBOARD_HTML = r"""
<!doctype html>
<html lang="vi">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1,maximum-scale=1,user-scalable=no">
<title>SHOP DHP · Seller Dashboard</title>
<style>
:root{--bg:#050509;--line:#30264f;--text:#f5f5f7;--muted:#8e8da1;--purple:#8b5cf6;--blue:#3b82f6}
*{box-sizing:border-box}
html,body{margin:0;padding:0;min-height:100%;
    background:radial-gradient(circle at 15% 0%,rgba(124,92,255,.13),transparent 32%),
               radial-gradient(circle at 90% 10%,rgba(236,72,153,.09),transparent 28%),var(--bg);
    color:var(--text);font-family:-apple-system,BlinkMacSystemFont,"Segoe UI",Roboto,Arial,sans-serif}
button,input,select{font:inherit}
button{cursor:pointer}
.wrap{width:min(1200px,96vw);margin:auto;padding:22px 0 50px}
.header{display:flex;align-items:center;justify-content:space-between;gap:15px;margin-bottom:18px;flex-wrap:wrap}
.brand{font-size:23px;font-weight:900;font-style:italic;letter-spacing:1px;
    background:linear-gradient(90deg,#a78bfa,#60a5fa,#ec4899);-webkit-background-clip:text;background-clip:text;color:transparent}
.logout{border:0;border-radius:9px;padding:9px 15px;color:white;font-size:12px;font-weight:800;background:linear-gradient(90deg,#ef4444,#f97316)}
.card{background:linear-gradient(145deg,rgba(255,255,255,.035),rgba(255,255,255,.012));
    border:1px solid rgba(139,92,246,.40);border-radius:17px;padding:16px;margin-bottom:15px;box-shadow:0 18px 50px rgba(0,0,0,.25)}
.card-title{display:flex;align-items:center;justify-content:space-between;gap:10px;margin-bottom:13px;flex-wrap:wrap}
.card-title h3{margin:0;font-size:15px;font-weight:900}
.stats{display:grid;grid-template-columns:repeat(auto-fit,minmax(150px,1fr));gap:9px}
.stat{min-height:74px;padding:12px;border-radius:13px;background:#08080d;border:1px solid var(--line);display:flex;flex-direction:column;justify-content:center}
.stat .label{color:var(--muted);font-size:9px;font-weight:800;letter-spacing:1.4px;text-transform:uppercase}
.stat .value{margin-top:3px;font-size:21px;line-height:1;font-weight:900}
.stat .sub{margin-top:5px;color:#777687;font-size:10px}
.stat.blue{border-color:rgba(59,130,246,.65)} .stat.purple{border-color:rgba(139,92,246,.65)}
.stat.green{border-color:rgba(34,197,94,.65)} .stat.yellow{border-color:rgba(245,158,11,.65)}
.field{display:flex;flex-direction:column;gap:5px;min-width:0}
.field label{font-size:10px;font-weight:800;color:var(--muted);text-transform:uppercase;letter-spacing:.6px}
.create-grid{display:grid;grid-template-columns:repeat(auto-fit,minmax(150px,1fr));gap:10px;align-items:end}
.input,.select{width:100%;min-height:39px;border-radius:9px;border:1px solid #332957;background:#111117;color:#eee;padding:9px 11px;outline:none}
.input:focus,.select:focus{border-color:var(--purple);box-shadow:0 0 0 2px rgba(139,92,246,.12)}
.btn{min-height:39px;border:0;border-radius:9px;padding:8px 13px;color:#fff;font-weight:800;font-size:12px}
.btn-primary{background:linear-gradient(90deg,#8b5cf6,#3b82f6)}
.btn-blue{background:linear-gradient(90deg,#2563eb,#0ea5e9)}
.btn-gray{background:#24242d;border:1px solid #3b3946}
.btn:hover{filter:brightness(1.12)}
.btn-full{width:100%}
.output{width:100%;min-height:80px;margin-top:10px;resize:vertical;border-radius:10px;border:1px solid #332957;background:#0d0d12;color:#d7d4ff;padding:11px;font-family:ui-monospace,SFMono-Regular,Menlo,monospace}
.qty-display{margin-top:10px;padding:12px 14px;border-radius:12px;background:rgba(139,92,246,.10);border:1px solid rgba(139,92,246,.4);display:flex;align-items:center;justify-content:space-between;gap:10px;flex-wrap:wrap}
.qty-display .qlabel{font-size:11px;color:var(--muted);font-weight:800;text-transform:uppercase;letter-spacing:.6px}
.qty-display .qvalue{font-size:24px;font-weight:900;color:#fff}
.hint{color:#777687;font-size:11px;margin-top:8px;line-height:1.5}
.filters{display:grid;grid-template-columns:repeat(auto-fit,minmax(150px,1fr));gap:8px}
.status-tabs{display:flex;gap:7px;flex-wrap:wrap;margin-bottom:12px}
.status-tab{border:1px solid #30264f;background:#0b0b10;color:#a9a6b8;border-radius:8px;padding:8px 12px;font-size:11px;font-weight:800}
.status-tab.active{color:#fff;border-color:#8b5cf6;background:linear-gradient(90deg,rgba(139,92,246,.28),rgba(59,130,246,.18))}
.table-wrap{overflow:auto;border-radius:11px;border:1px solid rgba(255,255,255,.06)}
.table-wrap.keys-scroll{max-height:640px;overflow-y:auto}
.table-wrap.keys-scroll thead th{position:sticky;top:0;background:#09090e;z-index:2;box-shadow:0 1px 0 rgba(255,255,255,.06)}
table{width:100%;min-width:900px;border-collapse:collapse}
thead{background:#09090e}
th{padding:11px 10px;color:#77758a;font-size:9px;font-weight:900;text-transform:uppercase;letter-spacing:1px;text-align:left;white-space:nowrap}
td{padding:11px 10px;border-top:1px solid rgba(255,255,255,.055);font-size:11px;vertical-align:middle}
tbody tr:hover{background:rgba(139,92,246,.045)}
.key{color:#fff;font-family:ui-monospace,SFMono-Regular,Menlo,monospace;font-weight:900}
.device{max-width:190px;color:#aaa8b8;overflow:hidden;text-overflow:ellipsis;white-space:nowrap}
.device-count{display:inline-block;margin-left:6px;font-size:9px;color:#c4b5fd;background:rgba(139,92,246,.14);border:1px solid rgba(139,92,246,.35);border-radius:6px;padding:1px 5px}
.actions{display:flex;gap:5px;flex-wrap:wrap}
.badge{display:inline-flex;align-items:center;border-radius:6px;padding:4px 7px;font-size:9px;font-weight:900;white-space:nowrap}
.badge.active{color:#86efac;background:rgba(34,197,94,.12);border:1px solid rgba(34,197,94,.35)}
.badge.unused{color:#93c5fd;background:rgba(59,130,246,.12);border:1px solid rgba(59,130,246,.35)}
.badge.expired{color:#fcd34d;background:rgba(245,158,11,.12);border:1px solid rgba(245,158,11,.35)}
.badge.banned{color:#fca5a5;background:rgba(239,68,68,.12);border:1px solid rgba(239,68,68,.35)}
.ban-note{display:block;margin-top:4px;font-size:9px;color:#fca5a5;max-width:170px}
.empty{padding:30px;text-align:center;color:#777687}
.loading{padding:30px;text-align:center;color:#8b5cf6}
@media(max-width:800px){
    .wrap{width:94vw;padding-top:14px}
    .create-grid,.filters{grid-template-columns:1fr}
    .stats{grid-template-columns:repeat(2,minmax(0,1fr))}
}
</style>
</head>
<body>
<div class="wrap">

    <div class="header">
        <div class="brand">SELLER DASHBOARD</div>
        <button class="logout" onclick="location.href='/serveripa/logout'">Đăng xuất</button>
    </div>

    <div class="card">
        <div class="card-title">
            <h3>📊 Hạn mức của bạn</h3>
            <button class="btn btn-gray" onclick="loadAll()">🔄 Làm mới</button>
        </div>
        <div class="stats">
            <div class="stat purple"><div class="label">Tổng key đã tạo</div><div class="value" id="s_total_keys">0</div><div class="sub">Từ trước tới nay</div></div>
            <div class="stat blue"><div class="label">Đã tạo hôm nay</div><div class="value" id="s_created_today">0</div><div class="sub">/ <span id="s_quota">500</span> key mỗi ngày</div></div>
            <div class="stat green"><div class="label">Còn lại hôm nay</div><div class="value" id="s_remaining">0</div><div class="sub">Số key có thể tạo tiếp</div></div>
            <div class="stat yellow"><div class="label">Tài khoản hết hạn</div><div class="value" id="s_expires" style="font-size:13px">-</div><div class="sub">Ngày hết hạn tài khoản seller</div></div>
        </div>
    </div>

    <div class="card">
        <div class="card-title"><h3>✨ Tạo Key</h3></div>
        <div class="create-grid">
            <div class="field">
                <label>Thời hạn key</label>
                <select class="select" id="s_duration">
                    <option value="2h">2 Giờ</option>
                    <option value="1d">1 Ngày</option>
                    <option value="7d">1 Tuần</option>
                    <option value="1m">1 Tháng</option>
                </select>
            </div>
            <div class="field">
                <label>Số lượng key</label>
                <input class="input" id="s_qty" type="number" min="1" max="10" value="1" placeholder="VD: 10">
            </div>
            <div class="field">
                <button class="btn btn-primary btn-full" onclick="createKeys()">🔑 Tạo Key</button>
            </div>
        </div>
        <div class="hint">Mỗi lần tạo tối đa 10 key. Tổng cộng tối đa 500 key/ngày.</div>

        <textarea id="created_keys" class="output" readonly placeholder="Key vừa tạo sẽ hiển thị ở đây..."></textarea>
        <div id="created_key_info" class="created-key-info" style="display:none"></div>
        <div class="qty-display">
            <span class="qlabel">Số lượng key vừa tạo</span>
            <span class="qvalue" id="created_qty_value">0</span>
        </div>
        <div style="margin-top:8px"><button class="btn btn-gray" onclick="copyCreatedKeys()">📋 Sao chép</button></div>
    </div>

    <div class="card">
        <div class="card-title">
            <h3>📋 Key Của Bạn <span id="key_total" style="color:#777;font-size:11px">(0)</span></h3>
            <button class="btn btn-gray" onclick="loadKeys()">🔄 Làm mới</button>
        </div>

        <div class="status-tabs">
            <button class="status-tab active" data-status="all" onclick="setStatus('all',this)">Tất cả</button>
            <button class="status-tab" data-status="active" onclick="setStatus('active',this)">Đang Active</button>
            <button class="status-tab" data-status="unused" onclick="setStatus('unused',this)">Chưa dùng</button>
            <button class="status-tab" data-status="expired" onclick="setStatus('expired',this)">Hết hạn</button>
            <button class="status-tab" data-status="banned" onclick="setStatus('banned',this)">Đã khoá</button>
        </div>

        <div class="filters">
            <input class="input" id="filter_q" placeholder="Tìm key / thiết bị" onkeydown="if(event.key==='Enter')loadKeys()">
            <button class="btn btn-primary" onclick="loadKeys()">🔎 Lọc</button>
            <button class="btn btn-gray" onclick="resetFilters()">Xoá lọc</button>
        </div>

        <div class="table-wrap keys-scroll" style="margin-top:13px">
            <table>
                <thead>
                    <tr><th>Key</th><th>Loại</th><th>Thời hạn</th><th>Trạng thái</th><th>Thiết bị</th><th>Người tạo</th><th>Hết hạn</th><th>Hành động</th></tr>
                </thead>
                <tbody id="keys_body"><tr><td colspan="8" class="loading">Đang tải dữ liệu...</td></tr></tbody>
            </table>
        </div>
    </div>

    <div style="text-align:center;color:#555;font-size:10px;padding:10px">SHOP DHP · /serveripa</div>
</div>

<script>
let currentStatus = "all";

async function api(url, options={}){
    const response = await fetch(url, Object.assign({credentials:"same-origin",headers:{"Content-Type":"application/json"}}, options));
    const contentType = response.headers.get("content-type") || "";
    if(!contentType.includes("application/json")){ throw new Error("Phiên đăng nhập đã hết hạn"); }
    return await response.json();
}
async function post(url,data={}){ return api(url,{method:"POST",body:JSON.stringify(data)}); }

async function createKeys(){
    const duration = document.getElementById("s_duration").value;
    let qty = Math.max(1, parseInt(document.getElementById("s_qty").value) || 1);
    if(qty > 10) qty = 10;
    const output = document.getElementById("created_keys");
    output.value = "Đang tạo key...";
    try{
        const result = await post("/seller/api/keys/create", { time_value: duration, qty });
        if(!result.ok){ output.value = result.error || "Không tạo được key"; return; }
        const items = result.items || (result.keys || []).map(key => ({key, duration_label: duration, expires_at: "-", status: "unused"}));
        output.value = items.map(item => item.key).join("\n");
        document.getElementById("created_qty_value").textContent = result.count ?? items.length;
        renderCreatedKeyInfo(items);
        await loadAll();
    } catch(error){ output.value = "Lỗi: "+error.message; }
}

function renderCreatedKeyInfo(items){
    const box = document.getElementById("created_key_info");
    if(!box) return;
    if(!items.length){ box.innerHTML = ""; box.style.display = "none"; return; }
    box.style.display = "grid";
    box.innerHTML = items.map(item => `
        <div class="created-key-row">
            <div>
                <div class="created-key-value">${escapeHtml(item.key)}</div>
                <div class="created-key-meta">${escapeHtml(item.duration_label || "-")} · Hết hạn: ${escapeHtml(item.expires_at || "Vĩnh viễn")}</div>
            </div>
            <span class="badge unused">Chưa dùng</span>
        </div>`).join("");
}

function copyCreatedKeys(){
    const output = document.getElementById("created_keys");
    if(!output.value) return;
    navigator.clipboard.writeText(output.value).then(()=>alert("Đã sao chép key.")).catch(()=>{ output.select(); document.execCommand("copy"); });
}

function setStatus(status,element){
    currentStatus = status;
    document.querySelectorAll(".status-tab").forEach(x=>x.classList.remove("active"));
    element.classList.add("active");
    loadKeys();
}

async function loadKeys(){
    const body = document.getElementById("keys_body");
    body.innerHTML = `<tr><td colspan="8" class="loading">Đang tải...</td></tr>`;
    try{
        const q = document.getElementById("filter_q").value.trim();
        const params = new URLSearchParams({ q, status: currentStatus });
        const data = await api("/seller/api/keys/mine?"+params.toString());
        if(!data.ok) throw new Error(data.error || "Không tải được key");
        document.getElementById("key_total").textContent = "("+(data.total||0)+")";
        renderKeys(data.items || []);
    } catch(error){
        body.innerHTML = `<tr><td colspan="8" class="empty">❌ ${escapeHtml(error.message)}</td></tr>`;
    }
}

function renderKeys(items){
    const body = document.getElementById("keys_body");
    if(!items.length){ body.innerHTML = `<tr><td colspan="8" class="empty">Bạn chưa có key nào.</td></tr>`; return; }

    body.innerHTML = items.map(item=>{
        const statusClass = {active:"active",unused:"unused",expired:"expired",banned:"banned"}[item.status] || "banned";
        const statusText = {active:"Đang Active",unused:"Chưa dùng",expired:"Hết hạn",banned:"Đã khoá"}[item.status] || item.status;
        const deviceList = (item.devices && item.devices.length) ? item.devices.join(" | ") : "-";
        const deviceCount = item.device_count || 0;
        const maxDev = item.max_devices || 1;
        const banNote = item.banned ? `<span class="ban-note">${escapeHtml(item.ban_reason || "Key đã bị admin khoá do vi phạm quy định.")}</span>` : "";
        const resetBtn = item.banned
            ? `<button class="btn btn-gray" disabled title="Key đã bị admin khoá, liên hệ admin để mở">Reset</button>`
            : `<button class="btn btn-blue" onclick="resetKey('${escapeJs(item.key)}')">↺ Reset</button>`;

        return `
            <tr>
                <td><div class="key">${escapeHtml(item.key)}</div></td>
                <td>${escapeHtml(item.type_name || "-")}</td>
                <td>${escapeHtml(item.duration_label || "-")}</td>
                <td><span class="badge ${statusClass}">${escapeHtml(statusText)}</span>${banNote}</td>
                <td><div class="device" title="${escapeHtml(deviceList)}">${escapeHtml(deviceList)}</div><span class="device-count">${deviceCount}/${maxDev}</span></td>
                <td>${escapeHtml(item.created_by || "-")}</td>
                <td>${escapeHtml(item.expires || "-")}</td>
                <td><div class="actions">${resetBtn}</div></td>
            </tr>`;
    }).join("");
}

async function resetKey(key){
    if(!confirm("Reset key này về trạng thái CHƯA DÙNG? (gỡ thiết bị đã gắn)")) return;
    try{
        const result = await post("/seller/api/keys/reset", { key });
        if(!result.ok){ alert(result.error || "Không thể reset key"); return; }
        await loadKeys();
    } catch(error){ alert(error.message); }
}

function resetFilters(){
    document.getElementById("filter_q").value = "";
    currentStatus = "all";
    document.querySelectorAll(".status-tab").forEach(x=>x.classList.remove("active"));
    const first = document.querySelector(".status-tab[data-status='all']");
    if(first) first.classList.add("active");
    loadKeys();
}

async function loadStats(){
    try{
        const data = await api("/seller/api/stats");
        if(!data.ok) return;
        document.getElementById("s_total_keys").textContent = data.total_keys || 0;
        document.getElementById("s_created_today").textContent = data.created_today || 0;
        document.getElementById("s_quota").textContent = data.quota || 500;
        document.getElementById("s_remaining").textContent = data.remaining || 0;
        document.getElementById("s_expires").textContent = data.expires_at || "-";
    } catch(error){ console.error(error); }
}

function escapeHtml(value){
    return String(value ?? "").replace(/[&<>"']/g, c=>({"&":"&amp;","<":"&lt;",">":"&gt;",'"':"&quot;","'":"&#39;"}[c]));
}
function escapeJs(value){ return String(value ?? "").replace(/\\/g,"\\\\").replace(/'/g,"\\'"); }

async function loadAll(){ await Promise.all([loadStats(), loadKeys()]); }
loadAll();
setInterval(loadAll, 30000);
</script>
</body>
</html>
"""


@app.route("/admin")
@admin_required
def admin_root():
    return Response(ADMIN_DASHBOARD_HTML, mimetype="text/html")


@app.route("/admin/manage")
@admin_required
def admin_manage_page():
    return redirect(url_for("admin_root"))


@app.route("/serveripa")
@seller_required
def seller_root():
    return Response(SELLER_DASHBOARD_HTML, mimetype="text/html")


@app.route("/health")
def health():
    return jsonify(ok=True, service="SHOPDHP Key Panel", port=PORT)


if __name__ == "__main__":
    init_db()
    print("=" * 60)
    print("SHOP DHP KEY PANEL")
    print(f"Admin      : http://127.0.0.1:{PORT}/admin")
    print(f"Admin login: http://127.0.0.1:{PORT}/admin/login")
    print(f"Seller     : http://127.0.0.1:{PORT}/serveripa")
    print(f"Seller login: http://127.0.0.1:{PORT}/serveripa/login")
    print(f"Database   : {DB_PATH}")
    print("=" * 60)
    app.run(host=HOST, port=PORT, debug=False, threaded=True)