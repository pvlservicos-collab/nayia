CREATE OR REPLACE FUNCTION public.crm_captacao_ficha_do_dono(p_captacao bigint)
 RETURNS TABLE(ficha_id bigint, tipo text, codigo integer, estado text, dados jsonb, fotos integer)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
 SET jit TO 'off'
AS $function$
  SELECT c.id, c.tipo, c.codigo, c.estado, c.dados - '_fotos_ids',
         coalesce(jsonb_array_length(CASE WHEN jsonb_typeof(c.fotos) = 'array' THEN c.fotos END), 0)
    FROM captacao_cadastro c
   WHERE c.lead_id = p_captacao AND c.estado IN ('coletando', 'pronto')
   ORDER BY (c.estado = 'pronto') DESC, c.atualizado_em DESC
   LIMIT 1
$function$;
