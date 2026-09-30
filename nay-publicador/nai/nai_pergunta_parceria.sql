CREATE OR REPLACE FUNCTION public.nai_pergunta_parceria(p text)
 RETURNS boolean
 LANGUAGE sql
 IMMUTABLE
AS $function$
  SELECT lower(unaccent(coalesce(p, ''))) ~ ('\m(aceit\w*|faz|fazem|fazemos|fazendo|fazer|faco|faria|fariam|trabalh\w*|vamos|bora|rola|topa|tem|teem|disponive\w*\s+(para|pra))'
                                              || '(\s+\w+){0,2}\s+parcerias?\M'
                                              || '|\mparcerias?\s*\?')
     AND lower(unaccent(coalesce(p, ''))) !~ '(como\s+(funciona|e|seria|fica)|50\s*/\s*50|50\s*%|porcent|divis|comiss|quanto|60\s*/\s*40)'
     AND lower(unaccent(coalesce(p, ''))) !~ '^\s*(resposta|responde|descarta|devolver|assumir)\M';
$function$
;
