CREATE OR REPLACE FUNCTION public.nai_tracar_entrada(p_payload jsonb, p_exec text DEFAULT NULL::text)
 RETURNS bigint
 LANGUAGE plpgsql
AS $function$
BEGIN
  RETURN nai_tracar(
    NULL, 'entrada', 'webhook_zapi', 'ok',
    p_payload, NULL,
    'chegou da Z-API', NULL, p_exec);
EXCEPTION WHEN others THEN
  RETURN NULL;
END;
$function$
;
