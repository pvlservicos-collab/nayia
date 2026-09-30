CREATE OR REPLACE FUNCTION public.nai_contato_irmaos(p_contato bigint)
 RETURNS bigint[]
 LANGUAGE sql
 STABLE COST 2000
AS $function$
  WITH eu AS (
    SELECT id, chave FROM nai_contato WHERE id = p_contato
  ), fone AS (
    SELECT coalesce(
      (SELECT nai_chave(i.telefone)
         FROM identidade_lid i, eu
        WHERE eu.chave LIKE 'lid:%'
          AND i.lid IN (regexp_replace(eu.chave, '^lid:', ''),
                        regexp_replace(eu.chave, '^lid:', '') || '@lid')
          AND coalesce(i.telefone, '') <> ''
        LIMIT 1),
      (SELECT chave FROM eu)) AS chave
  )
  SELECT coalesce(array_agg(DISTINCT c.id), ARRAY[p_contato])
    FROM nai_contato c
   WHERE c.id = p_contato
      OR c.chave = (SELECT chave FROM fone)
      OR c.chave IN (SELECT 'lid:' || regexp_replace(i.lid, '\D', '', 'g')
                       FROM identidade_lid i, fone
                      WHERE nai_chave(i.telefone) = fone.chave);
$function$
;
