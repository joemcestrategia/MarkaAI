-- 158_commission_rules_and_view.sql

create table if not exists commission_rules (
  id uuid primary key default gen_random_uuid(),
  shop_id text not null references shops(id) on delete cascade,
  employee_id text references employees(id) on delete cascade,
  service_id text references services(id) on delete cascade,
  commission_type text not null check (commission_type in ('percentage', 'fixed')),
  commission_value numeric(10,2) not null,
  applies_to text not null default 'all'
    check (applies_to in ('all', 'specific_service', 'specific_employee')),
  active boolean not null default true,
  created_at timestamptz default now(),
  updated_at timestamptz default now()
);

alter table commission_rules enable row level security;

do $$
begin
  if not exists (
    select 1
    from pg_policies
    where tablename = 'commission_rules'
    and policyname = 'Shop Manage commission_rules'
  ) then
    create policy "Shop Manage commission_rules" on public.commission_rules for all to authenticated 
    using (shop_id in (select shop_id from public.users where id = auth.uid()) or (select role from public.users where id = auth.uid()) = 'admin');
  end if;
end $$;

drop view if exists vw_commission_summary;

create or replace view vw_commission_summary as
select
  a.id as appointment_id,
  a.shop_id,
  a.professional_id as employee_id,
  p.name as employee_name,
  p.photo_url as employee_avatar,
  p.commission_percent as employee_commission_percent,
  s.id as service_id,
  s.name as service_name,
  coalesce(a.total_price, a.total_value, 0) as service_price,
  a.scheduled_at,
  date_trunc('month', a.scheduled_at) as month_reference,
  coalesce(cr.commission_type, 'percentage') as commission_type,
  coalesce(cr.commission_value, p.commission_percent, 0) as commission_value,
  case
    when coalesce(cr.commission_type, 'percentage') = 'percentage'
      then round((coalesce(a.total_price, a.total_value, 0) * coalesce(cr.commission_value, p.commission_percent, 0) / 100)::numeric, 2)
    else coalesce(cr.commission_value, p.commission_percent, 0)
  end as commission_amount
from appointments a
join services s on s.id = a.service_id
join employees p on p.id = a.professional_id
left join commission_rules cr
  on cr.shop_id = a.shop_id
  and cr.active = true
  and (
    (cr.applies_to = 'specific_employee' and cr.employee_id = a.professional_id)
    or (cr.applies_to = 'specific_service' and cr.service_id = a.service_id)
    or (cr.applies_to = 'all')
  )
where a.status = 'concluido';
