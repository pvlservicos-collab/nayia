-- 168 -- nai_contato_irmaos compara o @lid pelos DÍGITOS (29/09/2026)
--
-- Por quê: `identidade_lid.lid` está gravado dos dois jeitos -- 1.463 linhas
-- só com os dígitos e 157 com "@lid" no fim. A função comparava cru:
--   i.lid = '<dígitos>'   e   'lid:' || i.lid
-- então, nas 157, o telefone não achava o LID e o LID não achava o telefone.
-- Medido antes de aplicar: 40 contatos (20 pessoas) ganham o irmão, nenhum
-- perde, e o resultado antigo está contido no novo em 100% dos 307 candidatos.
-- Efeito: a regra do Tel (nai_tel_com_a_conversa, o gap de 30 min, o DEVOLVER)
-- passa a valer nas duas linhas dessas pessoas -- antes a Nay podia falar por
-- cima dele. Ver memória `duas-linhas-por-pessoa` e `lid-no-crm`.
--
-- Patch EM CIMA da versão viva (pg_proc de 29/09), não de arquivo antigo.
-- `i.lid IN (d, d || '@lid')` mantém o índice da chave primária de identidade_lid.
-- Também ignora linha de identidade sem telefone (antes podia devolver a chave
-- vazia e a pessoa ficava sozinha).
--
-- Conferência: SELECT * FROM nai_rodar_casos() antes e depois (43 de 43).

BEGIN;
SET LOCAL lock_timeout = '5s';

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
$function$;

COMMIT;
