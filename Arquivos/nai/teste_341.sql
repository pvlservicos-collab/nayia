-- Testes da 341 (rodam dentro do ensaio, antes do ROLLBACK).
CREATE TEMP TABLE _t (caso text, esperado text, veio text);

INSERT INTO _t SELECT 'a mobília dos cinco', '462=semi-mobiliado, 2411=semi-mobiliado, 2944=mobiliado, 4207=mobiliado, 5609=mobiliado',
  (SELECT string_agg(codigo || '=' || mobilia, ', ' ORDER BY codigo) FROM imoveis WHERE codigo IN (2944, 4207, 5609, 462, 2411));
INSERT INTO _t SELECT '2944: característica e financiamento', '{Mobiliado}/Sim',
  (SELECT caracteristicas::text || '/' || (extras->>'aceita financiamento') FROM imoveis WHERE codigo = 2944);

-- a regra da busca (a mesma expressão de core_imovel_busca) passa a ler o que foi corrigido
INSERT INTO _t SELECT 'como a busca vai ler', '462=semi, 2411=semi, 2944=mobiliado, 4207=mobiliado, 5609=mobiliado',
  (SELECT string_agg(codigo || '=' || CASE WHEN mobilia ~* '^\s*semi' THEN 'semi' WHEN mobilia ~* '^\s*mobiliad' THEN 'mobiliado' ELSE '?' END,
                     ', ' ORDER BY codigo) FROM imoveis WHERE codigo IN (2944, 4207, 5609, 462, 2411));

-- nada além disso mudou: a situação, o anúncio, os valores e a trava dos cinco estão como antes (a foto da busca
-- ainda é a de antes do ensaio, e ela guarda valores e se o imóvel é ofertável)
INSERT INTO _t SELECT 'situação, valores e oferta não mudaram', '5',
  (SELECT count(*)::text FROM imoveis i JOIN core_imovel_busca b USING (codigo)
    WHERE i.codigo IN (2944, 4207, 5609, 462, 2411)
      AND i.valor_aluguel IS NOT DISTINCT FROM b.valor_aluguel AND i.valor_venda IS NOT DISTINCT FROM b.valor_venda
      AND b.ofertavel AND coalesce(i.disponivel, true) AND coalesce(i.publicado_no_site, false) AND NOT coalesce(i.bloqueado, false)
      AND NOT coalesce(i.travado, false) = NOT coalesce((SELECT o.travado FROM imoveis o WHERE o.codigo = i.codigo), false));
INSERT INTO _t SELECT 'nenhum outro imóvel foi tocado (mobília)', '0',
  (SELECT count(*)::text FROM imoveis i JOIN core_imovel_busca b USING (codigo)
    WHERE i.codigo NOT IN (2944, 4207, 5609, 462, 2411)
      AND b.mobilia IS DISTINCT FROM CASE WHEN i.mobilia ~* '^\s*semi' THEN 'semi' WHEN i.mobilia ~* '^\s*mobiliad' THEN 'mobiliado'
                                          WHEN i.mobilia ~* 'ar.condicionado' THEN 'nao' END);

SELECT CASE WHEN esperado = veio THEN 'ok' ELSE 'FALHOU' END AS r, caso,
       CASE WHEN esperado = veio THEN '' ELSE 'esperado ' || esperado || ', veio ' || coalesce(veio, '(nulo)') END AS detalhe
  FROM _t;

DO $$
DECLARE n int; m int;
BEGIN
  SELECT count(*) FILTER (WHERE esperado IS DISTINCT FROM veio), count(*) INTO n, m FROM _t;
  IF n > 0 THEN RAISE EXCEPTION '341: % de % teste(s) falharam', n, m; END IF;
  RAISE NOTICE '341: % testes, todos certos', m;
END $$;
