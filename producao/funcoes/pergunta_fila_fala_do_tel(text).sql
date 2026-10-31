CREATE OR REPLACE FUNCTION public.pergunta_fila_fala_do_tel(p_texto text)
 RETURNS text
 LANGUAGE sql
 IMMUTABLE
AS $function$
  SELECT coalesce(nullif(btrim(regexp_replace(btrim(coalesce(p_texto, '')),
           ('^(fala|diz|diga|avisa|responde|explica)([[:space:]]+(pra|para|pro|a|ao|à)[[:space:]]+(ele|ela|o corretor'
            || '|a corretora|o cliente|a cliente|o rapaz|a moça))?[[:space:]]+(que[[:space:]]+)?'), '', 'i')), ''),
         btrim(coalesce(p_texto, '')))
$function$;
