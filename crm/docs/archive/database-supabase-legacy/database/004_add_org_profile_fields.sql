-- Migration to add organization profile fields
ALTER TABLE public.organizations
ADD COLUMN logo_url text,
ADD COLUMN corporate_email text,
ADD COLUMN phone text,
ADD COLUMN website text,
ADD COLUMN foundation_date date;
