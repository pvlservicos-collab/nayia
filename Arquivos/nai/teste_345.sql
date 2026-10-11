-- Testes da 345 (rodam dentro do ensaio, antes do ROLLBACK).
CREATE TEMP TABLE _t (caso text, esperado text, veio text);

-- nenhuma linha de imóvel some, e o retrato de antes tem todas
INSERT INTO _t SELECT 'nenhum imóvel apagado', (SELECT count(*)::text FROM privado.imovel_antes_345), (SELECT count(*)::text FROM imoveis);

-- mobília: só os quatro rótulos (ou vazio)
INSERT INTO _t SELECT 'mobília só nos 4 rótulos', '0',
  (SELECT count(*)::text FROM imoveis WHERE coalesce(btrim(mobilia), '') <> ''
      AND mobilia NOT IN ('sem nada', 'só climatizado', 'com modulados e ar', 'mobiliado'));
INSERT INTO _t SELECT 'nível lê as redações antigas e novas', 'semi/semi/mobiliado/mobiliado/climatizado/climatizado/nada/nada/-',
  concat_ws('/', nay_mobilia_nivel('semi-mobiliado (moveis planejados + ar)'), nay_mobilia_nivel('com modulados e ar'),
            nay_mobilia_nivel('mobiliado (moveis + cama + tudo)'), nay_mobilia_nivel('mobiliado'),
            nay_mobilia_nivel('so ar-condicionado'), nay_mobilia_nivel('só climatizado'),
            nay_mobilia_nivel('Sem mobília'), nay_mobilia_nivel('sem nada'), coalesce(nay_mobilia_nivel(''), '-'));
INSERT INTO _t SELECT '2944 (Maison Rochelle, corrigido na 341) segue mobiliado', 'mobiliado', (SELECT mobilia FROM imoveis WHERE codigo = 2944);
INSERT INTO _t SELECT 'o campo vazio com a característica Semi-Mobiliado foi preenchido', '0',
  (SELECT count(*)::text FROM imoveis WHERE coalesce(btrim(mobilia), '') = ''
      AND EXISTS (SELECT 1 FROM unnest(caracteristicas) c WHERE c ILIKE 'semi-mobiliado'));
INSERT INTO _t SELECT 'quem tinha semi no campo continua semi (nível)', 'true',
  (SELECT bool_and(nay_mobilia_nivel(i.mobilia) = 'semi') FROM privado.imovel_antes_345 a JOIN imoveis i USING (codigo)
    WHERE a.mobilia ILIKE 'semi%')::text;

-- observação
INSERT INTO _t SELECT 'observação veio do bloco OBS do anúncio', 'true',
  (SELECT (count(*) FILTER (WHERE coalesce(i.observacao, '') <> '') = count(*))::text
     FROM imovel_ficha f JOIN imoveis i USING (codigo) WHERE f.encontrado AND coalesce(btrim(f.observacoes), '') <> '');
INSERT INTO _t SELECT '2944: a observação é a lista de móveis do anúncio', 'true',
  (SELECT (observacao ILIKE '%sof%' AND observacao ILIKE '%geladeira%')::text FROM imoveis WHERE codigo = 2944);
INSERT INTO _t SELECT 'descrição longa NÃO virou observação', '0',
  (SELECT count(*)::text FROM imoveis WHERE length(coalesce(observacao, '')) > 1000);

-- área por tipo
INSERT INTO _t SELECT 'casa não tem mais área total (virou terreno)', '0',
  (SELECT count(*)::text FROM imoveis WHERE tipo IN ('Casa', 'Casa de condomínio') AND area_total IS NOT NULL);
INSERT INTO _t SELECT 'o terreno guarda o valor da área total de antes', 'true',
  (SELECT bool_and((i.extras ->> 'tamanho do terreno') ~ '^\d') FROM privado.imovel_antes_345 a JOIN imoveis i USING (codigo)
    WHERE i.tipo IN ('Casa', 'Casa de condomínio') AND coalesce(a.area_total, 0) > 0)::text;
INSERT INTO _t SELECT 'apartamento mantém a área total', 'true',
  (SELECT bool_and(i.area_total IS NOT DISTINCT FROM a.area_total) FROM privado.imovel_antes_345 a JOIN imoveis i USING (codigo)
    WHERE i.tipo = 'Apartamento')::text;

-- condomínio
INSERT INTO _t SELECT 'imóvel com nome de condomínio ligado pelo id', 'true',
  (SELECT (count(*) FILTER (WHERE condo_id IS NULL) < 400)::text FROM imoveis
    WHERE coalesce(btrim(condominio_nome), '') <> '' AND condominio_nome !~* 'identificad');
INSERT INTO _t SELECT '"Condomínio não identificado" não foi ligado', '0',
  (SELECT count(*)::text FROM imoveis WHERE condominio_nome ~* 'identificad' AND condo_id IS NOT NULL
      AND codigo IN (SELECT codigo FROM privado.imovel_antes_345 WHERE condo_id IS NULL));
INSERT INTO _t SELECT 'a ficha do Maison Rochelle ganhou o lazer do anúncio', 'true',
  (SELECT (cardinality(f.lazer) >= 3 AND EXISTS (SELECT 1 FROM unnest(f.lazer) x WHERE x ILIKE 'piscina'))::text
     FROM condominio_ficha f JOIN imoveis i ON i.condo_id = f.condominio_id WHERE i.codigo = 2944 LIMIT 1);
INSERT INTO _t SELECT 'apartamento com condomínio não tem mais Piscina na própria lista', '0',
  (SELECT count(*)::text FROM imoveis i WHERE i.condo_id IS NOT NULL AND i.tipo ~* '^apartamento'
      AND EXISTS (SELECT 1 FROM unnest(i.caracteristicas) x WHERE x ILIKE 'piscina' OR x ILIKE 'elevador' OR x ILIKE 'salão de festas'));
INSERT INTO _t SELECT 'casa de condomínio mantém a piscina (pode ser da casa)', 'true',
  (SELECT (count(*) > 0)::text FROM imoveis WHERE tipo = 'Casa de condomínio' AND EXISTS (SELECT 1 FROM unnest(caracteristicas) x WHERE x ILIKE 'piscina'));
INSERT INTO _t SELECT 'casa de condomínio NÃO tem mais portaria na própria lista', '0',
  (SELECT count(*)::text FROM imoveis WHERE tipo = 'Casa de condomínio' AND condo_id IS NOT NULL
      AND EXISTS (SELECT 1 FROM unnest(caracteristicas) x WHERE x ILIKE 'portaria' OR x ILIKE 'guarita%' OR x ILIKE 'salão de festas'));
INSERT INTO _t SELECT 'a mobília/climatizado NÃO saiu da lista do imóvel', 'true',
  (SELECT (count(*) > 300)::text FROM imoveis WHERE EXISTS (SELECT 1 FROM unnest(caracteristicas) x WHERE x ILIKE '%mobiliado' OR x ILIKE 'climatizado'));
INSERT INTO _t SELECT 'extras não tem mais a chave das características do condomínio', '0',
  (SELECT count(*)::text FROM imoveis WHERE extras ? 'caracteristicas do condominio');
INSERT INTO _t SELECT 'fichas com elevador decidido cresceram', 'true',
  (SELECT (count(*) FILTER (WHERE coalesce(btrim(elevador), '') <> '') > 20)::text FROM condominio_ficha);
INSERT INTO _t SELECT 'taxa por quartos entrou em fichas de prédio', 'true',
  (SELECT (count(*) FILTER (WHERE taxas <> '[]'::jsonb) > 20)::text FROM condominio_ficha);
INSERT INTO _t SELECT 'o retrato da ficha de antes existe', 'true', (SELECT (count(*) >= 35)::text FROM privado.condominio_ficha_antes_345);

SELECT CASE WHEN esperado = veio THEN 'ok' ELSE 'FALHOU' END AS r, caso,
       CASE WHEN esperado = veio THEN '' ELSE 'esperado ' || esperado || ', veio ' || coalesce(veio, '(nulo)') END AS detalhe
  FROM _t;

-- os números, para o relato
SELECT coalesce(mobilia, '(vazio)') AS mobilia, count(*) FROM imoveis GROUP BY 1 ORDER BY 2 DESC;
SELECT count(*) FILTER (WHERE coalesce(observacao, '') <> '') AS com_observacao,
       count(*) FILTER (WHERE condo_id IS NOT NULL) AS ligados_ao_condominio,
       (SELECT count(*) FROM condominio_ficha) AS fichas,
       (SELECT count(*) FROM condominio_ficha WHERE cardinality(lazer || seguranca || comodidades) > 0) AS fichas_com_caracteristicas,
       (SELECT count(*) FROM condominio_ficha WHERE taxas <> '[]'::jsonb) AS fichas_com_taxa,
       (SELECT count(*) FROM condominio_ficha WHERE coalesce(elevador, '') <> '') AS fichas_com_elevador
  FROM imoveis;

DO $$
DECLARE n int; m int;
BEGIN
  SELECT count(*) FILTER (WHERE esperado IS DISTINCT FROM veio), count(*) INTO n, m FROM _t;
  IF n > 0 THEN RAISE EXCEPTION '345: % de % teste(s) falharam', n, m; END IF;
  RAISE NOTICE '345: % testes, todos certos', m;
END $$;
