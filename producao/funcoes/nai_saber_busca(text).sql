CREATE OR REPLACE FUNCTION public.nai_saber_busca(p_texto text)
 RETURNS TABLE(id bigint, resposta text, semelhanca real)
 LANGUAGE sql
 STABLE
AS $function$
  -- O piso de 0,35 e o mesmo criterio da parecenca de condominio (89): acima
  -- disso e a mesma pergunta escrita de outro jeito; abaixo e outra coisa, e
  -- responder seria inventar.
  SELECT s.id, s.resposta, similarity(lower(unaccent(s.pergunta)), lower(unaccent(coalesce(p_texto, ''))))
    FROM nai_saber s
   WHERE s.ativo
     AND similarity(lower(unaccent(s.pergunta)), lower(unaccent(coalesce(p_texto, '')))) >= 0.35
   ORDER BY 3 DESC LIMIT 1;
$function$;
