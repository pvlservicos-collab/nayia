-- 343 -- Captação: os donos da lista 23 (contratos que vencem em agosto, setembro e outubro de 2026) entram na fila
--        do modelo oficial `situacao_imovel_cadastrado_1`
--
-- Pedro, 10/10/2026: "vê uma lista de imóveis marcados com contrato a vencer esse mês, e mês passado setembro e
-- agosto, e separa em uma lista para fazermos disparo da API oficial esse modelo lá com os botões
-- situacao_imovel_cadastrado_1 ... já prepara para enviar, me diz aqui quantos deu que vou te confirmar".
--
-- !! SÓ APLICAR COM O "PODE ENVIAR" DELE. Com `captacao_config.python_disparo = sim`, quem entra aqui como 'novo'
-- !! recebe o modelo no próximo horário de `captacao_no_horario()` (um por minuto, serviço nay-captacao).
--
-- A lista 23 foi salva pelo caminho do admin (Locação > filtro de vencimento): 19 contratos. Os candidatos são
-- montados como a rota `/api/captacao/importar` monta (`candidatos_da_lista`, nay-site-api/app.py): dono e telefone
-- do admin antigo, um lead por telefone, Sr./Sra. por `nay_tratamento_por_nome`. Ficam de fora, pelos mesmos
-- motivos da rota e do disparo:
--   - quem já está na campanha (11 em 10/10: 4 já receberam o modelo em 09/10, 2 a abertura antiga, 4 estão com o
--     Tel pelo celular, 1 é corretor);
--   - quem está em `captacao_nao_disparar` (342);
--   - sem telefone utilizável (2501), sem condomínio nem bairro para citar (2200);
--   - corretor, parceiro, empresa, imóvel de parceiro, telefone de corretor dos grupos;
--   - dono que já foi chamado por outro telefone.
-- Em 10/10 entram 6: 4770, 5607, 2262, 2647, 5439 e 4443.
--
-- "Condomínio não identificado" não é nome de condomínio: a frase cita o bairro (4443: "no bairro Centro").
BEGIN;
SET LOCAL lock_timeout = '3s';

WITH item AS (
  SELECT x->>'codigo' AS codigo, nullif(x->>'condominio', '') AS condominio_da_lista, (x->>'vencimento')::date AS vencimento,
         x->>'proprietario_nome' AS nome_da_lista, x->>'proprietario_telefone' AS telefone_da_lista
    FROM site_listas l, jsonb_array_elements(l.itens) x WHERE l.id = 23
), rico AS (
  SELECT it.codigo, it.vencimento, s.proprietario_id,
         coalesce(p.nome, it.nome_da_lista) AS nome, coalesce(p.telefone, it.telefone_da_lista) AS telefone_bruto,
         coalesce(i.tipo, d.tipo) AS tipo, coalesce(i.bairro, d.bairro) AS bairro,
         CASE WHEN coalesce(it.condominio_da_lista, '') IN ('', '—', '-')
              THEN coalesce(i.condominio_nome, d.condominio, a.condominio, it.condominio_da_lista)
              ELSE it.condominio_da_lista END AS condominio_bruto,
         coalesce(i.e_parceiro, false) AS de_parceiro
    FROM item it
    LEFT JOIN imoveis_admin_snapshot s ON s.codigo = it.codigo
    LEFT JOIN proprietarios_admin p ON p.id = s.proprietario_id
    LEFT JOIN imoveis i ON i.codigo::text = it.codigo
    LEFT JOIN proprietarios_admin_imoveis a ON a.codigo = s.codigo AND a.proprietario_id = s.proprietario_id
    LEFT JOIN imoveis_admin_detalhe d ON d.codigo = it.codigo
), fone AS (
  SELECT r.*, regexp_replace(coalesce(r.telefone_bruto, ''), '\D', '', 'g') AS dig,
         nullif(CASE WHEN r.condominio_bruto ~* 'n[aã]o identificad' OR r.condominio_bruto IN ('—', '-') THEN ''
                     ELSE btrim(r.condominio_bruto) END, '') AS condominio
    FROM rico r
), cand AS (
  SELECT f.*,
         CASE WHEN f.dig = '' THEN NULL
              WHEN f.dig ~ '^55' THEN CASE WHEN length(f.dig) IN (12, 13) THEN f.dig END
              WHEN length(f.dig) IN (10, 11) THEN '55' || f.dig END AS telefone,
         CASE WHEN f.condominio IS NOT NULL THEN 'no ' || f.condominio
              WHEN coalesce(btrim(f.bairro), '') <> '' THEN 'no bairro ' || btrim(f.bairro) END AS imovel_desc,
         nay_tratamento_por_nome(f.nome) AS tratamento
    FROM fone f
), marcado AS (
  SELECT c.*, nay_fone_chave(c.telefone) AS chave,
         row_number() OVER (PARTITION BY nay_fone_chave(c.telefone) ORDER BY c.vencimento, c.codigo) AS vez
    FROM cand c
), entram AS (
  SELECT m.* FROM marcado m
   WHERE m.telefone IS NOT NULL AND m.vez = 1 AND m.imovel_desc IS NOT NULL
     AND NOT (coalesce(btrim(m.nome), '') = '' AND m.tratamento IS NULL)
     AND NOT EXISTS (SELECT 1 FROM captacao_leads l WHERE l.telefone_chave = m.chave)
     AND NOT EXISTS (SELECT 1 FROM captacao_nao_disparar n WHERE n.telefone_chave = m.chave)
     AND NOT (coalesce(m.nome, '') ~* 'corretor|corretora|parceir|broker|assessoria|imobili[aá]ri|im[oó]veis|ltda|eireli|construtor|empreendiment'
              OR site_nao_e_dono(m.nome) OR nai_dono_e_parceiro(m.nome))
     AND NOT m.de_parceiro
     AND NOT EXISTS (SELECT 1 FROM corretores k
                      WHERE right(regexp_replace(coalesce(k.telefone, ''), '\D', '', 'g'), 8) = right(m.telefone, 8))
     AND NOT (m.proprietario_id IS NOT NULL
              AND EXISTS (SELECT 1 FROM captacao_leads o WHERE o.proprietario_id = m.proprietario_id
                                                           AND (o.ultimo_envio_em IS NOT NULL OR o.respondeu_em IS NOT NULL)))
)
INSERT INTO captacao_leads (telefone, nome, tratamento, proprietario_id, codigo, imovel_desc, condominio, bairro, tipo_imovel,
                            lista_id, quem_importou, status, etapa)
SELECT e.telefone, e.nome, e.tratamento, e.proprietario_id, e.codigo, e.imovel_desc, e.condominio, e.bairro, e.tipo,
       23, 'Pedro (lista 23: contratos a vencer em ago, set e out/2026)', 'novo', 'novo'
  FROM entram e
ON CONFLICT DO NOTHING;

-- todos os imóveis de cada dono, congelados agora (o mesmo que a rota de importação faz)
UPDATE captacao_leads l
   SET imoveis_prop = coalesce((SELECT jsonb_agg(jsonb_build_object('codigo', i.codigo, 'condominio', i.condominio, 'endereco', i.endereco)
                                                 ORDER BY i.codigo)
                                  FROM proprietarios_admin_imoveis i WHERE i.proprietario_id = l.proprietario_id), '[]'::jsonb)
 WHERE l.lista_id = 23 AND l.proprietario_id IS NOT NULL;

COMMIT;
