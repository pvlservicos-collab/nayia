CREATE OR REPLACE FUNCTION public.captacao_pediu_para_sair(p_texto text)
 RETURNS boolean
 LANGUAGE sql
 IMMUTABLE
AS $function$
  SELECT lower(unaccent(coalesce(p_texto, ''))) ~
         ('\m(nao quero (mais )?receber|nao me (mande|manda|envie)|para de (me )?mandar|'
       || 'pare de (me )?(mandar|enviar)|me (tira|tire|remove|remova) (da|dessa|desta) lista|'
       || 'descadastr|sair da lista|nao envie mais|nao manda mais|me exclui|nao perturbe)');
$function$;
