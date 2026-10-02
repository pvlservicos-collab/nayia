-- 262 (02/10/2026): A CONSULTA DEVOLVE RUA E NÚMERO SEPARADOS.
-- O bot da consulta, pelo Pedro: "no CRM, a rua e o número são campos separados.
-- Se puderem, mandem endereco só com a rua e um numero à parte. Se vier junto,
-- eu separo, mas assim fica menos chance de erro."
--
-- A 258 devolvia `dados.endereco` como "rua, número". Agora:
--   endereco     só a rua
--   numero       o número
--   complemento  o complemento (276 imóveis têm)
--
-- No nosso cadastro eles JÁ são colunas separadas em quase tudo: 4.616 dos 5.676
-- imóveis têm `numero` preenchido. Mas 38 têm o número escrito DENTRO da rua
-- ("Travessa Bacare, 44, Huascar Angelim, Aleixo, Manaus - AM"; 15 deles sem a
-- coluna do número). Para esses, a rua é cortada na vírgula que antecede o
-- número e o número sai dali quando a coluna está vazia. Só corta quando depois
-- da vírgula vem número: "Ramal do Januari, km 7, depois da ponte" fica inteiro.
--
-- E O LIXO SAI: o ensaio mostrou ruas gravadas como ", , ,  -" (molde de
-- endereço vazio) e "Rua Neves da Fontoura, - Adrianópolis, Manaus - AM". A
-- primeira vira nulo; a segunda, "Rua Neves da Fontoura". Medido no catálogo
-- inteiro: 94 ruas cortadas certo, 13 viram nulo (não tinham rua nenhuma) e 80
-- ficam com vírgula porque a vírgula é do endereço ("Rua 04, quadra A").
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
$de$              'endereco', nullif(concat_ws(', ', nullif(btrim(t.logradouro), ''), nullif(btrim(t.numero), '')), ''),
$de$,
$para$              -- 262: rua e número separados (o bot grava em campos separados)
              'endereco', nullif(btrim(regexp_replace(regexp_replace(coalesce(t.logradouro, ''),
                            ',\s*(n[º°o.]?\s*)?[0-9].*$', ''), '\s*,\s*(-|,|$).*$', ''), ' ,-'), ''),
              'numero', coalesce(nullif(btrim(t.numero), ''),
                                 (regexp_match(coalesce(t.logradouro, ''), ',\s*(?:n[º°o.]?\s*)?([0-9]+[A-Za-z]?)'))[1]),
              'complemento', nullif(btrim(t.complemento), ''),
$para$);
COMMIT;
