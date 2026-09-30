CREATE OR REPLACE FUNCTION public.nai_lista_visitas_corretor(p_contato bigint)
 RETURNS text
 LANGUAGE sql
 STABLE
AS $function$
  SELECT string_agg('• ' || nai_ref_imovel(x.codigo) || ' — ' || coalesce(nai_quando_humano(x.quando), 'sem horário'), E'\n' ORDER BY x.id)
    FROM nai_visita x WHERE x.corretor_id = p_contato AND nai_visita_aberta(x.estado);
$function$;
