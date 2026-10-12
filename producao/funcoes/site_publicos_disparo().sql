CREATE OR REPLACE FUNCTION public.site_publicos_disparo()
 RETURNS TABLE(n integer, grupo text, nome text, descricao text, total integer, disparados integer, falaram integer)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
  WITH oficial AS (                      -- quem já recebeu disparo nosso (oficial, ou a abertura da captação)
    SELECT DISTINCT nay_fone_chave(m.telefone) AS chave FROM captacao_mensagens m
     WHERE m.direcao = 'enviada' AND m.status <> 'Falhou' AND (m.message_id LIKE 'wamid%' OR m.origem = 'disparo')
    UNION
    SELECT l.telefone_chave FROM captacao_leads l WHERE l.ultimo_envio_em IS NOT NULL AND coalesce(l.telefone_chave, '') <> ''
  ), falou AS (                          -- quem escreveu para a gente nos últimos 60 dias (qualquer número)
    SELECT DISTINCT nay_fone_chave(nay_fone_com_ddi(m.telefone)) AS chave FROM mensagens m
     WHERE m.direcao = 'recebida' AND m.criada_em > now() - interval '60 days'
    UNION
    SELECT DISTINCT nay_fone_chave(nay_fone_com_ddi(m.telefone)) FROM captacao_mensagens m
     WHERE m.direcao = 'recebida' AND m.criada_em > now() - interval '60 days'
    UNION
    SELECT DISTINCT nay_fone_chave(nay_fone_com_ddi(c.chave)) FROM nai_turno t JOIN nai_contato c ON c.id = t.contato_id
     WHERE t.criado_em > now() - interval '60 days' AND c.chave !~ '@'
    UNION
    SELECT DISTINCT nay_fone_chave(nay_fone_com_ddi(c.telefone)) FROM corretores c
     WHERE c.ultima_interacao > now() - interval '60 days' AND coalesce(c.telefone, '') <> ''
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
    UNION ALL SELECT 10, l.telefone_chave FROM captacao_leads l JOIN captacao_retomada_oficial r ON r.lead_id = l.id
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
         coalesce(count(DISTINCT l.chave) FILTER (WHERE NOT EXISTS (SELECT 1 FROM falou f WHERE f.chave = l.chave)
                                                    AND EXISTS (SELECT 1 FROM oficial o WHERE o.chave = l.chave)), 0)::int AS disparados,
         coalesce(count(DISTINCT l.chave) FILTER (WHERE EXISTS (SELECT 1 FROM falou f WHERE f.chave = l.chave)), 0)::int AS falaram
    FROM nomes x LEFT JOIN listas l ON l.n = x.n
   GROUP BY x.n, x.grupo, x.nome, x.descricao
   ORDER BY (x.grupo = 'donos'), x.n;
$function$;
