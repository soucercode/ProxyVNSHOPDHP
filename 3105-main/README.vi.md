<p align="center">
  <img src="docs/images/app-icon.png" width="132" alt="Biểu tượng ứng dụng Proxy SHOP DHP">
</p>

<h1 align="center">3105</h1>

<p align="center">
  Trình quản lý dữ liệu ứng dụng, patch theo bundle, dọn dẹp giới hạn và hình nền PosterBoard dành cho iOS.
</p>

<p align="center">
  <img alt="Phiên bản" src="https://img.shields.io/badge/phiên%20bản-1.0%20beta%203-E6753A?style=flat-square">
  <img alt="iOS" src="https://img.shields.io/badge/iOS-26.0–26.6.1%20%7C%2027%20beta%201–4-222222?style=flat-square">
  <img alt="Ngôn ngữ" src="https://img.shields.io/badge/ngôn%20ngữ-English%20%7C%20Tiếng%20Việt%20%7C%20简体中文-E6753A?style=flat-square">
</p>

<p align="center"><a href="README.md">English</a> · <a href="#giấy-phép">Giấy phép</a></p>

> [!WARNING]
> 3105 đang ở giai đoạn beta. Chỉ sử dụng trên thiết bị và dữ liệu thuộc quyền sở hữu của bạn, đồng thời luôn sao lưu trước khi thay đổi tệp hệ thống hoặc dữ liệu ứng dụng.

## Giao diện

<p align="center">
  <img src="docs/images/home.png" width="245" alt="Trang chủ 3105">
  &nbsp;
  <img src="docs/images/patches.png" width="245" alt="Patch 3105">
  &nbsp;
  <img src="docs/images/cleaner.png" width="245" alt="Dọn dẹp 3105">
</p>

## Tính năng chính

- Duyệt dữ liệu ứng dụng theo **bundle identifier**, không phụ thuộc UUID container của từng máy.
- Trình quản lý tệp có tìm kiếm, nhập nhiều tệp, đổi tên, xóa, tạo tệp/thư mục và xử lý trùng tên.
- Tạo và nhập dự án patch `.3105`, hỗ trợ nhiều quy tắc, tệp/thư mục và mật khẩu tùy chọn.
- Dọn dẹp giới hạn trong `Library/Caches` và `tmp`, luôn hiển thị cảnh báo trước khi xóa.
- Nhập gói hình nền `.tendies`, xác thực payload và chỉ reset nội dung do 3105 cài đặt.
- 3105 không cài jailbreak, bootstrap hay daemon thường trú và không inject mã vào ứng dụng bên thứ ba. Do ứng dụng vẫn dùng khai thác thiết bị và có thể sửa dữ liệu app, không thể bảo đảm vượt qua mọi cơ chế kiểm tra tính toàn vẹn hoặc phát hiện jailbreak.
- Hỗ trợ tiếng Anh, tiếng Việt và tiếng Trung giản thể.

## Phiên bản iOS đã xác minh

| Hệ thống | Phiên bản/build |
| --- | --- |
| iOS 26 | 26.0 đến 26.6.1 |
| iOS 27 beta 1 | `24A5355q` |
| iOS 27 beta 2 | `24A5370h` |
| iOS 27 beta 3 | `24A5380h` |
| iOS 27 beta 4 | `24A5390f` |

Những build không có trong bảng sẽ được đánh dấu là không hỗ trợ.

## Lưu ý cài đặt

- Các chức năng trên thiết bị yêu cầu ứng dụng được ký bằng **chứng chỉ doanh nghiệp**.
- Không hỗ trợ SideStore, AltStore, 3uTools hoặc LiveContainer.
- Bundle ID `com.apple.mobile.MobileHouseArrest` được giữ có chủ đích cho luồng MHA-C2.
- Cây mã nguồn không chứa chứng chỉ, provisioning profile, ứng dụng đã ký hoặc IPA; phần Release có thể cung cấp IPA unsigned.

## Tác giả và ghi công

3105 được phát triển và thiết kế bởi [YangJiii](https://x.com/duongduong0908). Xem [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md) để biết các dự án và nhà phát triển nền tảng đã được sử dụng/tham khảo.

## Giấy phép

Phần mã gốc của 3105 được phát hành theo [GNU General Public License v3.0](LICENSE). Thành phần của bên thứ ba vẫn tuân theo bản quyền và điều khoản của dự án nguồn tương ứng; xem [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md).


## Bản cập nhật giao diện ProxyVN SHOP DHP
- Hiển thị thẻ thông tin thiết bị gồm iOS, Device và trạng thái hỗ trợ.
- Thanh Key cố định ở đáy màn hình; Key đã kích hoạt được lưu cục bộ.
- Nút Cài đặt nằm trong nội dung cuộn, không còn là thanh nổi cố định khi cuộn.
- Tên ứng dụng: `ProxyVN SHOP DHP` kèm dấu xác minh.
- Chức năng chỉ hiển thị trạng thái kích hoạt thành công khi có patch tài nguyên tích hợp.
- Chức năng chưa có patch hiển thị `⚠️ Chức năng đang được bảo trì`.
- Key hết hạn chặn thao tác chức năng và hiển thị `⚠️ Key đã hết hạn`.
- `Magic.3105` được đóng gói sẵn trong app bundle cho luồng patch demo nội bộ.
