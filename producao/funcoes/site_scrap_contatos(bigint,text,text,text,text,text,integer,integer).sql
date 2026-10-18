CREATE OR REPLACE FUNCTION public.site_scrap_contatos(p_lista bigint DEFAULT NULL::bigint, p_busca text DEFAULT NULL::text, p_status text DEFAULT NULL::text, p_etiqueta text DEFAULT NULL::text, p_bairro text DEFAULT NULL::text, p_ordem text DEFAULT 'anuncios'::text, p_limite integer DEFAULT 200, p_desloc integer DEFAULT 0)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE v_busca text := nullif(trim(p_busca), ''); v_dig text; v_total int; v_itens jsonb; v_bairros jsonb;
BEGIN
  v_dig := nullif(regexp_replace(coalesce(v_busca, ''), '\D', '', 'g'), '');
  WITH base AS MATERIALIZED (
    SELECT c.*, l.nome AS lista_nome, l.cor AS lista_cor, l.tipo AS lista_tipo,
           (SELECT array_agg(DISTINCT l2.nome ORDER BY l2.nome) FROM scrap_contato c2 JOIN scrap_lista l2 ON l2.id = c2.lista_id
             WHERE c2.telefone = c.telefone AND c2.id <> c.id AND l2.tipo = 'lista') AS tambem_em,
           (p_lista IS NOT NULL AND l.tipo = 'lista' AND scrap_bloqueado(c.telefone)) AS na_blacklist
      FROM scrap_contato c JOIN scrap_lista l ON l.id = c.lista_id
     WHERE (CASE WHEN p_lista IS NULL THEN l.tipo = 'lista' ELSE c.lista_id = p_lista END)
       AND (p_status IS NULL OR p_status = '' OR c.status = p_status)
       AND (p_etiqueta IS NULL OR p_etiqueta = '' OR p_etiqueta = ANY (c.etiquetas))
       AND (p_bairro IS NULL OR p_bairro = '' OR p_bairro = ANY (c.bairros))
       AND (v_busca IS NULL
            OR c.nome ILIKE '%' || v_busca || '%' OR c.empresa ILIKE '%' || v_busca || '%' OR c.observacao ILIKE '%' || v_busca || '%'
            OR c.exemplo_titulo ILIKE '%' || v_busca || '%'
            OR (v_dig IS NOT NULL AND c.telefone LIKE '%' || v_dig || '%'))
  ), uma AS (
    SELECT DISTINCT ON (CASE WHEN p_lista IS NULL THEN telefone ELSE id::text END) *
      FROM base ORDER BY (CASE WHEN p_lista IS NULL THEN telefone ELSE id::text END), n_anuncios DESC, id
  ), ord AS (
    SELECT * FROM uma
     ORDER BY CASE WHEN p_ordem = 'nome' THEN lower(coalesce(nome, 'zzz')) END,
              CASE WHEN p_ordem = 'recentes' THEN atualizado_em END DESC,
              CASE WHEN p_ordem = 'anuncios' OR p_ordem IS NULL THEN n_anuncios END DESC,
              id
  )
  SELECT count(*), (SELECT jsonb_agg(to_jsonb(x) - 'dados' || jsonb_build_object('telefone_fmt', scrap_telefone_formatar(x.telefone))) FROM (SELECT * FROM ord LIMIT greatest(p_limite, 1) OFFSET greatest(p_desloc, 0)) x)
    INTO v_total, v_itens FROM ord;
  SELECT coalesce(jsonb_agg(jsonb_build_object('bairro', b, 'n', n) ORDER BY n DESC, b), '[]'::jsonb) INTO v_bairros
    FROM (SELECT unnest(c.bairros) b, count(*) n FROM scrap_contato c JOIN scrap_lista l ON l.id = c.lista_id
           WHERE (CASE WHEN p_lista IS NULL THEN l.tipo = 'lista' ELSE c.lista_id = p_lista END) GROUP BY 1 ORDER BY 2 DESC LIMIT 40) y;
  RETURN jsonb_build_object('total', v_total, 'contatos', coalesce(v_itens, '[]'::jsonb), 'bairros', v_bairros);
END
$function$;
