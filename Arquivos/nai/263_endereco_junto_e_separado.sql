-- 263 (02/10/2026): O ENDEREÇO VAI JUNTO, E TAMBÉM SEPARADO -- o bot escolhe.
-- Pedro, depois da 262: "mande o número junto e ele decide, ok?".
--
-- A 262 tinha deixado `endereco` só com a rua. Volta a ser o endereço inteiro
-- ("rua, número"), como o bot recebia desde o começo, e a rua sozinha ganha um
-- campo próprio:
--   endereco     "Avenida Joaquim Nabuco, 1908"   rua e número juntos
--   rua          "Avenida Joaquim Nabuco"         só a rua
--   numero       "1908"
--   complemento
-- Quem consome usa `endereco` OU `rua` + `numero` -- nunca `endereco` + `numero`,
-- que repetiria o número.
--
-- O `endereco` é montado da rua JÁ LIMPA (262) com o número: não volta o lixo de
-- antes (", , ,  -") nem o número duas vezes quando ele estava escrito dentro
-- da rua.
BEGIN;
SET LOCAL lock_timeout = '3s';

CREATE OR REPLACE FUNCTION pg_temp.trocar(p_fn regprocedure, p_de text, p_para text, p_vezes int DEFAULT 1)
 RETURNS void LANGUAGE plpgsql AS $$
DECLARE d text := pg_get_functiondef(p_fn); n int := (length(d) - length(replace(d, p_de, ''))) / length(p_de);
BEGIN
  IF n <> p_vezes THEN RAISE EXCEPTION 'trocar em %: esperava % vez(es), achei % -- %', p_fn, p_vezes, n, left(p_de, 50); END IF;
  EXECUTE replace(d, p_de, p_para);
END $$;

SELECT pg_temp.trocar('crm_imovel_candidatos(jsonb)'::regprocedure,
$de$              -- 262: rua e número separados (o bot grava em campos separados)
              'endereco', nullif(btrim(regexp_replace(regexp_replace(coalesce(t.logradouro, ''),
                            ',\s*(n[º°o.]?\s*)?[0-9].*$', ''), '\s*,\s*(-|,|$).*$', ''), ' ,-'), ''),
$de$,
$para$              -- 262/263: `endereco` é rua + número juntos; `rua` e `numero` vão também
              -- separados, e quem consome escolhe (nunca endereco + numero: repete o número)
              'endereco', nullif(concat_ws(', ',
                 nullif(btrim(regexp_replace(regexp_replace(coalesce(t.logradouro, ''),
                            ',\s*(n[º°o.]?\s*)?[0-9].*$', ''), '\s*,\s*(-|,|$).*$', ''), ' ,-'), ''),
                 coalesce(nullif(btrim(t.numero), ''),
                          (regexp_match(coalesce(t.logradouro, ''), ',\s*(?:n[º°o.]?\s*)?([0-9]+[A-Za-z]?)'))[1])), ''),
              'rua', nullif(btrim(regexp_replace(regexp_replace(coalesce(t.logradouro, ''),
                            ',\s*(n[º°o.]?\s*)?[0-9].*$', ''), '\s*,\s*(-|,|$).*$', ''), ' ,-'), ''),
$para$);
COMMIT;
