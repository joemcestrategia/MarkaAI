CREATE OR REPLACE VIEW public.admin_appointment_metrics AS
WITH totals AS (
    SELECT 
        COUNT(id) AS total_appointments,
        SUM(total_price) AS total_volume,
        COUNT(DISTINCT shop_id) AS active_shops,
        COUNT(DISTINCT client_id) AS active_clients,
        COUNT(DISTINCT DATE(created_at)) AS days_with_appointments,
        COUNT(DISTINCT TO_CHAR(created_at, 'YYYY-MM')) AS months_with_appointments
    FROM public.appointments
)
SELECT 
    total_appointments,
    COALESCE(total_volume, 0) AS total_volume,
    active_shops,
    active_clients,
    CASE 
        WHEN days_with_appointments > 0 THEN ROUND((total_appointments::NUMERIC / days_with_appointments), 2) 
        ELSE 0 
    END AS avg_daily_appointments,
    CASE 
        WHEN months_with_appointments > 0 THEN ROUND((total_appointments::NUMERIC / months_with_appointments), 2) 
        ELSE 0 
    END AS avg_monthly_appointments
FROM totals;

-- Grant access to authenticated users
GRANT SELECT ON public.admin_appointment_metrics TO authenticated;
GRANT SELECT ON public.admin_appointment_metrics TO service_role;
