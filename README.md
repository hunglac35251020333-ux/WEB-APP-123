# PeopleOps HRM Việt Nam

Ứng dụng HRM responsive bằng React/Vite, giao diện tiếng Việt, ngày `DD/MM/YYYY`, tiền tệ `VND`, múi giờ `Asia/Ho_Chi_Minh`.

## Trạng thái hiện tại

- Dashboard lấy số liệu từ kho dữ liệu phát triển `localStorage` và tự cập nhật khi thêm/xóa nhân viên.
- Danh sách nhân viên có tìm kiếm, lọc, trạng thái, phân trang giao diện, thêm mới có validation và xóa có xác nhận.
- 12 module đã có điều hướng và khung trải nghiệm đồng nhất.
- Dữ liệu hiển thị mặc định là **dữ liệu mẫu phát triển**, không phải dữ liệu production.
- Backend production chưa được coi là hoạt động cho đến khi cấu hình Supabase và áp dụng migration.

## Chạy local

```bash
npm install
npm run dev
```

Build kiểm tra production:

```bash
npm run build
npm run preview
```

## Biến môi trường production

Tạo `.env.local` (không commit):

```env
VITE_SUPABASE_URL=https://YOUR_PROJECT.supabase.co
VITE_SUPABASE_ANON_KEY=YOUR_ANON_KEY
SUPABASE_SERVICE_ROLE_KEY=SERVER_ONLY_NEVER_EXPOSE_IN_BROWSER
APP_TIMEZONE=Asia/Ho_Chi_Minh
```

`SUPABASE_SERVICE_ROLE_KEY` chỉ dùng ở server/Edge Function. Không đặt khóa này trong biến bắt đầu bằng `VITE_`.

## Khởi tạo database

1. Tạo Supabase project tại khu vực gần Việt Nam.
2. Chạy `supabase/migrations/001_init.sql` bằng Supabase CLI hoặc SQL editor.
3. Bật email/password trong Supabase Auth.
4. Tạo người dùng quản trị trong Auth, sau đó thêm hồ sơ tương ứng vào `profiles` và gán vai trò `super_admin`.
5. Kiểm tra RLS bằng bốn tài khoản: Super Admin, HR Admin, Quản lý phòng ban, Nhân viên.

## Kiến trúc đề xuất

- Frontend: React + TypeScript, component library riêng/Tailwind khi mở rộng.
- Auth: Supabase Auth, session bằng cookie HTTP-only ở lớp server khi chuyển sang Next.js.
- Data: PostgreSQL với khóa ngoại, check constraint, RLS và audit log.
- API: Route handlers/Edge Functions; kiểm tra Zod ở biên API; mọi quyền nhạy cảm kiểm tra lại phía server.
- File: private Storage buckets, signed URL ngắn hạn cho hợp đồng, giấy tờ và phiếu lương.
- Báo cáo: truy vấn server-side theo phạm vi quyền; export bất đồng bộ; ghi audit khi xuất dữ liệu nhạy cảm.

## Luồng nghiệp vụ chính

- Nhân viên: tạo hồ sơ → mời tài khoản → gán vai trò/phòng ban → bổ sung hợp đồng/tài liệu → kích hoạt.
- Chấm công: check-in/out → đối chiếu ca → phát hiện muộn/sớm/tăng ca → quản lý duyệt → khóa bảng công.
- Nghỉ phép: gửi đơn → kiểm tra số dư/xung đột → quản lý duyệt → HR xác nhận nếu cần → trừ số dư.
- Bảng lương: khóa công → tính thu nhập/khấu trừ → HR kiểm tra → cấp có thẩm quyền duyệt → phát hành phiếu lương riêng tư.
- Hợp đồng: tạo bản nháp → phê duyệt → ký/lưu file riêng tư → cảnh báo trước hạn → gia hạn hoặc kết thúc.

## Kiểm thử cần có trước production

- Unit: tính công, số dư phép, thuế/khấu trừ, kiểm tra ngày hợp đồng.
- Integration: CRUD nhân viên, duyệt phép, khóa công, tạo bảng lương, xuất báo cáo.
- Security: RLS theo từng vai trò; IDOR; upload file; session expiry; audit export.
- E2E: đăng nhập, thêm nhân viên, check-in/out, duyệt nghỉ, xuất báo cáo.

## Triển khai

Build ứng dụng bằng `npm run build`, cấu hình biến môi trường trên nền tảng triển khai, áp dụng migration trước khi phát hành phiên bản ứng dụng. Bắt buộc sao lưu database, bật PITR nếu gói hỗ trợ, giới hạn CORS và thiết lập chính sách retention cho audit log/tài liệu.
