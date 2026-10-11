-- 347 -- A ficha do condomínio não repete item de segurança/comodidade dentro de lazer
--
-- As fichas de antes da 345 guardavam tudo em `lazer` ("Segurança 24h", "Elevador"...). A 345 classificou o que
-- chegou dos anúncios, mas o que já estava em lazer ficou lá, e a tela mostrava "Segurança 24h" em Lazer E em
-- Segurança (visto no 9029 em 11/10). Aqui o item sai de lazer quando a classificação dele é outra.
BEGIN;
SET LOCAL lock_timeout = '3s';

CREATE TEMP TABLE _classe (nome text PRIMARY KEY, grupo text NOT NULL);
INSERT INTO _classe VALUES
 ('condominio fechado','seguranca'),('guarita 24 horas','seguranca'),('guarita','seguranca'),('portaria','seguranca'),
 ('seguranca 24 horas','seguranca'),('seguranca 24h','seguranca'),('porteiro','seguranca'),('portao eletronico','seguranca'),
 ('cerca eletrica','seguranca'),('camera de seguranca','seguranca'),('sistema de camera','seguranca'),('interfone','seguranca'),
 ('elevador','comodidades'),('lavanderia','comodidades'),('gerador de energia','comodidades'),
 ('gerador de energia - 100%','comodidades'),('gas encanado','comodidades'),('agua de poco','comodidades'),
 ('poco','comodidades'),('recepcao','comodidades');
CREATE FUNCTION pg_temp.chave(t text) RETURNS text LANGUAGE sql IMMUTABLE AS
  $$ SELECT btrim(regexp_replace(lower(unaccent(coalesce(t, ''))), '\s+', ' ', 'g')) $$;

-- o que está em lazer e é de outro grupo vai para o grupo certo (sem repetir) e sai de lazer
UPDATE condominio_ficha f
   SET seguranca = (SELECT coalesce(array_agg(x ORDER BY o), '{}') FROM (
                      SELECT DISTINCT ON (pg_temp.chave(x)) x, o
                        FROM unnest(f.seguranca || (SELECT coalesce(array_agg(l), '{}') FROM unnest(f.lazer) l JOIN _classe k ON k.nome = pg_temp.chave(l) WHERE k.grupo = 'seguranca'))
                             WITH ORDINALITY u(x, o) ORDER BY pg_temp.chave(x), o) s),
       comodidades = (SELECT coalesce(array_agg(x ORDER BY o), '{}') FROM (
                      SELECT DISTINCT ON (pg_temp.chave(x)) x, o
                        FROM unnest(f.comodidades || (SELECT coalesce(array_agg(l), '{}') FROM unnest(f.lazer) l JOIN _classe k ON k.nome = pg_temp.chave(l) WHERE k.grupo = 'comodidades'))
                             WITH ORDINALITY u(x, o) ORDER BY pg_temp.chave(x), o) s),
       lazer = (SELECT coalesce(array_agg(l ORDER BY o), '{}') FROM unnest(f.lazer) WITH ORDINALITY u(l, o)
                 WHERE NOT EXISTS (SELECT 1 FROM _classe k WHERE k.nome = pg_temp.chave(l)))
 WHERE EXISTS (SELECT 1 FROM unnest(f.lazer) l JOIN _classe k ON k.nome = pg_temp.chave(l));

COMMIT;
