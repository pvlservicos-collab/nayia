CREATE OR REPLACE FUNCTION public.site_imoveis_para_enviar()
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
  WITH i AS (
    SELECT im.*,
           -- "Apartamento em Via Pública", "Casa" etc. no campo do condomínio são tipo, não nome
           CASE WHEN nay_sem_acento(lower(btrim(coalesce(im.condominio_nome, ''))))
                     ~ '^(casa|apartamento|sala|loja|galpao|terreno|lote|kitnet|flat|studio|cobertura|predio|ponto|sitio|chacara)'
                THEN NULL ELSE nullif(btrim(im.condominio_nome), '') END AS condo
      FROM imoveis im
     WHERE nay_esta_no_mercado(im.disponivel, im.bloqueado, im.publicado_no_site)
       AND NOT coalesce(im.e_parceiro, false)
       AND (coalesce(im.valor_venda, 0) > 0 OR coalesce(im.valor_aluguel, 0) > 0)
  ), t AS (
    SELECT i.*, coalesce(nullif(btrim(i.tipo), ''), 'Imóvel')
           || CASE WHEN coalesce(i.quartos, 0) > 0 THEN ' ' || i.quartos || CASE WHEN i.quartos = 1 THEN ' quarto' ELSE ' quartos' END ELSE '' END
           || CASE WHEN i.condo IS NOT NULL THEN ' no ' || i.condo
                   WHEN nullif(btrim(i.bairro), '') IS NOT NULL THEN ' em ' || btrim(i.bairro) ELSE '' END AS titulo
      FROM i
  )
  SELECT coalesce(jsonb_agg(jsonb_strip_nulls(jsonb_build_object(
           'codigo', t.codigo,
           'tipo', coalesce(nullif(btrim(t.tipo), ''), 'Imóvel'),
           'titulo', t.titulo,
           'slug', btrim(regexp_replace(lower(nay_sem_acento(t.titulo)), '[^a-z0-9]+', '-', 'g'), '-'),
           'condominio', t.condo,
           'bairro', nullif(btrim(t.bairro), ''),
           'quartos', t.quartos, 'vagas', t.vagas,
           'area', round(coalesce(nullif(t.area_util, 0), nullif(t.area_total, 0))),
           'venda', nullif(t.valor_venda, 0), 'aluguel', nullif(t.valor_aluguel, 0),
           -- 297: 'mobiliado' | 'semi' (só ar-condicionado e vazio não entram: a chave some)
           'mobilia', CASE WHEN lower(btrim(coalesce(t.mobilia, ''))) LIKE 'semi%' THEN 'semi'
                           WHEN lower(btrim(coalesce(t.mobilia, ''))) LIKE 'mobiliado%' THEN 'mobiliado' END,
           'foto', (SELECT f.url FROM imovel_fotos f
                     WHERE f.codigo = t.codigo AND coalesce(f.url, '') <> '' AND NOT coalesce(f.e_mosaico, false)
                     ORDER BY coalesce(f.e_capa, false) DESC, f.ordem NULLS LAST, f.id LIMIT 1),
           'lat', round(g.lat::numeric, 3), 'lon', round(g.lon::numeric, 3)))
         ORDER BY t.codigo DESC), '[]'::jsonb)
    FROM t LEFT JOIN imovel_geo g ON g.codigo = t.codigo;
$function$;
