CREATE OR REPLACE FUNCTION public.nai_perfil_ativo(p_contato bigint)
 RETURNS SETOF nai_perfil_cliente
 LANGUAGE sql
 STABLE
AS $function$
  SELECT p.* FROM nai_perfil_cliente p
   WHERE p.contato_id = ANY (coalesce(nai_contato_irmaos(p_contato), ARRAY[p_contato]))
     AND p.encerrado_em IS NULL AND p.atualizado_em > now() - interval '7 days'
   ORDER BY p.atualizado_em DESC LIMIT 1;
$function$;
