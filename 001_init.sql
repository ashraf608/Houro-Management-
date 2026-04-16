-- Enable extensions
create extension if not exists pgcrypto;

create type public.app_role as enum ('admin', 'supervisor', 'accountant', 'worker');
create type public.expense_category as enum ('diesel', 'food', 'salary', 'repair', 'insurance', 'tax', 'rent', 'phone_internet', 'other');
create type public.invoice_status as enum ('paid', 'unpaid', 'missing', 'overdue');
create type public.operation_type as enum ('battery_swap', 'pickup', 'deployment', 'charging', 'rebalancing', 'maintenance');
create type public.locale_code as enum ('de', 'ar');

create table public.companies (
  id uuid primary key default gen_random_uuid(),
  name text not null unique,
  created_at timestamptz not null default now()
);

create table public.cities (
  id uuid primary key default gen_random_uuid(),
  name text not null unique,
  created_at timestamptz not null default now()
);

create table public.workers (
  id uuid primary key default gen_random_uuid(),
  full_name text not null,
  phone text,
  email text,
  company_id uuid references public.companies(id) on delete set null,
  active boolean not null default true,
  created_at timestamptz not null default now()
);

create table public.vehicles (
  id uuid primary key default gen_random_uuid(),
  plate_number text not null unique,
  model text not null,
  city_id uuid references public.cities(id) on delete set null,
  insurance_expiry_date date,
  next_maintenance_date date,
  active boolean not null default true,
  created_at timestamptz not null default now()
);

create table public.profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  full_name text not null,
  role public.app_role not null default 'worker',
  language public.locale_code not null default 'de',
  worker_id uuid references public.workers(id) on delete set null,
  created_at timestamptz not null default now()
);

create table public.operations (
  id uuid primary key default gen_random_uuid(),
  date date not null,
  worker_id uuid not null references public.workers(id) on delete restrict,
  company_id uuid not null references public.companies(id) on delete restrict,
  city_id uuid not null references public.cities(id) on delete restrict,
  vehicle_id uuid references public.vehicles(id) on delete set null,
  operation_type public.operation_type not null,
  quantity numeric(12,2) not null check (quantity > 0),
  unit_price numeric(12,2) not null check (unit_price >= 0),
  total_amount numeric(12,2) generated always as (quantity * unit_price) stored,
  proof_file_path text,
  notes text,
  created_by uuid references auth.users(id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table public.expenses (
  id uuid primary key default gen_random_uuid(),
  date date not null,
  category public.expense_category not null,
  company_id uuid references public.companies(id) on delete set null,
  city_id uuid references public.cities(id) on delete set null,
  worker_id uuid references public.workers(id) on delete set null,
  vehicle_id uuid references public.vehicles(id) on delete set null,
  amount numeric(12,2) not null check (amount >= 0),
  has_invoice boolean not null default false,
  invoice_file_path text,
  notes text,
  created_by uuid references auth.users(id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table public.revenues (
  id uuid primary key default gen_random_uuid(),
  date date not null,
  company_id uuid not null references public.companies(id) on delete restrict,
  city_id uuid not null references public.cities(id) on delete restrict,
  operation_id uuid references public.operations(id) on delete set null,
  description text,
  quantity numeric(12,2) not null default 1 check (quantity > 0),
  unit_price numeric(12,2) not null check (unit_price >= 0),
  total_amount numeric(12,2) generated always as (quantity * unit_price) stored,
  invoice_id uuid,
  created_by uuid references auth.users(id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table public.invoices (
  id uuid primary key default gen_random_uuid(),
  invoice_number text,
  company_id uuid references public.companies(id) on delete set null,
  worker_id uuid references public.workers(id) on delete set null,
  vehicle_id uuid references public.vehicles(id) on delete set null,
  issue_date date,
  due_date date,
  amount numeric(12,2) not null default 0,
  status public.invoice_status not null default 'unpaid',
  file_path text,
  notes text,
  created_by uuid references auth.users(id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

alter table public.revenues add constraint revenues_invoice_id_fkey foreign key (invoice_id) references public.invoices(id) on delete set null;

create table public.app_settings (
  id uuid primary key default gen_random_uuid(),
  company_name text not null default 'Houro Logistics ERP',
  logo_file_path text,
  currency_code text not null default 'EUR',
  default_language public.locale_code not null default 'de',
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create or replace function public.current_app_role()
returns public.app_role
language sql
stable
as $$
  select coalesce((select role from public.profiles where id = auth.uid()), 'worker'::public.app_role);
$$;

create or replace function public.current_worker_id()
returns uuid
language sql
stable
as $$
  select worker_id from public.profiles where id = auth.uid();
$$;

create or replace function public.touch_updated_at()
returns trigger
language plpgsql
as $$
begin
  new.updated_at = now();
  return new;
end;
$$;

create trigger trg_operations_updated_at before update on public.operations for each row execute function public.touch_updated_at();
create trigger trg_expenses_updated_at before update on public.expenses for each row execute function public.touch_updated_at();
create trigger trg_revenues_updated_at before update on public.revenues for each row execute function public.touch_updated_at();
create trigger trg_invoices_updated_at before update on public.invoices for each row execute function public.touch_updated_at();
create trigger trg_settings_updated_at before update on public.app_settings for each row execute function public.touch_updated_at();

create or replace function public.refresh_overdue_invoices()
returns void
language sql
security definer
as $$
  update public.invoices
     set status = 'overdue'
   where status in ('unpaid', 'missing')
     and due_date < current_date;
$$;

create or replace function public.get_dashboard_kpis()
returns table (
  today_revenue numeric,
  today_expense numeric,
  net_profit numeric,
  operations_count bigint,
  missing_invoices bigint,
  overdue_invoices bigint
)
language sql
security definer
as $$
  select
    coalesce((select sum(total_amount) from public.revenues where date = current_date), 0) as today_revenue,
    coalesce((select sum(amount) from public.expenses where date = current_date), 0) as today_expense,
    coalesce((select sum(total_amount) from public.revenues where date = current_date), 0)
      - coalesce((select sum(amount) from public.expenses where date = current_date), 0) as net_profit,
    coalesce((select count(*) from public.operations where date = current_date), 0) as operations_count,
    coalesce((select count(*) from public.expenses where has_invoice = false), 0) as missing_invoices,
    coalesce((select count(*) from public.invoices where status = 'overdue'), 0) as overdue_invoices;
$$;

create or replace function public.get_vehicle_alerts()
returns table (
  vehicle_id uuid,
  plate_number text,
  alert_type text,
  alert_date date
)
language sql
security definer
as $$
  select id, plate_number, 'insurance_expiry'::text, insurance_expiry_date
    from public.vehicles
   where insurance_expiry_date is not null and insurance_expiry_date <= current_date + interval '30 day'
  union all
  select id, plate_number, 'maintenance_due'::text, next_maintenance_date
    from public.vehicles
   where next_maintenance_date is not null and next_maintenance_date <= current_date + interval '14 day';
$$;

-- Storage buckets (run in Supabase SQL editor if needed)
insert into storage.buckets (id, name, public) values ('invoice-files', 'invoice-files', false)
on conflict (id) do nothing;
insert into storage.buckets (id, name, public) values ('operation-proofs', 'operation-proofs', false)
on conflict (id) do nothing;

alter table public.profiles enable row level security;
alter table public.workers enable row level security;
alter table public.vehicles enable row level security;
alter table public.cities enable row level security;
alter table public.companies enable row level security;
alter table public.operations enable row level security;
alter table public.expenses enable row level security;
alter table public.revenues enable row level security;
alter table public.invoices enable row level security;
alter table public.app_settings enable row level security;

-- Read policies
create policy "profiles_select_self_or_admin" on public.profiles for select using (id = auth.uid() or public.current_app_role() = 'admin');
create policy "workers_read_all_for_staff" on public.workers for select using (public.current_app_role() in ('admin', 'supervisor', 'accountant'));
create policy "workers_read_self_mapped" on public.workers for select using (id = public.current_worker_id());
create policy "vehicles_read_all_for_staff" on public.vehicles for select using (public.current_app_role() in ('admin', 'supervisor', 'accountant'));
create policy "cities_read_all_authenticated" on public.cities for select to authenticated using (true);
create policy "companies_read_all_authenticated" on public.companies for select to authenticated using (true);
create policy "operations_read_staff_all" on public.operations for select using (public.current_app_role() in ('admin', 'supervisor', 'accountant'));
create policy "operations_read_worker_own" on public.operations for select using (worker_id = public.current_worker_id());
create policy "expenses_read_staff_all" on public.expenses for select using (public.current_app_role() in ('admin', 'supervisor', 'accountant'));
create policy "revenues_read_staff_all" on public.revenues for select using (public.current_app_role() in ('admin', 'supervisor', 'accountant'));
create policy "invoices_read_staff_all" on public.invoices for select using (public.current_app_role() in ('admin', 'supervisor', 'accountant'));
create policy "settings_read_admin" on public.app_settings for select using (public.current_app_role() = 'admin');

-- Insert/Update/Delete policies
create policy "operations_insert_staff" on public.operations for insert with check (public.current_app_role() in ('admin', 'supervisor'));
create policy "operations_insert_worker_own" on public.operations for insert with check (public.current_app_role() = 'worker' and worker_id = public.current_worker_id());
create policy "operations_update_staff" on public.operations for update using (public.current_app_role() in ('admin', 'supervisor'));
create policy "operations_delete_admin" on public.operations for delete using (public.current_app_role() = 'admin');

create policy "expenses_manage_staff" on public.expenses for all using (public.current_app_role() in ('admin', 'supervisor', 'accountant')) with check (public.current_app_role() in ('admin', 'supervisor', 'accountant'));
create policy "revenues_manage_staff" on public.revenues for all using (public.current_app_role() in ('admin', 'supervisor', 'accountant')) with check (public.current_app_role() in ('admin', 'supervisor', 'accountant'));
create policy "workers_manage_admin_supervisor" on public.workers for all using (public.current_app_role() in ('admin', 'supervisor')) with check (public.current_app_role() in ('admin', 'supervisor'));
create policy "vehicles_manage_admin_supervisor" on public.vehicles for all using (public.current_app_role() in ('admin', 'supervisor')) with check (public.current_app_role() in ('admin', 'supervisor'));
create policy "cities_manage_admin" on public.cities for all using (public.current_app_role() = 'admin') with check (public.current_app_role() = 'admin');
create policy "companies_manage_admin" on public.companies for all using (public.current_app_role() = 'admin') with check (public.current_app_role() = 'admin');
create policy "invoices_manage_staff" on public.invoices for all using (public.current_app_role() in ('admin', 'accountant', 'supervisor')) with check (public.current_app_role() in ('admin', 'accountant', 'supervisor'));
create policy "settings_manage_admin" on public.app_settings for all using (public.current_app_role() = 'admin') with check (public.current_app_role() = 'admin');

-- Storage policies
create policy "invoice_files_staff_only" on storage.objects for all to authenticated
using (bucket_id = 'invoice-files' and public.current_app_role() in ('admin', 'supervisor', 'accountant'))
with check (bucket_id = 'invoice-files' and public.current_app_role() in ('admin', 'supervisor', 'accountant'));

create policy "operation_proofs_staff_or_worker" on storage.objects for all to authenticated
using (
  bucket_id = 'operation-proofs'
  and public.current_app_role() in ('admin', 'supervisor', 'accountant', 'worker')
)
with check (
  bucket_id = 'operation-proofs'
  and public.current_app_role() in ('admin', 'supervisor', 'accountant', 'worker')
);
