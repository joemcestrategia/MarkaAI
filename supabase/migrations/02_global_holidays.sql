-- Create global_holidays table
CREATE TABLE IF NOT EXISTS public.global_holidays (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    date DATE NOT NULL UNIQUE,
    name TEXT NOT NULL,
    description TEXT,
    is_platform_closed BOOLEAN DEFAULT true,
    created_at TIMESTAMPTZ DEFAULT now(),
    created_by UUID REFERENCES auth.users(id)
);

-- RLS for global_holidays
ALTER TABLE public.global_holidays ENABLE ROW LEVEL SECURITY;

-- Everyone can read global holidays
CREATE POLICY "Allow public read global_holidays" 
ON public.global_holidays FOR SELECT 
TO authenticated, anon 
USING (true);

-- Only admins can manage global holidays
CREATE POLICY "Allow admin manage global_holidays" 
ON public.global_holidays FOR ALL 
TO authenticated 
USING (
    EXISTS (
        SELECT 1 FROM public.users 
        WHERE id = auth.uid() AND role = 'admin'
    )
);
