CREATE OR REPLACE FUNCTION public.site_publicos_disparo()
 RETURNS TABLE(n integer, nome text, descricao text, total integer, disparados integer)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
  WITH oficial AS (                      -- quem já recebeu pela API oficial
    SELECT DISTINCT nay_fone_chave(m.telefone) AS chave FROM captacao_mensagens m
     WHERE m.direcao = 'enviada' AND m.status <> 'Falhou' AND (m.message_id LIKE 'wamid%' OR m.origem = 'disparo')
    UNION
    SELECT l.telefone_chave FROM captacao_leads l WHERE l.ultimo_envio_em IS NOT NULL AND coalesce(l.telefone_chave, '') <> ''
  ), corr AS (                           -- os corretores dos grupos, um por telefone
    SELECT DISTINCT ON (nay_fone_chave(c.telefone)) nay_fone_chave(c.telefone) AS chave, c.ultima_interacao
      FROM corretores c WHERE coalesce(btrim(c.telefone), '') <> ''
     ORDER BY nay_fone_chave(c.telefone), c.ultima_interacao DESC NULLS LAST
  ), parc AS (                           -- os parceiros do site antigo (cadastro de proprietários marcado como parceiro)
    SELECT DISTINCT nay_fone_chave(nay_fone_com_ddi(p.telefone)) AS chave
      FROM proprietarios_export p
     WHERE coalesce(p.corretor, '') ~* 'parceir' AND length(regexp_replace(coalesce(p.telefone, ''), '\D', '', 'g')) BETWEEN 10 AND 13
  ), dono AS (                           -- cada dono do site com telefone e a situação dos imóveis dele
    SELECT nay_fone_chave(nay_fone_com_ddi(ps.telefone)) AS chave,
           bool_or(v.status = 'Disponível') AS tem_disponivel, bool_or(v.status = 'Alugado') AS tem_alugado,
           bool_and(v.status = 'Vendido') AS so_vendido, bool_and(v.status IN ('Removido', 'Arquivado')) AS so_fora,
           count(v.codigo) AS imoveis
      FROM vw_proprietarios_site ps JOIN vw_imoveis_todos v ON v.proprietario_id = ps.id
     WHERE length(regexp_replace(coalesce(ps.telefone, ''), '\D', '', 'g')) BETWEEN 10 AND 13
       AND NOT site_nao_e_dono(ps.nome)
     GROUP BY 1
  ), planilha AS (                       -- a planilha antiga de proprietários (export) que nunca virou dono de imóvel no site
    SELECT DISTINCT nay_fone_chave(nay_fone_com_ddi(p.telefone)) AS chave
      FROM proprietarios_export p
     WHERE coalesce(p.corretor, '') !~* 'parceir' AND NOT site_nao_e_dono(p.nome)
       AND length(regexp_replace(coalesce(p.telefone, ''), '\D', '', 'g')) BETWEEN 10 AND 13
       AND NOT EXISTS (SELECT 1 FROM dono d WHERE d.chave = nay_fone_chave(nay_fone_com_ddi(p.telefone)))
       AND NOT EXISTS (SELECT 1 FROM corr c WHERE c.chave = nay_fone_chave(nay_fone_com_ddi(p.telefone)))
  ), listas AS (
    SELECT 1 AS n, 'Corretores dos grupos' AS nome, 'tirando quem escreveu nos últimos 30 dias' AS descricao, chave
      FROM corr WHERE ultima_interacao IS NULL OR ultima_interacao < now() - interval '30 days'
    UNION ALL
    SELECT 2, 'Parceiros do site antigo', 'tirando quem já conversa com a gente', p.chave
      FROM parc p WHERE NOT EXISTS (SELECT 1 FROM corr c WHERE c.chave = p.chave AND c.ultima_interacao IS NOT NULL)
    UNION ALL
    SELECT 3, 'Donos com imóvel removido ou arquivado', 'atualizar cadastro antigo', chave FROM dono WHERE so_fora
    UNION ALL
    SELECT 4, 'Donos que só têm imóvel vendido', 'mais imóveis ("tem outro?")', chave FROM dono WHERE so_vendido
    UNION ALL
    SELECT 5, 'Donos com imóvel alugado', 'atualizar e pegar a data do contrato', chave FROM dono WHERE tem_alugado
    UNION ALL
    SELECT 6, 'Donos com imóvel disponível', 'atualizar', chave FROM dono WHERE tem_disponivel
    UNION ALL
    SELECT 7, 'Parceiros que não estão nos grupos', 'corretores novos', p.chave
      FROM parc p WHERE NOT EXISTS (SELECT 1 FROM corr c WHERE c.chave = p.chave)
    UNION ALL
    SELECT 8, 'Donos da planilha antiga que nunca viraram imóvel', 'mais imóveis', chave FROM planilha
    UNION ALL
    -- as que já foram disparadas (350): a campanha da captação e a retomada pelo oficial
    SELECT 9, 'Captação: proprietários pelo número oficial', 'a campanha da situação do imóvel (modelo com os botões)', l.telefone_chave
      FROM captacao_leads l WHERE coalesce(l.telefone_chave, '') <> ''
    UNION ALL
    SELECT 10, 'Captação: retomada pelo oficial', 'quem recebeu a abertura pela Z-API e nunca respondeu (323)', l.telefone_chave
      FROM captacao_leads l JOIN captacao_retomada_oficial r ON r.lead_id = l.id
  )
  , nomes AS (SELECT * FROM (VALUES
      (1, 'Corretores dos grupos', 'tirando quem escreveu nos últimos 30 dias'),
      (2, 'Parceiros do site antigo', 'tirando quem já conversa com a gente'),
      (3, 'Donos com imóvel removido ou arquivado', 'atualizar cadastro antigo'),
      (4, 'Donos que só têm imóvel vendido', 'mais imóveis ("tem outro?")'),
      (5, 'Donos com imóvel alugado', 'atualizar e pegar a data do contrato'),
      (6, 'Donos com imóvel disponível', 'atualizar'),
      (7, 'Parceiros que não estão nos grupos', 'corretores novos'),
      (8, 'Donos da planilha antiga que nunca viraram imóvel', 'mais imóveis'),
      (9, 'Captação: proprietários pelo número oficial', 'a campanha da situação do imóvel (modelo com os botões)'),
      (10, 'Captação: retomada pelo oficial', 'quem recebeu a abertura pela Z-API e nunca respondeu (323)')) AS v(n, nome, descricao))
  SELECT x.n, x.nome, x.descricao, coalesce(count(DISTINCT l.chave), 0)::int AS total,
         coalesce(count(DISTINCT l.chave) FILTER (WHERE EXISTS (SELECT 1 FROM oficial o WHERE o.chave = l.chave)), 0)::int AS disparados
    FROM nomes x LEFT JOIN listas l ON l.n = x.n GROUP BY x.n, x.nome, x.descricao ORDER BY x.n;
$function$;
