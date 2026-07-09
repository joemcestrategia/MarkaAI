import { getPlanIdFromPriceId, getPriceIdFromPlanId } from "../../supabase/functions/_shared/plan-mapping.ts";

Deno.test("plan-mapping: getPlanIdFromPriceId returns correct values", () => {
  // Correct valid mappings
  if (getPlanIdFromPriceId('price_1T98YSFzh8r5AMGzkMdAH2eq') !== 'starter') {
    throw new Error("Failed: price_1T98YSFzh8r5AMGzkMdAH2eq should map to starter");
  }
  if (getPlanIdFromPriceId('price_1T98ZPFzh8r5AMGzUHfVZRfC') !== 'plus') {
    throw new Error("Failed: price_1T98ZPFzh8r5AMGzUHfVZRfC should map to plus");
  }
  if (getPlanIdFromPriceId('price_1T98aHFzh8r5AMGzlgvM6eSZ') !== 'pro') {
    throw new Error("Failed: price_1T98aHFzh8r5AMGzlgvM6eSZ should map to pro");
  }
  
  // Unknown prices should return null
  if (getPlanIdFromPriceId('price_unknown_abc123') !== null) {
    throw new Error("Failed: unknown price should return null");
  }
  
  // Edge cases (null/undefined)
  if (getPlanIdFromPriceId(null) !== null) {
    throw new Error("Failed: null should return null");
  }
  if (getPlanIdFromPriceId(undefined) !== null) {
    throw new Error("Failed: undefined should return null");
  }
});

Deno.test("plan-mapping: getPriceIdFromPlanId returns correct values", () => {
  // Correct valid mappings
  if (getPriceIdFromPlanId('starter') !== 'price_1T98YSFzh8r5AMGzkMdAH2eq') {
    throw new Error("Failed: starter should map to price_1T98YSFzh8r5AMGzkMdAH2eq");
  }
  if (getPriceIdFromPlanId('plus') !== 'price_1T98ZPFzh8r5AMGzUHfVZRfC') {
    throw new Error("Failed: plus should map to price_1T98ZPFzh8r5AMGzUHfVZRfC");
  }
  if (getPriceIdFromPlanId('pro') !== 'price_1T98aHFzh8r5AMGzlgvM6eSZ') {
    throw new Error("Failed: pro should map to price_1T98aHFzh8r5AMGzlgvM6eSZ");
  }

  // Alias
  if (getPriceIdFromPlanId('start') !== 'price_1T98YSFzh8r5AMGzkMdAH2eq') {
    throw new Error("Failed: start should map to price_1T98YSFzh8r5AMGzkMdAH2eq");
  }
  
  // Unknown plans
  if (getPriceIdFromPlanId('unknown_plan') !== null) {
    throw new Error("Failed: unknown plan should return null");
  }

  // Edge cases
  if (getPriceIdFromPlanId(null) !== null) {
    throw new Error("Failed: null should return null");
  }
});
