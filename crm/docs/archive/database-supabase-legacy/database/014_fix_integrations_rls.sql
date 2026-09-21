-- Fixes RLS for integrations so normal users can connect WhatsApp Lite
DROP POLICY IF EXISTS "manage_integrations: write integrations" ON public.integrations;

CREATE POLICY "manage_integrations: write integrations" ON public.integrations
FOR ALL
USING (public.is_org_member(organization_id))
WITH CHECK (public.is_org_member(organization_id));
