-- PeopleOps HRM core schema for Supabase PostgreSQL.
-- Safe to rerun after an interrupted first execution.

begin;

create extension if not exists pgcrypto;

do $$ begin
  create type app_role as enum ('super_admin','hr_admin','department_manager','employee');
exception when duplicate_object then null;
end $$;

do $$ begin
  create type employment_status as enum ('probation','active','on_leave','terminated');
exception when duplicate_object then null;
end $$;

create table if not exists departments (
  id uuid primary key default gen_random_uuid(),
  code text unique not null,
  name text not null,
  manager_id uuid,
  created_at timestamptz not null default now()
);

create table if not exists positions (
  id uuid primary key default gen_random_uuid(),
  department_id uuid references departments(id) on delete restrict,
  name text not null,
  level smallint not null default 1 check(level between 1 and 20)
);

create table if not exists employees (
  id uuid primary key default gen_random_uuid(),
  employee_code text unique not null,
  full_name text not null,
  work_email text unique not null,
  personal_email text,
  phone text,
  gender text,
  date_of_birth date,
  address text,
  department_id uuid references departments(id) on delete restrict,
  position_id uuid references positions(id) on delete restrict,
  manager_id uuid references employees(id) on delete set null,
  start_date date not null,
  status employment_status not null default 'probation',
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

do $$ begin
  alter table departments add constraint departments_manager_fk
    foreign key(manager_id) references employees(id) on delete set null;
exception when duplicate_object then null;
end $$;

create table if not exists profiles (
  user_id uuid primary key references auth.users(id) on delete cascade,
  employee_id uuid unique references employees(id) on delete set null,
  role app_role not null default 'employee',
  active boolean not null default true
);

create table if not exists contracts (
  id uuid primary key default gen_random_uuid(),
  employee_id uuid not null references employees(id) on delete restrict,
  contract_no text unique not null,
  type text not null,
  start_date date not null,
  end_date date,
  base_salary numeric(15,2) not null check(base_salary >= 0),
  private_file_path text,
  created_at timestamptz not null default now(),
  check(end_date is null or end_date >= start_date)
);

create table if not exists attendance (
  id uuid primary key default gen_random_uuid(),
  employee_id uuid not null references employees(id) on delete cascade,
  work_date date not null,
  check_in timestamptz,
  check_out timestamptz,
  late_minutes int not null default 0 check(late_minutes >= 0),
  early_minutes int not null default 0 check(early_minutes >= 0),
  overtime_minutes int not null default 0 check(overtime_minutes >= 0),
  unique(employee_id,work_date)
);

create table if not exists leave_requests (
  id uuid primary key default gen_random_uuid(),
  employee_id uuid not null references employees(id) on delete cascade,
  type text not null,
  start_date date not null,
  end_date date not null,
  days numeric(5,2) not null check(days > 0),
  reason text,
  status text not null default 'pending' check(status in ('pending','approved','rejected','cancelled')),
  approver_id uuid references employees(id),
  created_at timestamptz not null default now(),
  check(end_date >= start_date)
);

create table if not exists payrolls (
  id uuid primary key default gen_random_uuid(),
  employee_id uuid not null references employees(id) on delete restrict,
  period date not null,
  base_salary numeric(15,2) not null,
  allowance numeric(15,2) not null default 0,
  bonus numeric(15,2) not null default 0,
  deduction numeric(15,2) not null default 0,
  insurance numeric(15,2) not null default 0,
  tax numeric(15,2) not null default 0,
  status text not null default 'draft' check(status in ('draft','approved','paid')),
  unique(employee_id,period)
);

create table if not exists audit_logs (
  id bigint generated always as identity primary key,
  actor_id uuid references auth.users(id),
  action text not null,
  entity_type text not null,
  entity_id text,
  metadata jsonb not null default '{}',
  ip inet,
  created_at timestamptz not null default now()
);

-- current_role is a PostgreSQL keyword. Use an application-prefixed name.
create or replace function app_current_role()
returns app_role language sql stable security definer set search_path=public as $$
  select role from profiles where user_id=auth.uid() and active=true
$$;

create or replace function current_employee_id()
returns uuid language sql stable security definer set search_path=public as $$
  select employee_id from profiles where user_id=auth.uid() and active=true
$$;

alter table employees enable row level security;
alter table contracts enable row level security;
alter table attendance enable row level security;
alter table leave_requests enable row level security;
alter table payrolls enable row level security;
alter table profiles enable row level security;
alter table audit_logs enable row level security;

drop policy if exists employee_read on employees;
create policy employee_read on employees for select
using(app_current_role() in ('super_admin','hr_admin') or id=current_employee_id() or manager_id=current_employee_id());
drop policy if exists employee_hr_write on employees;
create policy employee_hr_write on employees for all
using(app_current_role() in ('super_admin','hr_admin'))
with check(app_current_role() in ('super_admin','hr_admin'));

drop policy if exists contract_read on contracts;
create policy contract_read on contracts for select
using(app_current_role() in ('super_admin','hr_admin') or employee_id=current_employee_id());
drop policy if exists contract_hr_write on contracts;
create policy contract_hr_write on contracts for all
using(app_current_role() in ('super_admin','hr_admin'))
with check(app_current_role() in ('super_admin','hr_admin'));

drop policy if exists attendance_read on attendance;
create policy attendance_read on attendance for select
using(app_current_role() in ('super_admin','hr_admin') or employee_id=current_employee_id() or exists(
  select 1 from employees e where e.id=attendance.employee_id and e.manager_id=current_employee_id()
));
drop policy if exists attendance_self_insert on attendance;
create policy attendance_self_insert on attendance for insert
with check(employee_id=current_employee_id());

drop policy if exists leave_read on leave_requests;
create policy leave_read on leave_requests for select
using(app_current_role() in ('super_admin','hr_admin') or employee_id=current_employee_id() or exists(
  select 1 from employees e where e.id=leave_requests.employee_id and e.manager_id=current_employee_id()
));
drop policy if exists leave_self_create on leave_requests;
create policy leave_self_create on leave_requests for insert
with check(employee_id=current_employee_id());

drop policy if exists payroll_private_read on payrolls;
create policy payroll_private_read on payrolls for select
using(app_current_role() in ('super_admin','hr_admin') or employee_id=current_employee_id());
drop policy if exists payroll_hr_write on payrolls;
create policy payroll_hr_write on payrolls for all
using(app_current_role() in ('super_admin','hr_admin'))
with check(app_current_role() in ('super_admin','hr_admin'));

drop policy if exists profile_self_read on profiles;
create policy profile_self_read on profiles for select
using(user_id=auth.uid() or app_current_role()='super_admin');
drop policy if exists audit_admin_read on audit_logs;
create policy audit_admin_read on audit_logs for select
using(app_current_role()='super_admin');

create index if not exists employee_department_idx on employees(department_id);
create index if not exists attendance_date_idx on attendance(work_date,employee_id);
create index if not exists leave_status_idx on leave_requests(status,created_at);
create index if not exists contract_expiry_idx on contracts(end_date) where end_date is not null;

commit;
