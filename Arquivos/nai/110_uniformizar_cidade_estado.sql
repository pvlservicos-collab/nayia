-- =====================================================================
-- NAI -- 110: cidade e estado escritos de um jeito so (Tel, 23/09/2026)
--
-- A lista suspensa que ele pediu ("por a lista que desce la em todos os campos
-- de imoveis") mostrou de cara por que ela e necessaria: cada um digitou de um
-- jeito.
--
--   cidade: Manaus, MANAUS, manaus, Campo Grande
--   estado: Amazonas, AMAZONAS, AM, amazonas
--
-- Com quatro grafias de "Manaus", filtrar por cidade nunca traz tudo. Aqui
-- ficam uma de cada -- e, com a lista na tela, ninguem digita de novo.
-- =====================================================================

\set ON_ERROR_STOP on

BEGIN;

UPDATE imoveis SET cidade = 'Manaus'
 WHERE lower(unaccent(btrim(coalesce(cidade, '')))) = 'manaus' AND cidade <> 'Manaus';

UPDATE imoveis SET estado = 'AM'
 WHERE lower(unaccent(btrim(coalesce(estado, '')))) IN ('am', 'amazonas') AND estado <> 'AM';

COMMIT;

SELECT 'cidade' AS campo, coalesce(cidade,'(vazio)') AS valor, count(*)::text AS imoveis
  FROM imoveis GROUP BY 2
UNION ALL
SELECT 'estado', coalesce(estado,'(vazio)'), count(*)::text FROM imoveis GROUP BY 2
ORDER BY 1, 3::int DESC;
