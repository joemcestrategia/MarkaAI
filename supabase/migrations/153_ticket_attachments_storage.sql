-- ============================================================
-- Migration 153: Ticket Attachments Storage Bucket + columns
-- ============================================================

-- 1) Add attachments JSONB column to support_tickets (for initial screenshots)
ALTER TABLE support_tickets ADD COLUMN IF NOT EXISTS attachments JSONB DEFAULT '[]'::jsonb;

-- 2) Create the storage bucket for ticket attachments
INSERT INTO storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
VALUES (
  'ticket-attachments',
  'ticket-attachments',
  true,
  5242880, -- 5 MB
  ARRAY['image/jpeg','image/png','image/gif','image/webp','image/heic','image/heif']
)
ON CONFLICT (id) DO UPDATE SET
  public = true,
  file_size_limit = 5242880,
  allowed_mime_types = ARRAY['image/jpeg','image/png','image/gif','image/webp','image/heic','image/heif'];

-- 3) RLS policies for storage
-- Allow authenticated users to upload
CREATE POLICY "Authenticated users can upload ticket attachments"
ON storage.objects FOR INSERT TO authenticated
WITH CHECK (bucket_id = 'ticket-attachments');

-- Allow public read (bucket is public)
CREATE POLICY "Anyone can read ticket attachments"
ON storage.objects FOR SELECT TO public
USING (bucket_id = 'ticket-attachments');

-- Allow admins to delete
CREATE POLICY "Admins can delete ticket attachments"
ON storage.objects FOR DELETE TO authenticated
USING (
  bucket_id = 'ticket-attachments'
  AND EXISTS (SELECT 1 FROM public.users WHERE id = auth.uid() AND role = 'admin')
);
