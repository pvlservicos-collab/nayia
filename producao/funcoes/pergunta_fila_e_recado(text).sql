CREATE OR REPLACE FUNCTION public.pergunta_fila_e_recado(p_texto text)
 RETURNS boolean
 LANGUAGE sql
 STABLE
 SET search_path TO 'public'
AS $function$
  SELECT lower(unaccent(btrim(coalesce(p_texto, '')))) ~ ('^(ah sim|ah ta|ah ok|chegou|excelente|perfeito|otimo|top|tranquilo'
           || '|entendi|ta bom|ta certo|sim sim|ok obrigad[oa]|obrigad[oa] nay|k{2,}|(ha){2,}|rs+)[[:space:]!.,]*$')
      OR lower(unaccent(coalesce(p_texto, ''))) ~ '\m(passa a atender|nunca responde)\M'
$function$;
