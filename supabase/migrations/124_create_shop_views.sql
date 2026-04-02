-- Create shop_views table
CREATE TABLE IF NOT EXISTS public.shop_views (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID REFERENCES auth.users(id) ON DELETE CASCADE,
    shop_id UUID REFERENCES public.shops(id) ON DELETE CASCADE,
    viewed_at TIMESTAMPTZ DEFAULT now()
);

-- Enable RLS
ALTER TABLE public.shop_views ENABLE ROW LEVEL SECURITY;

-- Policy: Shop owners can see views for their own shop
-- Note: Checking if shop.user_id = auth.uid()
CREATE POLICY "Shop owners can see views for their shop" ON public.shop_views
    FOR SELECT USING (
        EXISTS (
            SELECT 1 FROM public.shops
            WHERE shops.id = shop_views.shop_id
            AND shops.user_id = auth.uid()
        )
    );

-- Policy: Authenticated users can insert views
CREATE POLICY "Authenticated users can insert views" ON public.shop_views
    FOR INSERT WITH CHECK (auth.uid() = user_id);

-- Performance Index
CREATE INDEX IF NOT EXISTS idx_shop_views_shop_id ON public.shop_views(shop_id);
CREATE INDEX IF NOT EXISTS idx_shop_views_user_id ON public.shop_views(user_id);
CREATE INDEX IF NOT EXISTS idx_shop_views_viewed_at ON public.shop_views(viewed_at DESC);
