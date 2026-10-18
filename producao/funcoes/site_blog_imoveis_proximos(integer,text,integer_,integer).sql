CREATE OR REPLACE FUNCTION public.site_blog_imoveis_proximos(p_codigo integer, p_bairro text, p_excluir integer[] DEFAULT '{}'::integer[], p_limite integer DEFAULT 4)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_lat double precision; v_lon double precision; v_loc boolean; v_norm text; v jsonb;
BEGIN
  SELECT g.lat, g.lon INTO v_lat, v_lon FROM imovel_geo g WHERE g.codigo = p_codigo;
  SELECT b.de_locacao INTO v_loc FROM core_imovel_busca b WHERE b.codigo = p_codigo;
  v_norm := nay_normalizar_lugar(p_bairro, true);
  SELECT coalesce(jsonb_agg(c.card ORDER BY c.ordem), '[]'::jsonb) INTO v
    FROM (SELECT site_blog_card_imovel(b.codigo) AS card,
                 CASE WHEN v_lat IS NOT NULL AND g.lat IS NOT NULL
                      THEN sqrt(power((g.lat - v_lat) * 111.0, 2) + power((g.lon - v_lon) * 107.0, 2))
                      WHEN v_norm IS NOT NULL AND b.bairro_norm = v_norm THEN 50
                      ELSE 500 END
                 + CASE WHEN v_loc IS NOT NULL AND b.de_locacao = v_loc THEN 0 ELSE 20 END
                 - least(coalesce(b.qtd_fotos, 0), 10) * 0.01 AS ordem
            FROM core_imovel_busca b
            LEFT JOIN imovel_geo g ON g.codigo = b.codigo
           WHERE b.ofertavel AND NOT coalesce(b.e_parceiro, false) AND coalesce(b.qtd_fotos, 0) > 0
             AND b.codigo <> coalesce(p_codigo, 0) AND NOT (b.codigo = ANY (coalesce(p_excluir, '{}')))
           ORDER BY ordem, b.codigo DESC
           LIMIT greatest(1, least(coalesce(p_limite, 4), 12))) c
   WHERE c.card IS NOT NULL;
  RETURN v;
END
$function$;
