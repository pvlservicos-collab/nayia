CREATE OR REPLACE FUNCTION public.nai_pede_documentos(p_texto text)
 RETURNS boolean
 LANGUAGE sql
 IMMUTABLE
AS $function$
  -- PEDIDO, e nao mencao. "manda" precisa terminar ali (senao "mandei os
  -- documentos para o proprietario" dispararia), e "document..." pega
  -- documento, documentos e documentacao de uma vez.
  WITH s AS (SELECT lower(unaccent(coalesce(p_texto, ''))) AS x)
  SELECT
      (x ~ '\m(quais|qual|que|lista|relacao|manda|mande|envia|envie|passa|preciso|precisa|necessari\w*|pede|pedir|exige|exigem|falta|faltam)\M[^.?!]{0,40}\m(document\w*|docs)\M'
       OR x ~ '\m(document\w*|docs)\M[^.?!]{0,40}\m(quais|qual|precisa|preciso|necessari\w*|pede|exige)\M'
       OR x ~ '^\s*(documenta[cç][aã]o|documentos)\s*[?!.]*\s*$')
  FROM s;
$function$
;
