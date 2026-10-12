-- 353 -- Captação: as listas 6 (donos com imóvel disponível) e 8 (donos da planilha antiga que nunca viraram imóvel)
--        entram na fila do modelo oficial `situacao_imovel_cadastrado_1`
--
-- Pedro, 12/10/2026, colando as duas listas da tela Captação › Modelos WhatsApp: "começa o disparo do
-- situacao_imovel_cadastrado_1 · Portuguese (BR) para essas 2 listas".
--
-- Com `captacao_config.python_disparo = sim` (está), quem entra aqui como 'novo' recebe o modelo no horário de
-- `captacao_no_horario()` (seg-sex 08:00-22:00, sáb/dom 08:00-18:00, pausa 12:00-13:30), um a cada 45-75 s,
-- pelo serviço nay-captacao. O modelo só tem {{1}} = nome, e já sai com o rodapé Imobeasy.
--
-- As duas listas são EXATAMENTE as de `site_publicos_disparo` (349/351/352): dono = vw_proprietarios_site com imóvel
-- em vw_imoveis_todos; planilha = proprietarios_export sem "parceir", que não é dono nem corretor dos grupos. Ficam de
-- fora, pelos mesmos motivos da rota de importação, da 343 e do disparo (352):
--   - quem falou conosco nos últimos 60 dias por qualquer número (privado.falou_conosco, com a cópia do CRM);
--   - corretor (grupos) ou parceiro; nome de corretor/imobiliária/empresa; telefone de corretor dos grupos (8 finais);
--   - quem já está na campanha (captacao_leads) e quem está em captacao_nao_disparar;
--   - sem telefone utilizável, sem nome para o "Olá, {{1}}!";
--   - dono que já foi chamado por outro telefone.
-- Um lead por telefone; a lista 6 cita o imóvel disponível de menor código e congela todos os imóveis do dono em
-- `imoveis_prop`; a lista 8 não tem imóvel (é a planilha antiga), então vai sem código e com `imoveis_prop = []`.
BEGIN;
SET LOCAL lock_timeout = '3s';

DROP TABLE IF EXISTS _entram;
CREATE TEMP TABLE _entram ON COMMIT DROP AS
WITH corretor AS (
    SELECT nay_fone_chave(nay_fone_com_ddi(c.telefone)) AS chave FROM corretores c WHERE coalesce(c.telefone, '') <> ''
    UNION
    SELECT nay_fone_chave(nay_fone_com_ddi(p.telefone)) FROM proprietarios_export p WHERE coalesce(p.corretor, '') ~* 'parceir'
), corr AS (
    SELECT DISTINCT nay_fone_chave(nay_fone_com_ddi(c.telefone)) AS chave FROM corretores c WHERE coalesce(btrim(c.telefone), '') <> ''
), dono AS (
    SELECT nay_fone_chave(nay_fone_com_ddi(ps.telefone)) AS chave,
           -- o dono do imóvel citado (o mesmo telefone pode estar em mais de um cadastro de proprietário)
           (array_agg(ps.id ORDER BY (v.status <> 'Disponível'), v.codigo))[1] AS proprietario_id,
           (array_agg(ps.nome ORDER BY (v.status <> 'Disponível'), v.codigo))[1] AS nome,
           (array_agg(nay_fone_com_ddi(ps.telefone) ORDER BY (v.status <> 'Disponível'), v.codigo))[1] AS telefone,
           bool_or(v.status = 'Disponível') AS tem_disponivel,
           (array_agg(v.codigo ORDER BY (v.status <> 'Disponível'), v.codigo))[1] AS codigo,
           (array_agg(v.condominio ORDER BY (v.status <> 'Disponível'), v.codigo))[1] AS condominio,
           (array_agg(v.bairro ORDER BY (v.status <> 'Disponível'), v.codigo))[1] AS bairro,
           (array_agg(v.tipo ORDER BY (v.status <> 'Disponível'), v.codigo))[1] AS tipo,
           jsonb_agg(jsonb_build_object('codigo', v.codigo, 'condominio', v.condominio, 'endereco', v.endereco) ORDER BY v.codigo) AS imoveis_prop
      FROM vw_proprietarios_site ps JOIN vw_imoveis_todos v ON v.proprietario_id = ps.id
     WHERE length(regexp_replace(coalesce(ps.telefone, ''), '\D', '', 'g')) BETWEEN 10 AND 13 AND NOT site_nao_e_dono(ps.nome)
       AND NOT EXISTS (SELECT 1 FROM corretor k WHERE k.chave = nay_fone_chave(nay_fone_com_ddi(ps.telefone)))
     GROUP BY 1
), planilha AS (
    SELECT DISTINCT ON (nay_fone_chave(nay_fone_com_ddi(p.telefone)))
           nay_fone_chave(nay_fone_com_ddi(p.telefone)) AS chave, p.id AS proprietario_id, p.nome, nay_fone_com_ddi(p.telefone) AS telefone
      FROM proprietarios_export p
     WHERE coalesce(p.corretor, '') !~* 'parceir' AND NOT site_nao_e_dono(p.nome)
       AND length(regexp_replace(coalesce(p.telefone, ''), '\D', '', 'g')) BETWEEN 10 AND 13
       AND NOT EXISTS (SELECT 1 FROM dono d WHERE d.chave = nay_fone_chave(nay_fone_com_ddi(p.telefone)))
       AND NOT EXISTS (SELECT 1 FROM corr c WHERE c.chave = nay_fone_chave(nay_fone_com_ddi(p.telefone)))
     ORDER BY nay_fone_chave(nay_fone_com_ddi(p.telefone)), p.id
), cand AS (
    SELECT 6 AS lista, d.chave, d.proprietario_id, d.nome, d.telefone, d.codigo::text AS codigo, d.condominio, d.bairro, d.tipo, d.imoveis_prop
      FROM dono d WHERE d.tem_disponivel
    UNION ALL
    SELECT 8, p.chave, p.proprietario_id, p.nome, p.telefone, NULL, NULL, NULL, NULL, '[]'::jsonb FROM planilha p
), marcado AS (
    SELECT c.*, nay_tratamento_por_nome(c.nome) AS tratamento,
           CASE WHEN coalesce(btrim(c.condominio), '') NOT IN ('', '—', '-') AND c.condominio !~* 'n[aã]o identificad' THEN 'no ' || btrim(c.condominio)
                WHEN coalesce(btrim(c.bairro), '') <> '' THEN 'no bairro ' || btrim(c.bairro) END AS imovel_desc,
           row_number() OVER (PARTITION BY c.chave ORDER BY c.lista, c.proprietario_id) AS vez
      FROM cand c
)
SELECT m.* FROM marcado m
 WHERE m.vez = 1 AND m.telefone ~ '^[0-9]{12,13}$'
   AND coalesce(btrim(m.nome), '') <> ''
   AND NOT EXISTS (SELECT 1 FROM captacao_leads l WHERE l.telefone_chave = m.chave OR l.telefone = m.telefone)
   AND NOT EXISTS (SELECT 1 FROM captacao_nao_disparar n WHERE n.telefone_chave = m.chave)
   AND NOT (m.nome ~* 'corretor|corretora|parceir|broker|assessoria|imobili[aá]ri|im[oó]veis|ltda|eireli|construtor|empreendiment'
            OR nai_dono_e_parceiro(m.nome))
   AND NOT EXISTS (SELECT 1 FROM corretores k
                    WHERE right(regexp_replace(coalesce(k.telefone, ''), '\D', '', 'g'), 8) = right(m.telefone, 8))
   AND NOT nay_falou_conosco(m.chave, 60)
   AND NOT nay_e_corretor_chave(m.chave)
   AND NOT EXISTS (SELECT 1 FROM captacao_leads o WHERE o.proprietario_id = m.proprietario_id
                                                    AND (o.ultimo_envio_em IS NOT NULL OR o.respondeu_em IS NOT NULL));

INSERT INTO captacao_leads (telefone, nome, tratamento, proprietario_id, codigo, imovel_desc, condominio, bairro, tipo_imovel,
                            lista_id, quem_importou, status, etapa, imoveis_prop)
SELECT e.telefone, e.nome, e.tratamento, e.proprietario_id, e.codigo, e.imovel_desc, e.condominio, e.bairro, e.tipo,
       NULL, CASE e.lista WHEN 6 THEN 'Pedro (lista 6: donos com imóvel disponível, 12/10)'
                          ELSE 'Pedro (lista 8: donos da planilha antiga, 12/10)' END,
       'novo', 'novo', e.imoveis_prop
  FROM _entram e
 ORDER BY e.lista, e.proprietario_id
ON CONFLICT DO NOTHING;

-- a regra da campanha (308: corretor, nome de corretor/imobiliária, imóvel de parceiro...) é por lead: quem ela barra
-- não fica parado como 'novo' na tabela, sai agora
DELETE FROM captacao_leads l
 WHERE l.quem_importou LIKE 'Pedro (lista _: %12/10)' AND captacao_fora_da_campanha(l.id) IS NOT NULL;

COMMIT;
