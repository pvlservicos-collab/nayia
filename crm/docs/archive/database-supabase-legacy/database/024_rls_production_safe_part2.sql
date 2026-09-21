-- =========================================================
-- PARTE 2: SCRIPT DE SEGURANÇA PARA AS DEMAIS TABELAS
-- (Campos Customizados, Leads, Integrações, Tags)
-- =========================================================

-- Limpando Políticas Antigas das demais tabelas-chave
DROP POLICY IF EXISTS "Members can view custom field definitions" ON public.custom_field_definitions;
DROP POLICY IF EXISTS "Members can insert custom field definitions" ON public.custom_field_definitions;
DROP POLICY IF EXISTS "Members can update custom field definitions" ON public.custom_field_definitions;
DROP POLICY IF EXISTS "Members can delete custom field definitions" ON public.custom_field_definitions;

DROP POLICY IF EXISTS "Members can view custom field values" ON public.custom_field_index_values;
DROP POLICY IF EXISTS "Members can insert custom field values" ON public.custom_field_index_values;
DROP POLICY IF EXISTS "Members can update custom field values" ON public.custom_field_index_values;
DROP POLICY IF EXISTS "Members can delete custom field values" ON public.custom_field_index_values;

DROP POLICY IF EXISTS "Members can view integrations" ON public.integrations;
DROP POLICY IF EXISTS "Members can insert integrations" ON public.integrations;
DROP POLICY IF EXISTS "Members can update integrations" ON public.integrations;
DROP POLICY IF EXISTS "Members can delete integrations" ON public.integrations;

DROP POLICY IF EXISTS "Members can view leads" ON public.leads;
DROP POLICY IF EXISTS "Members can insert leads" ON public.leads;
DROP POLICY IF EXISTS "Members can update leads" ON public.leads;
DROP POLICY IF EXISTS "Members can delete leads" ON public.leads;

DROP POLICY IF EXISTS "Members can view lead activities" ON public.lead_activities;
DROP POLICY IF EXISTS "Members can insert lead activities" ON public.lead_activities;
DROP POLICY IF EXISTS "Members can update lead activities" ON public.lead_activities;
DROP POLICY IF EXISTS "Members can delete lead activities" ON public.lead_activities;

DROP POLICY IF EXISTS "Members can view lead tags" ON public.lead_tags;
DROP POLICY IF EXISTS "Members can insert lead tags" ON public.lead_tags;
DROP POLICY IF EXISTS "Members can delete lead tags" ON public.lead_tags;

DROP POLICY IF EXISTS "Members can view tags" ON public.tags;
DROP POLICY IF EXISTS "Members can insert tags" ON public.tags;
DROP POLICY IF EXISTS "Members can update tags" ON public.tags;
DROP POLICY IF EXISTS "Members can delete tags" ON public.tags;


-- RECRIANDO COM A ARQUITETURA LIVRE DE LOOP (auth_get_user_orgs)

-- ================ CUSTOM FIELD DEFINITIONS ================
ALTER TABLE public.custom_field_definitions ENABLE ROW LEVEL SECURITY;
CREATE POLICY "CF Def view rule" ON public.custom_field_definitions FOR SELECT USING (organization_id IN (SELECT public.auth_get_user_orgs()) OR public.auth_is_superadmin());
CREATE POLICY "CF Def insert rule" ON public.custom_field_definitions FOR INSERT WITH CHECK (organization_id IN (SELECT public.auth_get_user_orgs()) OR public.auth_is_superadmin());
CREATE POLICY "CF Def update rule" ON public.custom_field_definitions FOR UPDATE USING (organization_id IN (SELECT public.auth_get_user_orgs()) OR public.auth_is_superadmin());
CREATE POLICY "CF Def delete rule" ON public.custom_field_definitions FOR DELETE USING (organization_id IN (SELECT public.auth_get_user_orgs()) OR public.auth_is_superadmin());

-- ================ INTEGRATIONS ================
ALTER TABLE public.integrations ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Integrations view rule" ON public.integrations FOR SELECT USING (organization_id IN (SELECT public.auth_get_user_orgs()) OR public.auth_is_superadmin());
CREATE POLICY "Integrations insert rule" ON public.integrations FOR INSERT WITH CHECK (organization_id IN (SELECT public.auth_get_user_orgs()) OR public.auth_is_superadmin());
CREATE POLICY "Integrations update rule" ON public.integrations FOR UPDATE USING (organization_id IN (SELECT public.auth_get_user_orgs()) OR public.auth_is_superadmin());
CREATE POLICY "Integrations delete rule" ON public.integrations FOR DELETE USING (organization_id IN (SELECT public.auth_get_user_orgs()) OR public.auth_is_superadmin());

-- ================ LEADS ================
ALTER TABLE public.leads ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Leads view rule" ON public.leads FOR SELECT USING (organization_id IN (SELECT public.auth_get_user_orgs()) OR public.auth_is_superadmin());
CREATE POLICY "Leads insert rule" ON public.leads FOR INSERT WITH CHECK (organization_id IN (SELECT public.auth_get_user_orgs()) OR public.auth_is_superadmin());
CREATE POLICY "Leads update rule" ON public.leads FOR UPDATE USING (organization_id IN (SELECT public.auth_get_user_orgs()) OR public.auth_is_superadmin());
CREATE POLICY "Leads delete rule" ON public.leads FOR DELETE USING (organization_id IN (SELECT public.auth_get_user_orgs()) OR public.auth_is_superadmin());

-- ================ CUSTOM FIELD VALUES ================
ALTER TABLE public.custom_field_index_values ENABLE ROW LEVEL SECURITY;
CREATE POLICY "CF Value view rule" ON public.custom_field_index_values FOR SELECT USING (
  lead_id IN (SELECT id FROM public.leads WHERE organization_id IN (SELECT public.auth_get_user_orgs()) OR public.auth_is_superadmin())
);
CREATE POLICY "CF Value insert rule" ON public.custom_field_index_values FOR INSERT WITH CHECK (
  lead_id IN (SELECT id FROM public.leads WHERE organization_id IN (SELECT public.auth_get_user_orgs()) OR public.auth_is_superadmin())
);
CREATE POLICY "CF Value update rule" ON public.custom_field_index_values FOR UPDATE USING (
  lead_id IN (SELECT id FROM public.leads WHERE organization_id IN (SELECT public.auth_get_user_orgs()) OR public.auth_is_superadmin())
);
CREATE POLICY "CF Value delete rule" ON public.custom_field_index_values FOR DELETE USING (
  lead_id IN (SELECT id FROM public.leads WHERE organization_id IN (SELECT public.auth_get_user_orgs()) OR public.auth_is_superadmin())
);

-- ================ LEAD ACTIVITIES ================
ALTER TABLE public.lead_activities ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Activities view rule" ON public.lead_activities FOR SELECT USING (
  lead_id IN (SELECT id FROM public.leads WHERE organization_id IN (SELECT public.auth_get_user_orgs()) OR public.auth_is_superadmin())
);
CREATE POLICY "Activities insert rule" ON public.lead_activities FOR INSERT WITH CHECK (
  lead_id IN (SELECT id FROM public.leads WHERE organization_id IN (SELECT public.auth_get_user_orgs()) OR public.auth_is_superadmin())
);
CREATE POLICY "Activities update rule" ON public.lead_activities FOR UPDATE USING (
  lead_id IN (SELECT id FROM public.leads WHERE organization_id IN (SELECT public.auth_get_user_orgs()) OR public.auth_is_superadmin())
);
CREATE POLICY "Activities delete rule" ON public.lead_activities FOR DELETE USING (
  lead_id IN (SELECT id FROM public.leads WHERE organization_id IN (SELECT public.auth_get_user_orgs()) OR public.auth_is_superadmin())
);

-- ================ TAGS & LEAD TAGS ================
ALTER TABLE public.tags ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Tags view rule" ON public.tags FOR SELECT USING (organization_id IN (SELECT public.auth_get_user_orgs()) OR public.auth_is_superadmin());
CREATE POLICY "Tags insert rule" ON public.tags FOR INSERT WITH CHECK (organization_id IN (SELECT public.auth_get_user_orgs()) OR public.auth_is_superadmin());
CREATE POLICY "Tags update rule" ON public.tags FOR UPDATE USING (organization_id IN (SELECT public.auth_get_user_orgs()) OR public.auth_is_superadmin());
CREATE POLICY "Tags delete rule" ON public.tags FOR DELETE USING (organization_id IN (SELECT public.auth_get_user_orgs()) OR public.auth_is_superadmin());

ALTER TABLE public.lead_tags ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Lead Tags view rule" ON public.lead_tags FOR SELECT USING (
  lead_id IN (SELECT id FROM public.leads WHERE organization_id IN (SELECT public.auth_get_user_orgs()) OR public.auth_is_superadmin())
);
CREATE POLICY "Lead Tags insert rule" ON public.lead_tags FOR INSERT WITH CHECK (
  lead_id IN (SELECT id FROM public.leads WHERE organization_id IN (SELECT public.auth_get_user_orgs()) OR public.auth_is_superadmin())
);
CREATE POLICY "Lead Tags delete rule" ON public.lead_tags FOR DELETE USING (
  lead_id IN (SELECT id FROM public.leads WHERE organization_id IN (SELECT public.auth_get_user_orgs()) OR public.auth_is_superadmin())
);
