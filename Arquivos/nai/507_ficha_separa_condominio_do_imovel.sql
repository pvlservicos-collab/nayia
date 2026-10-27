-- 507 (Pedro, 27/10/2026, ...2954): "ela bugou e confundiu informação do condomínio com informação do imóvel ... ela
-- deve saber separar o que é condomínio do que é imóvel".
--
-- O 9043 (Residencial Tapajós) tem "Piscina" na coluna caracteristicas -- que guarda as do condomínio também, porque é
-- nela que a busca procura -- e o campo extras "caracteristicas do condominio" diz que Piscina, Condomínio fechado,
-- Aceita pet e Segurança 24h são do condomínio. A ficha que a Nay velha lê (nai_ficha_completa) punha tudo em
-- "CARACTERÍSTICAS DO IMÓVEL" e ela respondeu "Sim, a casa tem piscina". Agora o que é do condomínio sai da lista do
-- imóvel e entra na do condomínio (a Nay nova faz o mesmo em cerebro/repo.py).
BEGIN;
SET LOCAL lock_timeout = '3s';
SET LOCAL statement_timeout = '20s';

DO $do$
DECLARE d text; antes text; depois text;
BEGIN
  d := pg_get_functiondef('public.nai_ficha_completa(integer)'::regprocedure);
  antes := $s$  IF coalesce(array_length(f.caracteristicas_imovel, 1), 0) > 0 OR coalesce(array_length(i.caracteristicas, 1), 0) > 0 THEN
    v := v || ('CARACTERÍSTICAS DO IMÓVEL: ' || array_to_string(
               ARRAY(SELECT DISTINCT c FROM unnest(coalesce(f.caracteristicas_imovel, '{}') || coalesce(i.caracteristicas, '{}')) c), ', '));
  END IF;
  IF coalesce(array_length(f.caracteristicas_condominio, 1), 0) > 0 THEN
    v := v || ('CARACTERÍSTICAS DO CONDOMÍNIO: ' || array_to_string(f.caracteristicas_condominio, ', '));
  END IF;$s$;
  depois := $s$  -- 507: o que o cadastro diz que é do condomínio ("caracteristicas do condominio") não é do imóvel
  x := nullif(btrim(i.extras->>'caracteristicas do condominio'), '');
  IF coalesce(array_length(f.caracteristicas_imovel, 1), 0) > 0 OR coalesce(array_length(i.caracteristicas, 1), 0) > 0 THEN
    v := v || ('CARACTERÍSTICAS DO IMÓVEL: ' || array_to_string(
               ARRAY(SELECT DISTINCT c FROM unnest(coalesce(f.caracteristicas_imovel, '{}') || coalesce(i.caracteristicas, '{}')) c
                      WHERE c <> ALL (coalesce(regexp_split_to_array(x, '\s*,\s*'), '{}'))), ', '));
  END IF;
  IF coalesce(array_length(f.caracteristicas_condominio, 1), 0) > 0 OR x IS NOT NULL THEN
    v := v || ('CARACTERÍSTICAS DO CONDOMÍNIO: ' || array_to_string(ARRAY(SELECT DISTINCT c FROM unnest(
               coalesce(f.caracteristicas_condominio, '{}') || coalesce(regexp_split_to_array(x, '\s*,\s*'), '{}')) c), ', '));
  END IF;$s$;
  IF position(antes IN d) = 0 THEN RAISE EXCEPTION 'nai_ficha_completa mudou: não achei o trecho das características'; END IF;
  EXECUTE replace(d, antes, depois);
END $do$;

COMMIT;
