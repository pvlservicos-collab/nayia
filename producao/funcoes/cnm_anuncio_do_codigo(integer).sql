CREATE OR REPLACE FUNCTION public.cnm_anuncio_do_codigo(p_codigo integer)
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  SELECT jsonb_build_object(
           'codigo', i.codigo,
           'condominio', nay_condominio_de_verdade(i.tipo, i.condominio_nome),
           'bairro', nullif(btrim(coalesce(i.bairro, '')), ''),
           'noAr', i.status = 'Disponível' AND coalesce(i.disponivel, false) AND coalesce(i.publicado_no_site, false),
           'foto', (SELECT f.url FROM imovel_fotos f
                     WHERE f.codigo = i.codigo AND NOT coalesce(f.e_mosaico, false) AND f.url ~* '^https://'
                     ORDER BY coalesce(f.e_capa, false) DESC, f.ordem NULLS LAST, f.id LIMIT 1))
    FROM imoveis i WHERE i.codigo = p_codigo
$function$;
