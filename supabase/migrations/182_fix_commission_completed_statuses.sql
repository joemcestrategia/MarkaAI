-- Migration 182: Atualiza view de comissões para incluir status "finalizado" e "realizado"
-- Antes: apenas status 'concluido' gerava comissão
-- Agora: 'concluido', 'finalizado' e 'realizado' geram comissão

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
where a.status in ('concluido', 'finalizado', 'realizado');
