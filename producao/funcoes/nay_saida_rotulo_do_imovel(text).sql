CREATE OR REPLACE FUNCTION public.nay_saida_rotulo_do_imovel(p_codigo text)
 RETURNS text
 LANGUAGE sql
 STABLE
 SET search_path TO 'public'
AS $function$
  SELECT p_codigo
         || coalesce((SELECT ' — ' || coalesce(nai_condominio_ok(i.condominio_nome), coalesce(nullif(i.tipo, ''), 'imóvel'))
                             || coalesce(' (' || nullif(i.bairro, '') || ')', '')
                        FROM imoveis i WHERE i.codigo::text = p_codigo), '');
$function$;
