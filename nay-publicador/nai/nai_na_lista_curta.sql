CREATE OR REPLACE FUNCTION public.nai_na_lista_curta(p_contato bigint, p_chave text)
 RETURNS boolean
 LANGUAGE sql
 STABLE
AS $function$
  SELECT btrim(nai_cfg('so_estes_numeros', '')) <> ''
     AND (p_chave = ANY (nai_chaves_de('so_estes_numeros'))
          OR (p_contato IS NOT NULL AND EXISTS (
                SELECT 1 FROM nai_contato c
                 WHERE c.id = ANY (nai_contato_irmaos(p_contato))
                   AND c.chave = ANY (nai_chaves_de('so_estes_numeros')))));
$function$
;
