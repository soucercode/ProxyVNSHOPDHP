# SHOP DHP License Server - VPS

Địa chỉ API test của VPS:
http://103.161.16.212:5050

## 1. Cài đặt Ubuntu VPS

```bash
sudo apt update
sudo apt install -y python3 python3-venv python3-pip
```

## 2. Tạo thư mục

```bash
mkdir -p ~/shopdhp
cd ~/shopdhp
```

Chép `server.py` vào thư mục này.

## 3. Tạo virtual environment

```bash
python3 -m venv .venv
source .venv/bin/activate
pip install --upgrade pip
pip install Flask Werkzeug
```

## 4. Cấu hình

Không đưa mật khẩu Admin vào IPA.

Tạo biến môi trường trong shell:

```bash
export SHOPDHP_HOST=0.0.0.0
export SHOPDHP_PORT=5050
export SHOPDHP_ADMIN_USER='YOUR_ADMIN_USER'
export SHOPDHP_ADMIN_PASS='YOUR_ADMIN_PASSWORD'
```

## 5. Mở port

Nếu VPS sử dụng UFW:

```bash
sudo ufw allow 5050/tcp
sudo ufw reload
```

Đồng thời mở TCP 5050 ở firewall/security group của nhà cung cấp VPS.

## 6. Chạy test

```bash
cd ~/shopdhp
source .venv/bin/activate
python server.py
```

Kiểm tra:

```bash
curl http://127.0.0.1:5050/health
```

Từ iPhone/PC bên ngoài:

```text
http://103.161.16.212:5050/health
```

## 7. Trang quản trị

```text
http://103.161.16.212:5050/admin
```

Seller:

```text
http://103.161.16.212:5050/serveripa/login
```

API activation:

```text
http://103.161.16.212:5050/api/keys/activate
```

API verify:

```text
http://103.161.16.212:5050/api/keys/verify
```

## 8. Chạy nền trên VPS bằng systemd

Tạo:

```bash
sudo nano /etc/systemd/system/shopdhp.service
```

Nội dung:

```ini
[Unit]
Description=SHOP DHP License Server
After=network.target

[Service]
Type=simple
User=root
WorkingDirectory=/root/shopdhp
Environment="SHOPDHP_HOST=0.0.0.0"
Environment="SHOPDHP_PORT=5050"
Environment="SHOPDHP_ADMIN_USER=YOUR_ADMIN_USER"
Environment="SHOPDHP_ADMIN_PASS=YOUR_ADMIN_PASSWORD"
ExecStart=/root/shopdhp/.venv/bin/python /root/shopdhp/server.py
Restart=always
RestartSec=3

[Install]
WantedBy=multi-user.target
```

Sau đó:

```bash
sudo systemctl daemon-reload
sudo systemctl enable --now shopdhp
sudo systemctl status shopdhp
```

Xem log:

```bash
journalctl -u shopdhp -f
```

## 9. App iOS

`ThreeOneOSFive/Info.plist` đã được cấu hình:

```xml
<key>LicenseServerURL</key>
<string>http://103.161.16.212:5050</string>
```

App gọi:

```text
POST /api/keys/activate
POST /api/keys/verify
GET  /health
```

Client gửi:

```json
{
  "key": "DHP-IPA-XXXXXX",
  "udid": "DEVICE_ID",
  "device_name": "iPhone ..."
}
```

Lưu ý: client đang dùng `identifierForVendor` làm Device ID riêng theo app/vendor, không phải UDID hệ thống của Apple.

Khi server trả:

```text
Key không tồn tại
```

app hiển thị:

```text
⚠️ Key không tồn tại
```

Khi key đã bị bind sang thiết bị khác và giới hạn là 1:

```text
Key đã sử dụng cho thiết bị khác
```

Thông báo tự biến mất sau khoảng 4 giây.

## 10. Bản cập nhật V21

- Giao diện iPhone được hạ phần nội dung đầu màn hình khoảng 1 cm để không bị tai thỏ che.
- Toast/thông báo cũng được hạ xuống vùng an toàn.
- Màn hình Home hạ card chức năng xuống đồng bộ.
- License vẫn dùng bàn phím hệ thống iOS, không có bàn phím custom trong app.
- Seller Dashboard sau khi tạo key trả về thêm `items` gồm key, thời hạn, ngày hết hạn và trạng thái để hiển thị ngay thông tin key vừa tạo.

Sau khi thay `server.py` trên VPS, restart:

```bash
sudo systemctl daemon-reload
sudo systemctl restart shopdhp
sudo systemctl status shopdhp --no-pager
curl http://127.0.0.1:5050/health
```
