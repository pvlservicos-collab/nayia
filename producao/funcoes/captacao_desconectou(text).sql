CREATE OR REPLACE FUNCTION public.captacao_desconectou(p_erro text)
 RETURNS text
 LANGUAGE plpgsql
AS $function$
BEGIN
  PERFORM captacao_desarmar('a Z-API avisou que o número desconectou'
                            || COALESCE(' (' || NULLIF(btrim(p_erro), '') || ')', ''));
  RETURN (SELECT valor FROM captacao_config WHERE chave = '_disjuntor');
END $function$;
