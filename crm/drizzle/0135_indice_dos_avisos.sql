-- 0135 (Pedro, 04/11/2026: "otimizar o CRM, tá demorando a carregar"): /api/avisos roda a cada 10 s em cada aba aberta (o
-- som de lead novo) e procurava por organization_id + updated_at lendo os ~88 mil registros de lead_activities inteiros
-- (45-100 ms por pedido). Aplicado no crmdb em 04/11 (CONCURRENTLY, como o papel crm).
CREATE INDEX CONCURRENTLY IF NOT EXISTS lead_activities_org_updated_idx ON lead_activities (organization_id, updated_at DESC);
