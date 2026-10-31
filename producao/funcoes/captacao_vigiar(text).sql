CREATE OR REPLACE FUNCTION public.captacao_vigiar(p_quem text DEFAULT 'n8n'::text)
 RETURNS text
 LANGUAGE plpgsql
AS $function$
BEGIN
  IF coalesce(nullif(btrim((SELECT valor FROM captacao_config WHERE chave = 'rotinas_de')), ''), 'n8n') <> p_quem THEN
    RETURN NULL;
  END IF;
  RETURN captacao_vigiar_rodar();
END
$function$;
