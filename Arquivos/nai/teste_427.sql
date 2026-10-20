\pset pager off
SET ROLE nay_disparo;
SELECT jsonb_array_length(crm_visitantes()) AS visitas_total, jsonb_array_length(crm_visitantes(date_trunc('month', now())::date, now()::date)) AS no_mes;
SELECT x->>'origem' o, x->>'quando' q, x->>'imovel' im, x->>'corretor' c, x->>'corretor_telefone' t, x->>'cliente' cl
  FROM jsonb_array_elements(crm_visitantes()) x LIMIT 5;
SELECT crm_olx_busca_parceiro_abrir('{"telefone": "92900002222", "finalidade": "venda", "teto": 500000, "bairros": ["Flores"],
  "olx": {"tipos": ["apartamento"], "quartos": [2, 3], "condominio": ["elevador"], "anunciante": "p", "vazio": null}}', 'ensaio') AS abriu;
RESET ROLE;
SELECT b.filtros->'olx' FROM privado.olx_busca_parceiro b JOIN privado.olx_lead_whatsapp l ON l.id = b.lead WHERE l.telefone = '92900002222';
