CREATE OR REPLACE FUNCTION public.nai_e_comando_parada(p text)
 RETURNS boolean
 LANGUAGE sql
 IMMUTABLE
AS $function$
  -- Duas palavras de proposito: "parar" sozinho e palavra comum demais para
  -- desligar o atendimento inteiro sem querer.
  -- Parenteses em volta da concatenacao: `~*` e `||` tem a mesma precedencia,
  -- e sem eles isto vira (p ~* 'A') || 'B' -- que devolve texto, nao boolean.
  SELECT coalesce(p, '') ~* ('^\s*(@?nay[\s,:;.!-]*)?(parar|pausar|parada|voltar|retomar|volta)\s+'
                           || '(o\s+)?(atendimento|atender)\s*[.!]?\s*$');
$function$
;
