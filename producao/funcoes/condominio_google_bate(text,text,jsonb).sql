CREATE OR REPLACE FUNCTION public.condominio_google_bate(p_campo text, p_valor text, p_sug jsonb)
 RETURNS boolean
 LANGUAGE plpgsql
 STABLE
AS $function$
DECLARE s text;
BEGIN
  IF p_sug IS NULL OR p_valor IS NULL OR btrim(p_valor) = '' THEN
    RETURN false;                     -- campo vazio nunca é "do Google"
  END IF;

  IF p_campo = 'elevador' THEN
    IF jsonb_typeof(p_sug->'elevador') <> 'boolean' THEN RETURN false; END IF;
    RETURN (p_sug->>'elevador')::boolean = (lower(btrim(p_valor)) ~ '^(s|possui|tem|[1-9])');
  END IF;

  s := p_sug->>p_campo;
  IF s IS NULL OR btrim(s) = '' THEN RETURN false; END IF;

  IF p_campo IN ('torres', 'andares', 'aptos_por_andar', 'unidades', 'ano_construcao', 'numero', 'cep') THEN
    RETURN nullif(regexp_replace(p_valor, '\D', '', 'g'), '')
         = nullif(regexp_replace(s,       '\D', '', 'g'), '');
  END IF;

  RETURN condominio_google_chave(p_valor) = condominio_google_chave(s);
END;
$function$;
