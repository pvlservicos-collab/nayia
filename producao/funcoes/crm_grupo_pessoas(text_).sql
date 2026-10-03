CREATE OR REPLACE FUNCTION public.crm_grupo_pessoas(p_telefones text[])
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
  WITH pedidos AS (
    SELECT DISTINCT t AS telefone, nai_chave(t) AS chave
      FROM unnest(coalesce(p_telefones, '{}'::text[])) t
     WHERE t ~ '^\d{10,15}$'
  ), cor AS (
    SELECT DISTINCT ON (nai_chave(c.telefone)) nai_chave(c.telefone) AS chave, nullif(btrim(c.nome), '') AS nome, c.ativo
      FROM corretores c
     WHERE nai_chave(c.telefone) IN (SELECT chave FROM pedidos)
     ORDER BY nai_chave(c.telefone), c.ativo DESC NULLS LAST
  )
  SELECT coalesce(jsonb_object_agg(p.telefone, jsonb_strip_nulls(jsonb_build_object(
           'nome', coalesce(cor.nome, nullif(btrim(k.nome_completo), ''), nullif(btrim(k.nome_whatsapp), '')),
           'corretor', cor.chave IS NOT NULL,
           'falou_com_a_nay', k.id IS NOT NULL))), '{}'::jsonb)
    FROM pedidos p
    LEFT JOIN cor ON cor.chave = p.chave
    LEFT JOIN nai_contato k ON k.chave = p.chave;
$function$;
