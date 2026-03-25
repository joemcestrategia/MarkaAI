// Common logic for Affiliate System
import { createClient } from 'supabase';

export const genCouponCode = (name: string): string => {
  const prefix = name.substring(0, 3).toUpperCase().padEnd(3, 'X');
  const random = Math.floor(1000 + Math.random() * 9000);
  return `${prefix}${random}`;
};

export const getAffiliateConfig = async (supabase: any) => {
  const { data, error } = await supabase
    .from('affiliate_program_config')
    .select('*')
    .limit(1)
    .single();
  
  if (error) throw error;
  return data;
};
