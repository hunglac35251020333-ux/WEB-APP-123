-- PeopleOps HRM - Complete production schema extension
-- Run after 001_init.sql on Supabase PostgreSQL.
-- Time values are stored as timestamptz (UTC) and rendered in Asia/Ho_Chi_Minh.

begin;

create extension if not exists pgcrypto;
create extension if not exists citext;

-- ============================================================
-- Shared helpers
-- ============================================================

create or replace function set_updated_at()
returns trigger language plpgsql as $$
begin
  new.updated_at = now();
  return new;
end;
$$;

create or replace function is_admin()
returns boolean language sql stable security definer set search_path = public as $$
  select coalesce(app_current_role() in ('super_admin','hr_admin'), false)
$$;

create or replace function is_super_admin()
returns boolean language sql stable security definer set search_path = public as $$
  select coalesce(app_current_role() = 'super_admin', false)
$$;

create or replace function manages_employee(target_employee uuid)
returns boolean language sql stable security definer set search_path = public as $$
  select exists (
    select 1 from employees e
    where e.id = target_employee and e.manager_id = current_employee_id()
  )
$$;

-- ============================================================
-- Organization, employee profile, roles and documents
-- ============================================================

alter table departments
  add column if not exists description text,
  add column if not exists parent_id uuid references departments(id) on delete set null,
  add column if not exists cost_center text,
  add column if not exists active boolean not null default true,
  add column if not exists updated_at timestamptz not null default now();

alter table positions
  add column if not exists code text,
  add column if not exists description text,
  add column if not exists active boolean not null default true,
  add column if not exists created_at timestamptz not null default now(),
  add column if not exists updated_at timestamptz not null default now();

create unique index if not exists positions_code_unique
  on positions(code) where code is not null;

alter table employees
  add column if not exists avatar_path text,
  add column if not exists national_id text,
  add column if not exists national_id_issued_date date,
  add column if not exists national_id_issued_place text,
  add column if not exists tax_code text,
  add column if not exists social_insurance_no text,
  add column if not exists bank_name text,
  add column if not exists bank_account_no text,
  add column if not exists emergency_contact_name text,
  add column if not exists emergency_contact_phone text,
  add column if not exists emergency_contact_relationship text,
  add column if not exists probation_end_date date,
  add column if not exists termination_date date,
  add column if not exists termination_reason text,
  add column if not exists metadata jsonb not null default '{}'::jsonb;

create table if not exists permissions (
  id uuid primary key default gen_random_uuid(),
  code text unique not null check (code ~ '^[a-z0-9_.-]+$'),
  module text not null,
  action text not null,
  description text,
  created_at timestamptz not null default now()
);

create table if not exists role_permissions (
  role app_role not null,
  permission_id uuid not null references permissions(id) on delete cascade,
  granted boolean not null default true,
  created_at timestamptz not null default now(),
  primary key (role, permission_id)
);

create or replace function has_permission(permission_code text)
returns boolean language sql stable security definer set search_path = public as $$
  select coalesce(
    app_current_role() = 'super_admin' or exists (
      select 1
      from role_permissions rp
      join permissions p on p.id = rp.permission_id
      where rp.role = app_current_role()
        and rp.granted = true
        and p.code = permission_code
    ), false
  )
$$;

create table if not exists employee_job_history (
  id uuid primary key default gen_random_uuid(),
  employee_id uuid not null references employees(id) on delete cascade,
  department_id uuid references departments(id) on delete set null,
  position_id uuid references positions(id) on delete set null,
  manager_id uuid references employees(id) on delete set null,
  effective_from date not null,
  effective_to date,
  change_type text not null check (change_type in ('hire','transfer','promotion','demotion','manager_change','termination','rehire')),
  note text,
  created_by uuid references auth.users(id) on delete set null,
  created_at timestamptz not null default now(),
  check (effective_to is null or effective_to >= effective_from)
);

create table if not exists employee_documents (
  id uuid primary key default gen_random_uuid(),
  employee_id uuid not null references employees(id) on delete cascade,
  document_type text not null,
  title text not null,
  storage_path text not null,
  mime_type text,
  file_size_bytes bigint check (file_size_bytes is null or file_size_bytes >= 0),
  confidential boolean not null default true,
  expires_at date,
  uploaded_by uuid references auth.users(id) on delete set null,
  created_at timestamptz not null default now()
);

-- ============================================================
-- Work shifts and attendance
-- ============================================================

create table if not exists work_shifts (
  id uuid primary key default gen_random_uuid(),
  code text unique not null,
  name text not null,
  start_time time not null,
  end_time time not null,
  break_minutes integer not null default 60 check (break_minutes between 0 and 480),
  grace_late_minutes integer not null default 0 check (grace_late_minutes between 0 and 240),
  grace_early_minutes integer not null default 0 check (grace_early_minutes between 0 and 240),
  crosses_midnight boolean not null default false,
  active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists employee_shift_assignments (
  id uuid primary key default gen_random_uuid(),
  employee_id uuid not null references employees(id) on delete cascade,
  shift_id uuid not null references work_shifts(id) on delete restrict,
  effective_from date not null,
  effective_to date,
  weekdays smallint[] not null default '{1,2,3,4,5}',
  created_at timestamptz not null default now(),
  check (effective_to is null or effective_to >= effective_from)
);

alter table attendance
  add column if not exists shift_id uuid references work_shifts(id) on delete set null,
  add column if not exists check_in_source text,
  add column if not exists check_out_source text,
  add column if not exists check_in_latitude numeric(9,6),
  add column if not exists check_in_longitude numeric(9,6),
  add column if not exists check_out_latitude numeric(9,6),
  add column if not exists check_out_longitude numeric(9,6),
  add column if not exists status text not null default 'present',
  add column if not exists note text,
  add column if not exists approved_by uuid references employees(id) on delete set null,
  add column if not exists approved_at timestamptz,
  add column if not exists updated_at timestamptz not null default now();

create table if not exists attendance_adjustments (
  id uuid primary key default gen_random_uuid(),
  attendance_id uuid references attendance(id) on delete cascade,
  employee_id uuid not null references employees(id) on delete cascade,
  work_date date not null,
  requested_check_in timestamptz,
  requested_check_out timestamptz,
  reason text not null,
  status text not null default 'pending' check (status in ('pending','approved','rejected','cancelled')),
  reviewed_by uuid references employees(id) on delete set null,
  reviewed_at timestamptz,
  review_note text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists overtime_requests (
  id uuid primary key default gen_random_uuid(),
  employee_id uuid not null references employees(id) on delete cascade,
  work_date date not null,
  start_time timestamptz not null,
  end_time timestamptz not null,
  requested_minutes integer generated always as ((extract(epoch from (end_time - start_time)) / 60)::integer) stored,
  approved_minutes integer check (approved_minutes is null or approved_minutes >= 0),
  reason text not null,
  status text not null default 'pending' check (status in ('pending','approved','rejected','cancelled')),
  approver_id uuid references employees(id) on delete set null,
  approved_at timestamptz,
  created_at timestamptz not null default now(),
  check (end_time > start_time)
);

create table if not exists holidays (
  id uuid primary key default gen_random_uuid(),
  holiday_date date unique not null,
  name text not null,
  paid boolean not null default true,
  created_at timestamptz not null default now()
);

-- ============================================================
-- Leave management
-- ============================================================

create table if not exists leave_types (
  id uuid primary key default gen_random_uuid(),
  code text unique not null,
  name text not null,
  annual_quota numeric(5,2) not null default 0 check (annual_quota >= 0),
  paid boolean not null default true,
  requires_attachment boolean not null default false,
  carry_forward_limit numeric(5,2) not null default 0 check (carry_forward_limit >= 0),
  active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

alter table leave_requests
  add column if not exists leave_type_id uuid references leave_types(id) on delete restrict,
  add column if not exists session_start text not null default 'full_day',
  add column if not exists session_end text not null default 'full_day',
  add column if not exists attachment_path text,
  add column if not exists current_step integer not null default 1,
  add column if not exists updated_at timestamptz not null default now();

create table if not exists leave_balances (
  id uuid primary key default gen_random_uuid(),
  employee_id uuid not null references employees(id) on delete cascade,
  leave_type_id uuid not null references leave_types(id) on delete cascade,
  year integer not null check (year between 2000 and 2200),
  opening_balance numeric(6,2) not null default 0,
  accrued numeric(6,2) not null default 0,
  used numeric(6,2) not null default 0 check (used >= 0),
  adjustment numeric(6,2) not null default 0,
  updated_at timestamptz not null default now(),
  unique (employee_id, leave_type_id, year)
);

create table if not exists leave_approval_steps (
  id uuid primary key default gen_random_uuid(),
  leave_request_id uuid not null references leave_requests(id) on delete cascade,
  step_no integer not null check (step_no > 0),
  approver_id uuid references employees(id) on delete set null,
  approver_role app_role,
  status text not null default 'pending' check (status in ('pending','approved','rejected','skipped')),
  note text,
  decided_at timestamptz,
  created_at timestamptz not null default now(),
  unique (leave_request_id, step_no)
);

create or replace view leave_balance_summary as
select
  lb.employee_id,
  lb.leave_type_id,
  lt.code as leave_type_code,
  lt.name as leave_type_name,
  lb.year,
  lb.opening_balance + lb.accrued + lb.adjustment as entitlement,
  lb.used,
  lb.opening_balance + lb.accrued + lb.adjustment - lb.used as remaining
from leave_balances lb
join leave_types lt on lt.id = lb.leave_type_id;

-- ============================================================
-- Contracts
-- ============================================================

alter table contracts
  add column if not exists status text not null default 'draft',
  add column if not exists signed_at date,
  add column if not exists probation_salary numeric(15,2),
  add column if not exists notes text,
  add column if not exists created_by uuid references auth.users(id) on delete set null,
  add column if not exists updated_at timestamptz not null default now();

create table if not exists contract_extensions (
  id uuid primary key default gen_random_uuid(),
  contract_id uuid not null references contracts(id) on delete cascade,
  old_end_date date,
  new_end_date date not null,
  old_base_salary numeric(15,2),
  new_base_salary numeric(15,2) check (new_base_salary is null or new_base_salary >= 0),
  reason text,
  attachment_path text,
  approved_by uuid references auth.users(id) on delete set null,
  created_at timestamptz not null default now(),
  check (old_end_date is null or new_end_date >= old_end_date)
);

create or replace view expiring_contracts as
select c.*, e.employee_code, e.full_name, e.department_id,
       (c.end_date - current_date) as days_remaining
from contracts c
join employees e on e.id = c.employee_id
where c.end_date is not null
  and c.status not in ('terminated','expired')
  and c.end_date between current_date and current_date + 90;

-- ============================================================
-- Payroll
-- ============================================================

create table if not exists payroll_runs (
  id uuid primary key default gen_random_uuid(),
  period_start date not null,
  period_end date not null,
  pay_date date,
  status text not null default 'draft' check (status in ('draft','calculating','review','approved','paid','cancelled')),
  locked_at timestamptz,
  locked_by uuid references auth.users(id) on delete set null,
  approved_at timestamptz,
  approved_by uuid references auth.users(id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (period_start, period_end),
  check (period_end >= period_start)
);

alter table payrolls
  add column if not exists payroll_run_id uuid references payroll_runs(id) on delete restrict,
  add column if not exists gross_salary numeric(15,2) not null default 0,
  add column if not exists net_salary numeric(15,2) not null default 0,
  add column if not exists payslip_path text,
  add column if not exists paid_at timestamptz,
  add column if not exists updated_at timestamptz not null default now();

create table if not exists payroll_components (
  id uuid primary key default gen_random_uuid(),
  code text unique not null,
  name text not null,
  component_type text not null check (component_type in ('earning','deduction','employer_contribution')),
  taxable boolean not null default true,
  insurance_base boolean not null default false,
  active boolean not null default true,
  created_at timestamptz not null default now()
);

create table if not exists payroll_items (
  id uuid primary key default gen_random_uuid(),
  payroll_id uuid not null references payrolls(id) on delete cascade,
  component_id uuid references payroll_components(id) on delete restrict,
  label text not null,
  quantity numeric(12,2) not null default 1,
  unit_amount numeric(15,2) not null default 0,
  amount numeric(15,2) not null,
  note text,
  created_at timestamptz not null default now()
);

-- ============================================================
-- Performance / KPI / OKR
-- ============================================================

create table if not exists performance_cycles (
  id uuid primary key default gen_random_uuid(),
  name text not null,
  start_date date not null,
  end_date date not null,
  status text not null default 'draft' check (status in ('draft','active','review','closed')),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  check (end_date >= start_date)
);

create table if not exists objectives (
  id uuid primary key default gen_random_uuid(),
  cycle_id uuid not null references performance_cycles(id) on delete cascade,
  employee_id uuid references employees(id) on delete cascade,
  department_id uuid references departments(id) on delete cascade,
  parent_id uuid references objectives(id) on delete set null,
  title text not null,
  description text,
  weight numeric(5,2) not null default 0 check (weight between 0 and 100),
  progress numeric(5,2) not null default 0 check (progress between 0 and 100),
  status text not null default 'not_started' check (status in ('not_started','on_track','at_risk','completed','cancelled')),
  created_by uuid references auth.users(id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  check (employee_id is not null or department_id is not null)
);

create table if not exists key_results (
  id uuid primary key default gen_random_uuid(),
  objective_id uuid not null references objectives(id) on delete cascade,
  title text not null,
  metric_type text not null default 'number' check (metric_type in ('number','percentage','currency','boolean')),
  start_value numeric(18,2) not null default 0,
  target_value numeric(18,2) not null,
  current_value numeric(18,2) not null default 0,
  unit text,
  due_date date,
  updated_at timestamptz not null default now()
);

create table if not exists performance_reviews (
  id uuid primary key default gen_random_uuid(),
  cycle_id uuid not null references performance_cycles(id) on delete cascade,
  employee_id uuid not null references employees(id) on delete cascade,
  reviewer_id uuid not null references employees(id) on delete restrict,
  review_type text not null default 'manager' check (review_type in ('self','manager','peer','hr')),
  score numeric(4,2) check (score between 0 and 5),
  strengths text,
  improvements text,
  summary text,
  status text not null default 'draft' check (status in ('draft','submitted','acknowledged','closed')),
  submitted_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (cycle_id, employee_id, reviewer_id, review_type)
);

-- ============================================================
-- Recruitment
-- ============================================================

create table if not exists job_openings (
  id uuid primary key default gen_random_uuid(),
  code text unique not null,
  title text not null,
  department_id uuid references departments(id) on delete restrict,
  position_id uuid references positions(id) on delete set null,
  hiring_manager_id uuid references employees(id) on delete set null,
  headcount integer not null default 1 check (headcount > 0),
  employment_type text,
  location text,
  salary_min numeric(15,2),
  salary_max numeric(15,2),
  description text,
  requirements text,
  status text not null default 'draft' check (status in ('draft','open','paused','closed','cancelled')),
  opened_at date,
  closed_at date,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  check (salary_min is null or salary_min >= 0),
  check (salary_max is null or salary_max >= coalesce(salary_min,0))
);

create table if not exists candidates (
  id uuid primary key default gen_random_uuid(),
  full_name text not null,
  email citext not null,
  phone text,
  source text,
  resume_path text,
  linkedin_url text,
  portfolio_url text,
  consent_at timestamptz,
  retention_until date,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (email)
);

create table if not exists applications (
  id uuid primary key default gen_random_uuid(),
  job_opening_id uuid not null references job_openings(id) on delete cascade,
  candidate_id uuid not null references candidates(id) on delete cascade,
  stage text not null default 'applied' check (stage in ('applied','screening','interview','offer','hired','rejected','withdrawn')),
  rating numeric(3,2) check (rating between 0 and 5),
  owner_id uuid references employees(id) on delete set null,
  rejection_reason text,
  applied_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (job_opening_id, candidate_id)
);

create table if not exists interviews (
  id uuid primary key default gen_random_uuid(),
  application_id uuid not null references applications(id) on delete cascade,
  round_no integer not null default 1 check (round_no > 0),
  interview_type text not null,
  scheduled_start timestamptz not null,
  scheduled_end timestamptz not null,
  location_or_link text,
  status text not null default 'scheduled' check (status in ('scheduled','completed','cancelled','no_show')),
  score numeric(3,2) check (score between 0 and 5),
  feedback text,
  created_at timestamptz not null default now(),
  check (scheduled_end > scheduled_start)
);

create table if not exists interview_panelists (
  interview_id uuid not null references interviews(id) on delete cascade,
  employee_id uuid not null references employees(id) on delete cascade,
  primary key (interview_id, employee_id)
);

-- ============================================================
-- Assets
-- ============================================================

create table if not exists asset_categories (
  id uuid primary key default gen_random_uuid(),
  code text unique not null,
  name text not null,
  depreciation_months integer check (depreciation_months is null or depreciation_months > 0),
  created_at timestamptz not null default now()
);

create table if not exists assets (
  id uuid primary key default gen_random_uuid(),
  asset_code text unique not null,
  category_id uuid references asset_categories(id) on delete restrict,
  name text not null,
  brand text,
  model text,
  serial_number text unique,
  purchase_date date,
  purchase_cost numeric(15,2) check (purchase_cost is null or purchase_cost >= 0),
  warranty_end_date date,
  status text not null default 'available' check (status in ('available','assigned','maintenance','lost','retired')),
  condition text,
  location text,
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists asset_assignments (
  id uuid primary key default gen_random_uuid(),
  asset_id uuid not null references assets(id) on delete restrict,
  employee_id uuid not null references employees(id) on delete restrict,
  assigned_at timestamptz not null default now(),
  expected_return_date date,
  returned_at timestamptz,
  condition_out text,
  condition_in text,
  handover_document_path text,
  assigned_by uuid references auth.users(id) on delete set null,
  note text,
  check (returned_at is null or returned_at >= assigned_at)
);

create unique index if not exists one_active_asset_assignment
  on asset_assignments(asset_id) where returned_at is null;

-- ============================================================
-- Notifications, settings, reporting and audit
-- ============================================================

create table if not exists notifications (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  title text not null,
  message text not null,
  type text not null default 'info',
  action_url text,
  read_at timestamptz,
  created_at timestamptz not null default now()
);

create table if not exists system_settings (
  key text primary key,
  value jsonb not null,
  description text,
  sensitive boolean not null default false,
  updated_by uuid references auth.users(id) on delete set null,
  updated_at timestamptz not null default now()
);

create table if not exists report_exports (
  id uuid primary key default gen_random_uuid(),
  requested_by uuid not null references auth.users(id) on delete cascade,
  report_type text not null,
  format text not null check (format in ('csv','xlsx','pdf')),
  filters jsonb not null default '{}'::jsonb,
  status text not null default 'queued' check (status in ('queued','processing','completed','failed','expired')),
  storage_path text,
  error_message text,
  expires_at timestamptz,
  created_at timestamptz not null default now(),
  completed_at timestamptz
);

create or replace function audit_row_change()
returns trigger language plpgsql security definer set search_path = public as $$
declare
  row_id text;
  safe_metadata jsonb;
begin
  row_id := coalesce((to_jsonb(new)->>'id'), (to_jsonb(old)->>'id'));
  safe_metadata := jsonb_build_object(
    'operation', tg_op,
    'table', tg_table_name,
    'changed_at', now()
  );
  insert into audit_logs(actor_id, action, entity_type, entity_id, metadata)
  values (auth.uid(), lower(tg_op), tg_table_name, row_id, safe_metadata);
  return coalesce(new, old);
end;
$$;

-- Never copy salary, national ID, bank account or document contents into audit metadata.
drop trigger if exists audit_employees on employees;
create trigger audit_employees after insert or update or delete on employees
for each row execute function audit_row_change();
drop trigger if exists audit_contracts on contracts;
create trigger audit_contracts after insert or update or delete on contracts
for each row execute function audit_row_change();
drop trigger if exists audit_payrolls on payrolls;
create trigger audit_payrolls after insert or update or delete on payrolls
for each row execute function audit_row_change();
drop trigger if exists audit_leave_requests on leave_requests;
create trigger audit_leave_requests after insert or update or delete on leave_requests
for each row execute function audit_row_change();

-- ============================================================
-- Business functions
-- ============================================================

create or replace function check_in_employee(
  p_source text default 'web',
  p_latitude numeric default null,
  p_longitude numeric default null
)
returns attendance language plpgsql security definer set search_path = public as $$
declare
  emp uuid := current_employee_id();
  local_date date := (now() at time zone 'Asia/Ho_Chi_Minh')::date;
  result attendance;
begin
  if emp is null then raise exception 'Employee profile not found'; end if;
  insert into attendance(employee_id, work_date, check_in, check_in_source, check_in_latitude, check_in_longitude)
  values(emp, local_date, now(), p_source, p_latitude, p_longitude)
  on conflict(employee_id, work_date) do update
    set check_in = coalesce(attendance.check_in, excluded.check_in),
        check_in_source = coalesce(attendance.check_in_source, excluded.check_in_source),
        updated_at = now()
  returning * into result;
  return result;
end;
$$;

create or replace function check_out_employee(p_source text default 'web')
returns attendance language plpgsql security definer set search_path = public as $$
declare
  emp uuid := current_employee_id();
  local_date date := (now() at time zone 'Asia/Ho_Chi_Minh')::date;
  result attendance;
begin
  update attendance
  set check_out = now(), check_out_source = p_source, updated_at = now()
  where employee_id = emp and work_date = local_date and check_in is not null
  returning * into result;
  if result.id is null then raise exception 'No check-in found for today'; end if;
  return result;
end;
$$;

create or replace function approve_leave_request(p_request_id uuid, p_approve boolean, p_note text default null)
returns leave_requests language plpgsql security definer set search_path = public as $$
declare
  req leave_requests;
begin
  select * into req from leave_requests where id = p_request_id for update;
  if req.id is null then raise exception 'Leave request not found'; end if;
  if not (is_admin() or manages_employee(req.employee_id)) then raise exception 'Permission denied'; end if;
  if req.status <> 'pending' then raise exception 'Request has already been processed'; end if;

  update leave_requests
  set status = case when p_approve then 'approved' else 'rejected' end,
      approver_id = current_employee_id(), updated_at = now()
  where id = p_request_id returning * into req;

  if p_approve and req.leave_type_id is not null then
    insert into leave_balances(employee_id, leave_type_id, year, used)
    values(req.employee_id, req.leave_type_id, extract(year from req.start_date)::int, req.days)
    on conflict(employee_id, leave_type_id, year)
    do update set used = leave_balances.used + excluded.used, updated_at = now();
  end if;

  insert into leave_approval_steps(leave_request_id, step_no, approver_id, status, note, decided_at)
  values(req.id, req.current_step, current_employee_id(), case when p_approve then 'approved' else 'rejected' end, p_note, now())
  on conflict(leave_request_id, step_no) do update
    set approver_id = excluded.approver_id, status = excluded.status,
        note = excluded.note, decided_at = excluded.decided_at;
  return req;
end;
$$;

-- ============================================================
-- Dashboard views backed by live database data
-- ============================================================

create or replace view dashboard_employee_metrics as
select
  count(*) filter (where status in ('active','probation','on_leave')) as total_employees,
  count(*) filter (where start_date >= current_date - 30) as new_last_30_days,
  count(*) filter (where status = 'terminated' and termination_date >= date_trunc('month', current_date)::date) as terminated_this_month,
  count(*) filter (where status = 'probation') as probation_count,
  count(*) filter (where status = 'on_leave') as on_leave_count
from employees;

create or replace view dashboard_department_distribution as
select d.id, d.code, d.name,
       count(e.id) filter (where e.status in ('active','probation','on_leave')) as employee_count
from departments d
left join employees e on e.department_id = d.id
where d.active = true
group by d.id, d.code, d.name;

create or replace view dashboard_attendance_monthly as
select
  date_trunc('month', work_date)::date as month,
  count(*) as attendance_records,
  count(*) filter (where late_minutes > 0) as late_count,
  count(*) filter (where early_minutes > 0) as early_count,
  sum(overtime_minutes) as overtime_minutes,
  round(100.0 * count(*) filter (where status = 'present') / nullif(count(*),0), 2) as attendance_rate
from attendance
group by date_trunc('month', work_date);

create or replace view dashboard_headcount_monthly as
with months(month_start) as (
  select generated_at::date
  from generate_series(
    date_trunc('month', current_date) - interval '11 months',
    date_trunc('month', current_date),
    interval '1 month'
  ) as generated_at
)
select
  m.month_start,
  count(e.id) filter (
    where e.start_date >= m.month_start
      and e.start_date < m.month_start + interval '1 month'
  ) as joined,
  count(e.id) filter (
    where e.termination_date >= m.month_start
      and e.termination_date < m.month_start + interval '1 month'
  ) as left_company
from months m
left join employees e on true
group by m.month_start
order by m.month_start;

-- ============================================================
-- Indexes and update triggers
-- ============================================================

create index if not exists employees_manager_idx on employees(manager_id);
create index if not exists employees_status_idx on employees(status);
create index if not exists employee_history_employee_date_idx on employee_job_history(employee_id, effective_from desc);
create index if not exists employee_documents_employee_idx on employee_documents(employee_id, document_type);
create index if not exists shift_assignments_employee_date_idx on employee_shift_assignments(employee_id, effective_from, effective_to);
create index if not exists attendance_adjustment_status_idx on attendance_adjustments(status, created_at);
create index if not exists overtime_employee_date_idx on overtime_requests(employee_id, work_date);
create index if not exists leave_balance_employee_year_idx on leave_balances(employee_id, year);
create index if not exists payroll_run_status_idx on payroll_runs(status, period_end);
create index if not exists payroll_items_payroll_idx on payroll_items(payroll_id);
create index if not exists objectives_employee_cycle_idx on objectives(employee_id, cycle_id);
create index if not exists reviews_employee_cycle_idx on performance_reviews(employee_id, cycle_id);
create index if not exists applications_stage_idx on applications(job_opening_id, stage);
create index if not exists interviews_schedule_idx on interviews(scheduled_start);
create index if not exists assets_status_idx on assets(status, category_id);
create index if not exists notifications_unread_idx on notifications(user_id, created_at desc) where read_at is null;
create index if not exists audit_logs_entity_idx on audit_logs(entity_type, entity_id, created_at desc);

do $$
declare t text;
begin
  foreach t in array array[
    'departments','positions','employees','work_shifts','attendance','attendance_adjustments',
    'leave_types','leave_requests','leave_balances','contracts','payroll_runs','payrolls',
    'performance_cycles','objectives','key_results','performance_reviews','job_openings',
    'candidates','applications','assets','system_settings'
  ] loop
    execute format('drop trigger if exists set_%I_updated_at on %I', t, t);
    execute format('create trigger set_%I_updated_at before update on %I for each row execute function set_updated_at()', t, t);
  end loop;
end $$;

-- ============================================================
-- RLS
-- ============================================================

alter table permissions enable row level security;
alter table role_permissions enable row level security;
alter table employee_job_history enable row level security;
alter table employee_documents enable row level security;
alter table work_shifts enable row level security;
alter table employee_shift_assignments enable row level security;
alter table attendance_adjustments enable row level security;
alter table overtime_requests enable row level security;
alter table holidays enable row level security;
alter table leave_types enable row level security;
alter table leave_balances enable row level security;
alter table leave_approval_steps enable row level security;
alter table contract_extensions enable row level security;
alter table payroll_runs enable row level security;
alter table payroll_components enable row level security;
alter table payroll_items enable row level security;
alter table performance_cycles enable row level security;
alter table objectives enable row level security;
alter table key_results enable row level security;
alter table performance_reviews enable row level security;
alter table job_openings enable row level security;
alter table candidates enable row level security;
alter table applications enable row level security;
alter table interviews enable row level security;
alter table interview_panelists enable row level security;
alter table asset_categories enable row level security;
alter table assets enable row level security;
alter table asset_assignments enable row level security;
alter table notifications enable row level security;
alter table system_settings enable row level security;
alter table report_exports enable row level security;

create policy permissions_authenticated_read on permissions for select to authenticated using (true);
create policy permissions_super_write on permissions for all to authenticated using (is_super_admin()) with check (is_super_admin());
create policy role_permissions_authenticated_read on role_permissions for select to authenticated using (true);
create policy role_permissions_super_write on role_permissions for all to authenticated using (is_super_admin()) with check (is_super_admin());

create policy history_scope_read on employee_job_history for select to authenticated
using (is_admin() or employee_id = current_employee_id() or manages_employee(employee_id));
create policy history_hr_write on employee_job_history for all to authenticated using (is_admin()) with check (is_admin());

create policy documents_scope_read on employee_documents for select to authenticated
using (is_admin() or employee_id = current_employee_id());
create policy documents_hr_write on employee_documents for all to authenticated using (is_admin()) with check (is_admin());

create policy shifts_read on work_shifts for select to authenticated using (true);
create policy shifts_hr_write on work_shifts for all to authenticated using (is_admin()) with check (is_admin());
create policy shift_assignments_scope_read on employee_shift_assignments for select to authenticated
using (is_admin() or employee_id = current_employee_id() or manages_employee(employee_id));
create policy shift_assignments_hr_write on employee_shift_assignments for all to authenticated using (is_admin()) with check (is_admin());

create policy adjustments_scope_read on attendance_adjustments for select to authenticated
using (is_admin() or employee_id = current_employee_id() or manages_employee(employee_id));
create policy adjustments_self_create on attendance_adjustments for insert to authenticated
with check (employee_id = current_employee_id());
create policy adjustments_approver_update on attendance_adjustments for update to authenticated
using (is_admin() or manages_employee(employee_id)) with check (is_admin() or manages_employee(employee_id));

create policy overtime_scope_read on overtime_requests for select to authenticated
using (is_admin() or employee_id = current_employee_id() or manages_employee(employee_id));
create policy overtime_self_create on overtime_requests for insert to authenticated with check (employee_id = current_employee_id());
create policy overtime_approver_update on overtime_requests for update to authenticated
using (is_admin() or manages_employee(employee_id)) with check (is_admin() or manages_employee(employee_id));

create policy holidays_read on holidays for select to authenticated using (true);
create policy holidays_hr_write on holidays for all to authenticated using (is_admin()) with check (is_admin());
create policy leave_types_read on leave_types for select to authenticated using (true);
create policy leave_types_hr_write on leave_types for all to authenticated using (is_admin()) with check (is_admin());
create policy leave_balances_scope_read on leave_balances for select to authenticated
using (is_admin() or employee_id = current_employee_id() or manages_employee(employee_id));
create policy leave_balances_hr_write on leave_balances for all to authenticated using (is_admin()) with check (is_admin());
create policy leave_steps_scope_read on leave_approval_steps for select to authenticated
using (is_admin() or approver_id = current_employee_id() or exists(select 1 from leave_requests r where r.id = leave_request_id and r.employee_id = current_employee_id()));

create policy contract_extensions_scope_read on contract_extensions for select to authenticated
using (is_admin() or exists(select 1 from contracts c where c.id = contract_id and c.employee_id = current_employee_id()));
create policy contract_extensions_hr_write on contract_extensions for all to authenticated using (is_admin()) with check (is_admin());

create policy payroll_runs_hr_only on payroll_runs for all to authenticated using (is_admin()) with check (is_admin());
create policy payroll_components_hr_only on payroll_components for all to authenticated using (is_admin()) with check (is_admin());
create policy payroll_items_scope_read on payroll_items for select to authenticated
using (is_admin() or exists(select 1 from payrolls p where p.id = payroll_id and p.employee_id = current_employee_id()));
create policy payroll_items_hr_write on payroll_items for all to authenticated using (is_admin()) with check (is_admin());

create policy performance_cycles_read on performance_cycles for select to authenticated using (true);
create policy performance_cycles_hr_write on performance_cycles for all to authenticated using (is_admin()) with check (is_admin());
create policy objectives_scope_read on objectives for select to authenticated
using (is_admin() or employee_id = current_employee_id() or department_id in (select department_id from employees where id = current_employee_id()));
create policy objectives_scope_write on objectives for all to authenticated
using (is_admin() or employee_id = current_employee_id() or manages_employee(employee_id))
with check (is_admin() or employee_id = current_employee_id() or manages_employee(employee_id));
create policy key_results_scope_read on key_results for select to authenticated
using (exists(select 1 from objectives o where o.id = objective_id and (is_admin() or o.employee_id = current_employee_id() or manages_employee(o.employee_id))));
create policy key_results_scope_write on key_results for all to authenticated
using (exists(select 1 from objectives o where o.id = objective_id and (is_admin() or o.employee_id = current_employee_id() or manages_employee(o.employee_id))))
with check (exists(select 1 from objectives o where o.id = objective_id and (is_admin() or o.employee_id = current_employee_id() or manages_employee(o.employee_id))));
create policy reviews_scope_read on performance_reviews for select to authenticated
using (is_admin() or employee_id = current_employee_id() or reviewer_id = current_employee_id());
create policy reviews_reviewer_write on performance_reviews for all to authenticated
using (is_admin() or reviewer_id = current_employee_id()) with check (is_admin() or reviewer_id = current_employee_id());

create policy jobs_authenticated_read on job_openings for select to authenticated using (true);
create policy jobs_hr_write on job_openings for all to authenticated using (is_admin()) with check (is_admin());
create policy candidates_hr_only on candidates for all to authenticated using (is_admin()) with check (is_admin());
create policy applications_hr_only on applications for all to authenticated using (is_admin()) with check (is_admin());
create policy interviews_panel_read on interviews for select to authenticated
using (is_admin() or exists(select 1 from interview_panelists p where p.interview_id = id and p.employee_id = current_employee_id()));
create policy interviews_hr_write on interviews for all to authenticated using (is_admin()) with check (is_admin());
create policy panelists_scope_read on interview_panelists for select to authenticated
using (is_admin() or employee_id = current_employee_id());
create policy panelists_hr_write on interview_panelists for all to authenticated using (is_admin()) with check (is_admin());

create policy asset_categories_read on asset_categories for select to authenticated using (true);
create policy asset_categories_hr_write on asset_categories for all to authenticated using (is_admin()) with check (is_admin());
create policy assets_authenticated_read on assets for select to authenticated using (true);
create policy assets_hr_write on assets for all to authenticated using (is_admin()) with check (is_admin());
create policy assignments_scope_read on asset_assignments for select to authenticated
using (is_admin() or employee_id = current_employee_id() or manages_employee(employee_id));
create policy assignments_hr_write on asset_assignments for all to authenticated using (is_admin()) with check (is_admin());

create policy notifications_owner on notifications for all to authenticated
using (user_id = auth.uid()) with check (user_id = auth.uid());
create policy settings_admin_only on system_settings for all to authenticated using (is_super_admin()) with check (is_super_admin());
create policy exports_owner_read on report_exports for select to authenticated
using (requested_by = auth.uid() or is_admin());
create policy exports_authorized_create on report_exports for insert to authenticated
with check (requested_by = auth.uid() and (is_admin() or has_permission('reports.export')));

-- Explicit grants; RLS remains the authorization boundary.
grant usage on schema public to authenticated;
grant select, insert, update, delete on all tables in schema public to authenticated;
grant usage, select on all sequences in schema public to authenticated;
grant execute on function check_in_employee(text,numeric,numeric) to authenticated;
grant execute on function check_out_employee(text) to authenticated;
grant execute on function approve_leave_request(uuid,boolean,text) to authenticated;

-- ============================================================
-- Default permission catalogue and non-sensitive settings
-- ============================================================

insert into permissions(code,module,action,description) values
('employees.read','employees','read','Xem hồ sơ nhân viên theo phạm vi'),
('employees.write','employees','write','Tạo và cập nhật hồ sơ nhân viên'),
('attendance.approve','attendance','approve','Duyệt điều chỉnh chấm công và tăng ca'),
('leave.approve','leave','approve','Duyệt đơn nghỉ phép'),
('contracts.read_sensitive','contracts','read_sensitive','Xem dữ liệu hợp đồng nhạy cảm'),
('payroll.manage','payroll','manage','Quản lý bảng lương'),
('recruitment.manage','recruitment','manage','Quản lý tuyển dụng'),
('assets.manage','assets','manage','Quản lý tài sản'),
('reports.export','reports','export','Xuất báo cáo'),
('settings.manage','settings','manage','Quản lý cấu hình hệ thống')
on conflict(code) do update set module=excluded.module, action=excluded.action, description=excluded.description;

insert into role_permissions(role,permission_id,granted)
select r.role, p.id, true
from (values
  ('hr_admin'::app_role,'employees.read'),('hr_admin'::app_role,'employees.write'),
  ('hr_admin'::app_role,'attendance.approve'),('hr_admin'::app_role,'leave.approve'),
  ('hr_admin'::app_role,'contracts.read_sensitive'),('hr_admin'::app_role,'payroll.manage'),
  ('hr_admin'::app_role,'recruitment.manage'),('hr_admin'::app_role,'assets.manage'),
  ('hr_admin'::app_role,'reports.export'),
  ('department_manager'::app_role,'employees.read'),('department_manager'::app_role,'attendance.approve'),
  ('department_manager'::app_role,'leave.approve'),('department_manager'::app_role,'reports.export')
) as r(role, code)
join permissions p on p.code = r.code
on conflict(role,permission_id) do update set granted=excluded.granted;

insert into system_settings(key,value,description,sensitive) values
('app.timezone','"Asia/Ho_Chi_Minh"'::jsonb,'Múi giờ mặc định',false),
('app.date_format','"DD/MM/YYYY"'::jsonb,'Định dạng ngày hiển thị',false),
('app.currency','"VND"'::jsonb,'Đơn vị tiền tệ',false),
('attendance.allow_mobile_checkin','true'::jsonb,'Cho phép chấm công từ thiết bị di động',false),
('contracts.expiry_warning_days','[90,60,30,7]'::jsonb,'Các mốc cảnh báo hợp đồng',false)
on conflict(key) do nothing;

commit;
