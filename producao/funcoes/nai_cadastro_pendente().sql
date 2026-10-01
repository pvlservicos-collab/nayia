CREATE OR REPLACE FUNCTION public.nai_cadastro_pendente()
 RETURNS TABLE(fonte text, codigo integer, ficha_id bigint, titulo text, tipo text, bairro text, condominio text, origem text, status text, pct integer, falta text[], motivos text[], fotos integer, fotos_de_fora integer, dono text, atualizado timestamp with time zone, dados jsonb)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
 SET jit TO 'off'
AS $function$
  WITH f AS (   -- as fotos: quantas, e quantas estão num link que não é nosso
    SELECT codigo, count(*)::int AS n,
           count(*) FILTER (WHERE url !~ '^https://imobeasy\.(com|online)/')::int AS de_fora
      FROM imovel_fotos GROUP BY codigo
  ),
  fichas AS (   -- a ficha da conversa que ninguém aplicou
    SELECT c.id, c.lead_id, c.tipo, c.codigo, c.dados, c.estado, c.atualizado_em,
           nullif(btrim(l.nome), '') AS dono
      FROM captacao_cadastro c
      LEFT JOIN captacao_leads l ON l.id = c.lead_id
     WHERE c.estado IN ('coletando', 'pronto')
  ),
  im AS (
    SELECT i.codigo, i.status, i.origem, i.tipo, i.bairro,
           nullif(btrim(i.condominio_nome), '') AS condominio,
           coalesce(f.n, 0) AS fotos, coalesce(f.de_fora, 0) AS de_fora,
           p.pct, p.falta, p.falta_essencial, p.oferecido,
           i.bloqueado, i.criado_em,
           (SELECT pr.nome FROM proprietarios pr WHERE pr.id = i.proprietario_id) AS dono,
           (SELECT max(x.id) FROM fichas x WHERE x.codigo = i.codigo) AS ficha_id,
           array_remove(ARRAY[
             CASE WHEN i.status = 'Rascunho' THEN 'pré-cadastro (Rascunho)' END,
             CASE WHEN i.bloqueado THEN 'bloqueado: a Nay não oferece' END,
             CASE WHEN p.oferecido AND coalesce(f.n, 0) = 0 THEN 'no ar sem nenhuma foto' END,
             CASE WHEN p.oferecido AND p.falta_essencial <> '{}' THEN 'falta o essencial: ' || array_to_string(p.falta_essencial, ', ') END,
             CASE WHEN coalesce(f.de_fora, 0) > 0 THEN 'foto em link de fora (' || f.de_fora || '): some quando expirar' END,
             CASE WHEN EXISTS (SELECT 1 FROM fichas x WHERE x.codigo = i.codigo) THEN 'o dono ditou dados na conversa e ninguém aplicou' END
           ], NULL) AS motivos
      FROM imoveis i
      LEFT JOIN f ON f.codigo = i.codigo
      LEFT JOIN vw_imovel_pontuacao p ON p.codigo = i.codigo
  )
  SELECT 'imovel'::text, im.codigo, im.ficha_id,
         coalesce(im.condominio, im.tipo, 'Imóvel ' || im.codigo),
         im.tipo, im.bairro, im.condominio, im.origem, im.status,
         im.pct, im.falta, im.motivos, im.fotos, im.de_fora, im.dono, im.criado_em, NULL::jsonb
    FROM im WHERE im.motivos <> '{}'
  UNION ALL
  -- a ficha de imóvel NOVO: o dono contou tudo e o imóvel nem existe ainda
  SELECT 'ficha'::text, NULL::integer, x.id,
         coalesce(nullif(btrim(x.dados->>'condominio'), ''), nullif(btrim(x.dados->>'tipo'), ''), 'Imóvel novo'),
         nullif(btrim(x.dados->>'tipo'), ''), nullif(btrim(x.dados->>'bairro'), ''),
         nullif(btrim(x.dados->>'condominio'), ''), 'captacao', 'Sem cadastro',
         NULL::integer, '{}'::text[],
         ARRAY['o dono ditou o imóvel na conversa e ele não está cadastrado'],
         0, 0, x.dono, x.atualizado_em, x.dados
    FROM fichas x WHERE x.codigo IS NULL AND x.tipo <> 'atualizar'
$function$;
