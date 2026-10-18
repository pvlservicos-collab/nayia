-- 409: SCRAP — celular guardado sem o 9 (18/10/2026)
-- A base da casa (corretores, falou_conosco, parte de proprietarios) guarda o celular como 55 + DDD + 8 dígitos, sem o 9
-- (a chave nay_fone_chave). O normalizador do Scrap recusava esses (10 dígitos com o local começando em 9): 1.549 dos
-- 1.567 corretores saíram como "inválidos" na carga das listas Base. Agora: 10 dígitos com o local começando em 6-9 é
-- celular sem o 9 e ganha o 9 de volta.
BEGIN;
SET LOCAL lock_timeout = '3s';
CREATE OR REPLACE FUNCTION scrap_telefone_normalizar(p text)
RETURNS text
LANGUAGE plpgsql IMMUTABLE AS $function$
DECLARE d text; ddd int; t text; i int;
BEGIN
  t := coalesce(p, '');
  FOR i IN 1..3 LOOP   -- "9998I-9200": letra no meio dos dígitos é dígito mal digitado
    t := regexp_replace(t, '(\d)[Il|]', '\11', 'g');
    t := regexp_replace(t, '[Il|](\d)', '1\1', 'g');
    t := regexp_replace(t, '(\d)[Oo](?=\d)', '\10', 'g');
  END LOOP;
  d := regexp_replace(t, '\D', '', 'g');
  IF d = '' THEN RETURN NULL; END IF;
  IF length(d) IN (12, 13) AND left(d, 2) = '55' THEN d := substr(d, 3); END IF;
  IF length(d) = 11 AND left(d, 1) = '0' THEN d := substr(d, 2); END IF;       -- 092 ...
  IF length(d) = 9 AND left(d, 1) = '9' THEN d := '92' || d; END IF;
  IF length(d) = 8 AND left(d, 1) IN ('2', '3') THEN d := '92' || d; END IF;
  IF length(d) = 10 AND substr(d, 3, 1) IN ('6', '7', '8', '9') THEN d := left(d, 2) || '9' || substr(d, 3); END IF;  -- celular sem o 9
  IF length(d) NOT IN (10, 11) THEN RETURN NULL; END IF;
  ddd := left(d, 2)::int;
  IF ddd < 11 OR ddd > 99 OR substr(d, 2, 1) = '0' THEN RETURN NULL; END IF;
  IF length(d) = 11 THEN
    IF substr(d, 3, 1) <> '9' THEN RETURN NULL; END IF;
    IF substr(d, 3, 9) ~ '^(\d)\1{8}$' THEN RETURN NULL; END IF;                 -- 99999-9999
    RETURN d;
  END IF;
  IF ddd NOT IN (92, 97) OR substr(d, 3, 1) NOT IN ('2', '3') THEN RETURN NULL; END IF;
  RETURN d;
END
$function$;
COMMIT;
