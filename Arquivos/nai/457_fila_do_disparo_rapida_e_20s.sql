-- 457 -- A fila do disparo do modelo oficial sem travar com 1.726 donos, 1 modelo a cada 20 s, e os 2 que falaram conosco fora
--
-- Pedro, 21/10/2026, com o disparo do outro_imovel_04 (listas 5, 3 e 4) já liberado: "garanta que não falamos com nenhum
-- antes por nenhum número nos últimos 60 dias para não mandar msg de novo para quem já falamos, e põe para 1 a cada 20
-- segundos".
--
-- O que estava: captacao_py_fila_do_disparo conferia CADA lead fazendo conta no telefone de todas as mensagens e de todos
-- os corretores (nay_fone_chave por linha, nay_e_corretor_chave, captacao_fora_da_campanha). Com 1.726 na fila passou do
-- statement_timeout e o disparo parou no primeiro minuto ("o disparo falhou; tento de novo em 20 s"): nada saiu.
-- Agora cada conjunto (quem já recebeu, quem falou conosco em 60 dias, corretores, parceiros, imóveis de parceiro) é
-- calculado UMA vez por chamada, com as MESMAS regras; captacao_fora_da_campanha continua valendo na reserva (gatilho 308).
--
-- A garantia dos 60 dias, conferida em 21/10 ~11:15 com os 1.726: todas as fontes do naydb (Parceria, captação, Nay velha
-- e nova nas duas direções, envios, saídas do sistema, OLX, corretores) e o crmdb (leads + lead_activities, as duas
-- direções). Dois tinham falado conosco depois de entrar na lista: …8062 (o número de captação falou com ele em 13/10) e
-- …0278 (Parceria). Os dois vão para captacao_nao_disparar (a fila já os barrava pelo falou_conosco; agora é para sempre).
BEGIN;
SET LOCAL lock_timeout = '3s';

INSERT INTO captacao_nao_disparar (telefone_chave, motivo)
SELECT l.telefone_chave, '457: falou conosco nos últimos 60 dias (conferência do disparo do outro_imovel_04, 21/10)'
  FROM captacao_leads l
 WHERE l.modelo_abertura = 'outro_imovel_04' AND l.status = 'novo' AND l.id IN (5658, 5977)   -- …8062 e …0278
ON CONFLICT (telefone_chave) DO NOTHING;

UPDATE captacao_config SET valor = '18' WHERE chave = 'python_disparo_seg_min';
UPDATE captacao_config SET valor = '22' WHERE chave = 'python_disparo_seg_max';

CREATE OR REPLACE FUNCTION public.captacao_py_fila_do_disparo()
 RETURNS SETOF bigint
 LANGUAGE sql
 STABLE
AS $function$
  WITH aprovados AS MATERIALIZED (
    SELECT regexp_split_to_array(coalesce((SELECT c.valor FROM captacao_config c WHERE c.chave = 'python_modelos_aprovados'), ''),
                                 '\s*,\s*') AS a
  ), cand AS MATERIALIZED (   -- o barato primeiro: quem pode estar na fila
    SELECT l.* FROM captacao_leads l, aprovados p
     WHERE l.tentativas < 4 AND NOT l.opt_out AND l.humano_assumiu_em IS NULL
       AND coalesce(btrim(l.telefone), '') <> '' AND coalesce(btrim(l.nome), '') <> ''
       AND (l.status IN ('novo', 'erro')
            OR (l.status = 'enviado' AND l.respondeu_em IS NULL
                AND EXISTS (SELECT 1 FROM captacao_retomada_oficial r WHERE r.lead_id = l.id)
                AND NOT EXISTS (SELECT 1 FROM captacao_motor mt WHERE mt.lead_id = l.id)))
       -- 447: o modelo próprio do lead só sai depois que a Meta aprovar (o nay-captacao escreve a lista)
       AND (l.modelo_abertura IS NULL OR l.modelo_abertura = ANY (p.a))
       AND NOT EXISTS (SELECT 1 FROM captacao_nao_disparar n WHERE n.telefone_chave = l.telefone_chave)
  ), enviada AS MATERIALIZED (    -- quem já recebeu alguma coisa nossa pela captação
    SELECT DISTINCT nay_fone_chave(m.telefone) AS chave FROM captacao_mensagens m
     WHERE m.direcao = 'enviada' AND m.status <> 'Falhou'
  ), recebida AS MATERIALIZED (   -- quem já escreveu para a captação
    SELECT DISTINCT nay_fone_chave(m.telefone) AS chave FROM captacao_mensagens m WHERE m.direcao = 'recebida'
  ), falou AS MATERIALIZED (      -- 352: falou conosco por qualquer número nos últimos 60 dias (nay_falou_conosco)
    SELECT f.chave FROM privado.falou_conosco f WHERE f.ultima_em > now() - interval '60 days'
  ), corretor AS MATERIALIZED (   -- 352: nay_e_corretor_chave (grupos ou parceria)
    SELECT nay_fone_chave(nay_fone_com_ddi(c.telefone)) AS chave FROM corretores c WHERE coalesce(c.telefone, '') <> ''
    UNION
    SELECT nay_fone_chave(nay_fone_com_ddi(p.telefone)) FROM proprietarios_export p WHERE coalesce(p.corretor, '') ~* 'parceir'
  ), corr8 AS MATERIALIZED (      -- 308: captacao_fora_da_campanha, corretor dos grupos pelos 8 finais
    SELECT DISTINCT right(regexp_replace(coalesce(k.telefone, ''), '\D', '', 'g'), 8) AS f8 FROM corretores k
  ), parceiro AS MATERIALIZED (   -- 308: captacao_fora_da_campanha, imóvel de parceiro
    SELECT i.codigo::text AS codigo FROM imoveis i WHERE coalesce(i.e_parceiro, false)
  ), teste AS MATERIALIZED (
    SELECT right(regexp_replace(coalesce((SELECT c.valor FROM captacao_config c WHERE c.chave = 'telefone_teste'), ''), '\D', '', 'g'), 8) AS f8
  ), ja_chamado AS MATERIALIZED ( -- o mesmo dono já chamado por outro telefone (outro lead dele já recebeu ou respondeu)
    SELECT o.id, o.proprietario_id FROM captacao_leads o
     WHERE o.proprietario_id IS NOT NULL AND (o.ultimo_envio_em IS NOT NULL OR o.respondeu_em IS NOT NULL)
  )
  SELECT l.id
    FROM cand l, teste t
   WHERE (l.status = 'enviado' OR NOT EXISTS (SELECT 1 FROM enviada e WHERE e.chave = l.telefone_chave))
     AND (l.status <> 'enviado' OR NOT EXISTS (SELECT 1 FROM recebida r WHERE r.chave = l.telefone_chave))
     AND NOT EXISTS (SELECT 1 FROM ja_chamado j WHERE j.proprietario_id = l.proprietario_id AND j.id <> l.id)
     AND NOT EXISTS (SELECT 1 FROM falou f WHERE f.chave = l.telefone_chave)
     AND NOT EXISTS (SELECT 1 FROM corretor k WHERE k.chave = l.telefone_chave)
     -- captacao_fora_da_campanha (308), o telefone de teste passa sempre
     AND (right(l.telefone, 8) = t.f8 OR (
              NOT EXISTS (SELECT 1 FROM corr8 c WHERE c.f8 = right(l.telefone, 8))
          AND NOT (nai_dono_e_parceiro(l.nome) OR coalesce(l.nome, '') ~* 'parceri')
          AND NOT EXISTS (SELECT 1 FROM parceiro p
                           WHERE p.codigo = l.codigo
                              OR p.codigo IN (SELECT x ->> 'codigo' FROM jsonb_array_elements(coalesce(l.imoveis_prop, '[]'::jsonb)) x))))
   ORDER BY (l.status = 'enviado'), l.id;
$function$;

COMMIT;
