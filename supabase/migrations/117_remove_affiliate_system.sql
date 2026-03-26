-- MarkaAI - Remove Affiliate System
-- Created: 2026-03-26

-- Drop triggers if they exist
DROP TRIGGER IF EXISTS affiliates_updated_at ON affiliates;
DROP TRIGGER IF EXISTS referrals_updated_at ON affiliate_referrals;
DROP TRIGGER IF EXISTS commissions_updated_at ON affiliate_commissions;

-- Drop Tables (Dependencies first: clicks, commissions, referrals depend on affiliates)
DROP TABLE IF EXISTS affiliate_clicks;
DROP TABLE IF EXISTS affiliate_commissions;
DROP TABLE IF EXISTS affiliate_referrals;
DROP TABLE IF EXISTS affiliates;
DROP TABLE IF EXISTS affiliate_program_config;

-- Note: The function update_updated_at_column might be used by other tables, 
-- so we keep it unless we are sure it was only for affiliates. 
-- In this project, it seems to be a common utility.

-- RLS Policies are automatically dropped when the table is dropped.
