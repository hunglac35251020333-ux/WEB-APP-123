-- Development-only sample seed. Never run on a production database containing real HR data.
begin;

insert into departments(code,name,description) values
('TECH','Công nghệ','Phát triển sản phẩm và nền tảng'),
('HR','Nhân sự','Vận hành con người và tổ chức'),
('SALES','Kinh doanh','Phát triển khách hàng và doanh thu'),
('MKT','Marketing','Thương hiệu và tăng trưởng'),
('OPS','Vận hành','Vận hành doanh nghiệp')
on conflict(code) do update set name=excluded.name, description=excluded.description;

insert into positions(code,name,department_id,level)
select v.code,v.name,d.id,v.level
from (values
  ('ENG_LEAD','Engineering Lead','TECH',8),
  ('PRODUCT_MANAGER','Product Manager','TECH',7),
  ('HR_DIRECTOR','HR Director','HR',10),
  ('ACCOUNT_EXEC','Account Executive','SALES',5),
  ('CONTENT_SPECIALIST','Content Specialist','MKT',4)
) v(code,name,department_code,level)
join departments d on d.code=v.department_code
on conflict(code) do update set name=excluded.name,department_id=excluded.department_id,level=excluded.level;

insert into work_shifts(code,name,start_time,end_time,break_minutes,grace_late_minutes) values
('OFFICE','Ca hành chính','08:30','17:30',60,10),
('MORNING','Ca sáng','06:00','14:00',30,5),
('EVENING','Ca chiều','14:00','22:00',30,5)
on conflict(code) do update set name=excluded.name,start_time=excluded.start_time,end_time=excluded.end_time;

insert into leave_types(code,name,annual_quota,paid,carry_forward_limit) values
('ANNUAL','Nghỉ phép năm',12,true,5),
('SICK','Nghỉ ốm',0,true,0),
('UNPAID','Nghỉ không lương',0,false,0),
('MARRIAGE','Nghỉ kết hôn',3,true,0),
('BEREAVEMENT','Nghỉ tang',3,true,0)
on conflict(code) do update set name=excluded.name,annual_quota=excluded.annual_quota,paid=excluded.paid;

insert into payroll_components(code,name,component_type,taxable,insurance_base) values
('BASE','Lương cơ bản','earning',true,true),
('ALLOWANCE','Phụ cấp','earning',true,false),
('BONUS','Thưởng','earning',true,false),
('PIT','Thuế thu nhập cá nhân','deduction',false,false),
('SI','Bảo hiểm xã hội','deduction',false,false),
('HI','Bảo hiểm y tế','deduction',false,false),
('UI','Bảo hiểm thất nghiệp','deduction',false,false)
on conflict(code) do update set name=excluded.name,component_type=excluded.component_type;

insert into asset_categories(code,name,depreciation_months) values
('LAPTOP','Máy tính xách tay',36),
('MONITOR','Màn hình',36),
('PHONE','Điện thoại',36),
('ACCESSORY','Phụ kiện',24),
('OTHER','Khác',null)
on conflict(code) do update set name=excluded.name,depreciation_months=excluded.depreciation_months;

commit;
