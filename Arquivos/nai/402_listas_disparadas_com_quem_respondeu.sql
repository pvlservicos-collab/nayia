-- 402: as listas JÁ DISPARADAS continuam com o número delas: quantos receberam disparo e quantos responderam
--
-- Pedro, 17/10/2026: "deixa lá as listas que já disparamos, e põe um número lá, ex. 100 disparados, 20% respondeu, aí tu
-- põe a barra 20% verde". Com a 401 (60 dias de contato, nos dois sentidos) quem recebeu disparo saiu do "para falar" e o
-- "já receberam" zerou. Agora: `disparados` conta TODO mundo da lista que recebeu disparo (sem o corte dos 60 dias),
-- `responderam` quantos deles escreveram depois do disparo, e `total` continua sendo quem falta (sem contato em 60 dias).
BEGIN;
SET LOCAL lock_timeout = '3s';
DROP FUNCTION IF EXISTS public.site_publicos_disparo();
CREATE OR REPLACE FUNCTION public.site_publicos_disparo()
 RETURNS TABLE(n integer, grupo text, nome text, descricao text, total integer, disparados integer, responderam integer, falaram integer)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
  WITH oficial AS MATERIALIZED (         -- quem já recebeu disparo nosso (oficial, ou a abertura da captação), e quando
    SELECT x.chave, min(x.em) AS em FROM (
      SELECT nay_fone_chave(m.telefone) AS chave, m.criada_em AS em FROM captacao_mensagens m
       WHERE m.direcao = 'enviada' AND m.status <> 'Falhou' AND (m.message_id LIKE 'wamid%' OR m.origem = 'disparo')
      UNION ALL
      SELECT l.telefone_chave, l.ultimo_envio_em FROM captacao_leads l
       WHERE l.ultimo_envio_em IS NOT NULL AND coalesce(l.telefone_chave, '') <> '') x
     GROUP BY x.chave
  ), recebida AS MATERIALIZED (           -- 402: a última mensagem de cada pessoa (o telefone limpo uma vez só)
    SELECT nay_fone_chave(nay_fone_com_ddi(r.telefone)) AS chave, max(r.criada_em) AS em
      FROM captacao_mensagens r WHERE r.direcao = 'recebida' GROUP BY 1
  ), respondeu AS (                       -- 402: escreveu depois do disparo (ou a campanha marcou que respondeu)
    SELECT o.chave FROM oficial o JOIN recebida r ON r.chave = o.chave AND r.em > o.em
    UNION
    SELECT l.telefone_chave FROM captacao_leads l
     WHERE l.respondeu_em IS NOT NULL AND EXISTS (SELECT 1 FROM oficial o WHERE o.chave = l.telefone_chave)
  ), falou AS (                          -- 352: quem escreveu para a gente nos últimos 60 dias, por QUALQUER número
    SELECT f.chave FROM privado.falou_conosco f WHERE f.ultima_em > now() - interval '60 days'
  ), corretor AS (                        -- 352: corretor (grupos ou parceria) não é dono
    SELECT nay_fone_chave(nay_fone_com_ddi(c.telefone)) AS chave FROM corretores c WHERE coalesce(c.telefone, '') <> ''
    UNION
    SELECT nay_fone_chave(nay_fone_com_ddi(p.telefone)) FROM proprietarios_export p WHERE coalesce(p.corretor, '') ~* 'parceir'
  ), corr AS (
    SELECT DISTINCT ON (nay_fone_chave(nay_fone_com_ddi(c.telefone))) nay_fone_chave(nay_fone_com_ddi(c.telefone)) AS chave, c.ultima_interacao
      FROM corretores c WHERE coalesce(btrim(c.telefone), '') <> ''
     ORDER BY nay_fone_chave(nay_fone_com_ddi(c.telefone)), c.ultima_interacao DESC NULLS LAST
  ), parc AS (
    SELECT DISTINCT nay_fone_chave(nay_fone_com_ddi(p.telefone)) AS chave
      FROM proprietarios_export p
     WHERE coalesce(p.corretor, '') ~* 'parceir' AND length(regexp_replace(coalesce(p.telefone, ''), '\D', '', 'g')) BETWEEN 10 AND 13
  ), dono AS (
    SELECT nay_fone_chave(nay_fone_com_ddi(ps.telefone)) AS chave,
           bool_or(v.status = 'Disponível') AS tem_disponivel, bool_or(v.status = 'Alugado') AS tem_alugado,
           bool_and(v.status = 'Vendido') AS so_vendido, bool_and(v.status IN ('Removido', 'Arquivado')) AS so_fora
      FROM vw_proprietarios_site ps JOIN vw_imoveis_todos v ON v.proprietario_id = ps.id
     WHERE length(regexp_replace(coalesce(ps.telefone, ''), '\D', '', 'g')) BETWEEN 10 AND 13 AND NOT site_nao_e_dono(ps.nome)
       AND NOT EXISTS (SELECT 1 FROM corretor k WHERE k.chave = nay_fone_chave(nay_fone_com_ddi(ps.telefone)))
     GROUP BY 1
  ), planilha AS (
    SELECT DISTINCT nay_fone_chave(nay_fone_com_ddi(p.telefone)) AS chave
      FROM proprietarios_export p
     WHERE coalesce(p.corretor, '') !~* 'parceir' AND NOT site_nao_e_dono(p.nome)
       AND length(regexp_replace(coalesce(p.telefone, ''), '\D', '', 'g')) BETWEEN 10 AND 13
       AND NOT EXISTS (SELECT 1 FROM dono d WHERE d.chave = nay_fone_chave(nay_fone_com_ddi(p.telefone)))
       AND NOT EXISTS (SELECT 1 FROM corr c WHERE c.chave = nay_fone_chave(nay_fone_com_ddi(p.telefone)))
  ), listas AS (
    SELECT 1 AS n, chave FROM corr
    UNION ALL SELECT 2, p.chave FROM parc p
    UNION ALL SELECT 7, p.chave FROM parc p WHERE NOT EXISTS (SELECT 1 FROM corr c WHERE c.chave = p.chave)
    UNION ALL SELECT 3, chave FROM dono WHERE so_fora
    UNION ALL SELECT 4, chave FROM dono WHERE so_vendido
    UNION ALL SELECT 5, chave FROM dono WHERE tem_alugado
    UNION ALL SELECT 6, chave FROM dono WHERE tem_disponivel
    UNION ALL SELECT 8, chave FROM planilha
    UNION ALL SELECT 9, l.telefone_chave FROM captacao_leads l WHERE coalesce(l.telefone_chave, '') <> ''
                AND NOT EXISTS (SELECT 1 FROM corretor k WHERE k.chave = l.telefone_chave)
    UNION ALL SELECT 10, l.telefone_chave FROM captacao_leads l JOIN captacao_retomada_oficial r ON r.lead_id = l.id
                WHERE NOT EXISTS (SELECT 1 FROM corretor k WHERE k.chave = l.telefone_chave)
  ), nomes AS (SELECT * FROM (VALUES
      (1, 'corretores', 'Corretores dos grupos', 'os corretores dos grupos da Parceria'),
      (2, 'corretores', 'Parceiros do site antigo', 'cadastro antigo marcado como parceiro'),
      (7, 'corretores', 'Parceiros que não estão nos grupos', 'corretores novos para os grupos'),
      (3, 'donos', 'Donos com imóvel removido ou arquivado', 'atualizar cadastro antigo'),
      (4, 'donos', 'Donos que só têm imóvel vendido', 'mais imóveis ("tem outro?")'),
      (5, 'donos', 'Donos com imóvel alugado', 'atualizar e pegar a data do contrato'),
      (6, 'donos', 'Donos com imóvel disponível', 'atualizar'),
      (8, 'donos', 'Donos da planilha antiga que nunca viraram imóvel', 'mais imóveis'),
      (9, 'donos', 'Captação: proprietários pelo número oficial', 'a campanha da situação do imóvel (já disparada)'),
      (10, 'donos', 'Captação: retomada pelo oficial', 'quem recebeu a abertura pela Z-API e nunca respondeu (já disparada)')
    ) AS v(n, grupo, nome, descricao))
  SELECT x.n, x.grupo, x.nome, x.descricao,
         coalesce(count(DISTINCT l.chave) FILTER (WHERE NOT EXISTS (SELECT 1 FROM falou f WHERE f.chave = l.chave)), 0)::int AS total,
         -- 402: disparados e responderam sem o corte dos 60 dias (é o placar da lista que já saiu)
         coalesce(count(DISTINCT l.chave) FILTER (WHERE EXISTS (SELECT 1 FROM oficial o WHERE o.chave = l.chave)), 0)::int AS disparados,
         coalesce(count(DISTINCT l.chave) FILTER (WHERE EXISTS (SELECT 1 FROM respondeu r WHERE r.chave = l.chave)), 0)::int AS responderam,
         coalesce(count(DISTINCT l.chave) FILTER (WHERE EXISTS (SELECT 1 FROM falou f WHERE f.chave = l.chave)), 0)::int AS falaram
    FROM nomes x LEFT JOIN listas l ON l.n = x.n
   GROUP BY x.n, x.grupo, x.nome, x.descricao
   ORDER BY (x.grupo = 'donos'), x.n;
$function$;

REVOKE ALL ON FUNCTION public.site_publicos_disparo() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.site_publicos_disparo() TO nay_site_escrita, nay_leitura;
COMMIT;
