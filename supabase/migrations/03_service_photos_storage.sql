-- Create services storage bucket
INSERT INTO storage.buckets (id, name, public)
VALUES ('services', 'services', true)
ON CONFLICT (id) DO NOTHING;

-- RLS Policies for services bucket

-- 1. Allow public read access to service photos
CREATE POLICY "Public Access"
ON storage.objects FOR SELECT
USING (bucket_id = 'services');

-- 2. Allow authenticated users to upload service photos to their own shop folder
CREATE POLICY "Allow shop upload"
ON storage.objects FOR INSERT
TO authenticated
WITH CHECK (
    bucket_id = 'services' AND
    (storage.foldername(name))[1] = 'services' AND
    EXISTS (
        SELECT 1 FROM public.users
        WHERE id = auth.uid() AND (role = 'admin' OR shop_id = (storage.foldername(name))[2])
    )
);

-- 3. Allow shops to delete/update their own service photos
CREATE POLICY "Allow shop manage"
ON storage.objects FOR ALL
TO authenticated
USING (
    bucket_id = 'services' AND
    (storage.foldername(name))[1] = 'services' AND
    EXISTS (
        SELECT 1 FROM public.users
        WHERE id = auth.uid() AND (role = 'admin' OR shop_id = (storage.foldername(name))[2])
    )
);
