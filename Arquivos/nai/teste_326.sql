-- testes da 326 (dentro do ensaio, sem BEGIN/COMMIT)
-- a origem de cada tipo que está na fila hoje
SELECT p.fonte, p.origem, p.codigo, p.ficha_id,
       left(site_origem_do_cadastro(p.codigo, CASE WHEN p.codigo IS NULL THEN p.ficha_id END)::text, 260) AS origem_card
  FROM (SELECT DISTINCT ON (coalesce(origem, fonte)) * FROM nai_cadastro_pendente() ORDER BY coalesce(origem, fonte), codigo) p;

-- juntar: um rascunho do site (A) em outro imóvel (B), com as fotos
CREATE TEMP TABLE par AS
SELECT (SELECT codigo FROM nai_cadastro_pendente() WHERE status = 'Rascunho' AND fotos > 0 ORDER BY codigo LIMIT 1) AS a,
       (SELECT codigo FROM imoveis WHERE status = 'Disponível' ORDER BY codigo LIMIT 1) AS b;
SELECT a, b, (SELECT count(*) FROM imovel_fotos WHERE codigo = a) AS fotos_a, (SELECT count(*) FROM imovel_fotos WHERE codigo = b) AS fotos_b_antes FROM par;
SELECT site_juntar_cadastro(a, NULL, b, true, 'teste') AS juntou FROM par;
SELECT (SELECT status FROM imoveis WHERE codigo = a) AS a_ficou, (SELECT extras->>'atualizacao_de' FROM imoveis WHERE codigo = a) AS a_aponta,
       (SELECT count(*) FROM imovel_fotos WHERE codigo = b) AS fotos_b_depois FROM par;
-- juntar de novo não duplica as fotos
SELECT site_juntar_cadastro(a, NULL, b, true, 'teste') ->> 'fotos' AS fotos_na_segunda_vez FROM par;

-- uma ficha do dono num imóvel
CREATE TEMP TABLE fic AS SELECT (SELECT ficha_id FROM nai_cadastro_pendente() WHERE fonte = 'ficha' ORDER BY ficha_id LIMIT 1) AS f,
                                (SELECT codigo FROM imoveis WHERE status = 'Rascunho' ORDER BY codigo DESC LIMIT 1) AS em;
SELECT f, em, site_juntar_cadastro(NULL, f, em, true, 'teste') AS juntou,
       (SELECT estado || ' #' || codigo FROM captacao_cadastro WHERE id = f) AS ficha_ficou FROM fic;
SELECT 'a ficha saiu da fila (tem de ser 0)' AS o_que, count(*) FROM nai_cadastro_pendente() p, fic WHERE p.ficha_id = fic.f AND p.fonte = 'ficha';

-- erros que têm de ser recusados
DO $t$ BEGIN PERFORM site_juntar_cadastro(1, NULL, 1, false, 't'); RAISE EXCEPTION 'devia recusar'; EXCEPTION WHEN raise_exception THEN RAISE NOTICE 'recusou o mesmo imóvel: %', SQLERRM; END $t$;
DO $t$ BEGIN PERFORM site_juntar_cadastro(NULL, NULL, 1, false, 't'); RAISE EXCEPTION 'devia recusar'; EXCEPTION WHEN raise_exception THEN RAISE NOTICE 'recusou sem origem: %', SQLERRM; END $t$;
