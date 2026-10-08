CREATE OR REPLACE FUNCTION public.crm_olx_conta_preparar(p_conta text, p_segredo text)
 RETURNS text
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v text;
BEGIN
  IF p_conta NOT IN ('proprietarios', 'corretores') THEN RETURN NULL; END IF;
  IF p_segredo IS NULL OR p_segredo !~ '^[A-Za-z0-9]{40,100}$' THEN RETURN NULL; END IF;
  INSERT INTO privado.olx_conta (conta, segredo) VALUES (p_conta, p_segredo) ON CONFLICT (conta) DO NOTHING;
  SELECT c.segredo INTO v FROM privado.olx_conta c WHERE c.conta = p_conta;
  RETURN v;
END
$function$;
