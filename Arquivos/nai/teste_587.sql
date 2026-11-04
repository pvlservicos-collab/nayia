-- 587: os nomes saem (condomínio, ou tipo e bairro) e a visita da Nay Leads cancela
SELECT 'nomes' caso, codigo, nome FROM crm_imoveis_nomes(ARRAY[840, 3166, 887, 1485, 9131]) ORDER BY codigo;
SELECT 'nome vazio' caso, count(*) AS n FROM crm_imoveis_nomes((SELECT array_agg(codigo) FROM imoveis)) WHERE nome IS NULL;
SELECT 'cancela' caso, c.* FROM (SELECT id FROM privado.olx_visita WHERE estado = 'confirmada' ORDER BY id DESC LIMIT 1) v,
       LATERAL crm_visita_leads_cancelar(v.id, 'teste') c;
SELECT 'ficou cancelada' caso, count(*) AS n FROM privado.olx_visita WHERE estado = 'cancelada' AND atualizado_em > now() - interval '1 minute';
SELECT 'inexistente' caso, c.* FROM crm_visita_leads_cancelar(-1, 'teste') c;
