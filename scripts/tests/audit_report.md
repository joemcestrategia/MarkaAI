# Resultado da Auditoria de Migrations Pendentes

## ðŸŸ¢ CONFIRMADAS
Essas migrations tÃªm estruturas que jÃ¡ existem no banco (seguro marcar como applied).
- 209_add_employee_user_id.sql
- 209_isolate_gcal_sync.sql
- 213_add_wa_reminder_message_id.sql
- 215_fix_public_rls_select_leak.sql
- 220_add_client_geolocation.sql
- 221_add_lat_lng_to_shops.sql
- 20260604_fix_plan_limits_and_boost.sql
- 20260617000000_add_pago_em_to_appointments.sql

## ðŸ”´ SUSPEITAS
Essas migrations descrevem tabelas ou colunas que NÃƒO existem no banco atual (NÃƒO marcar como applied).
- 20260323_affiliate_system.sql
- 20260422_whatsapp_qr_codes.sql
- 20260423_meta_whatsapp_config.sql
- 20260703154500_mp_processed_payments.sql
- 20260703194848_add_refund_fields.sql
- 20260703201117_add_cancellation_note.sql

## ðŸŸ¡ AMBÃGUAS
Essas migrations nÃ£o criam tabelas nem adicionam colunas explÃ­citas no formato esperado. Geralmente sÃ£o triggers, RPCs, policies ou inserts.
- 208_sync_gcal_webhook_trigger.sql
- 210_fix_availability_rpcs_types.sql
- 211_fix_work_day_trigger_type.sql
- 212_fix_birthday_trigger_type.sql
- 214_fix_role_protection_policy.sql
- 216_fix_visitor_profiles_rpc.sql
- 217_fix_remaining_public_rls.sql
- 218_enable_rls_categories_plans_shops.sql
- 219_fix_shops_insert_rls.sql
- 222_update_user_geolocation_rpc.sql
- 20260422_whatsapp_cron.sql
- 20260422_whatsapp_integration.sql
- 20260423_fix_role_reset_on_oauth.sql
