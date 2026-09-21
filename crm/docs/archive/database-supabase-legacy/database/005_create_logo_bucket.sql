-- Migration to create the organization logos storage bucket
insert into storage.buckets (id, name, public)
values ('org-logos', 'org-logos', true)
on conflict (id) do nothing;

-- Set up RLS for the bucket
CREATE POLICY "Logos are publicly accessible"
ON storage.objects FOR SELECT
USING ( bucket_id = 'org-logos' );

CREATE POLICY "Users can upload logos to their organization"
ON storage.objects FOR INSERT
WITH CHECK (
    bucket_id = 'org-logos' 
    AND auth.role() = 'authenticated'
    -- Note: More complex RLS can be added here to restrict uploads to specific organization folders based on member roles
);

CREATE POLICY "Users can update their organization logos"
ON storage.objects FOR UPDATE
WITH CHECK (
    bucket_id = 'org-logos' 
    AND auth.role() = 'authenticated'
);

CREATE POLICY "Users can delete their organization logos"
ON storage.objects FOR DELETE
USING (
    bucket_id = 'org-logos' 
    AND auth.role() = 'authenticated'
);
