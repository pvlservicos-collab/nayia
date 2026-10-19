-- testes da 418 (rodam dentro do ensaio, antes do ROLLBACK): ./scripts/nay ensaio Arquivos/nai/418_*.sql Arquivos/nai/teste_418.sql
\pset pager off
DO $$
DECLARE a bigint; b bigint;
BEGIN
  -- a Greyce Jane, mesmo texto por dois números (13/10 10:58 e 11:00)
  SELECT j.card INTO a FROM privado.grupo_pedido p JOIN privado.grupo_pedido_junto j ON j.pedido_id = p.id
   WHERE p.texto ILIKE 'Alguém tem apto disponível para aluguel nas regiões do lago azul%' ORDER BY p.enviada_em LIMIT 1;
  SELECT count(DISTINCT j.card) INTO b FROM privado.grupo_pedido p JOIN privado.grupo_pedido_junto j ON j.pedido_id = p.id
   WHERE p.texto ILIKE 'Alguém tem apto disponível para aluguel nas regiões do lago azul%';
  IF b <> 1 THEN RAISE EXCEPTION 'Greyce: % cards (esperado 1)', b; END IF;
  -- Karla Amorim e Juliana Pinheiro, o mesmo pedido da casa térrea na Ponta Negra
  SELECT count(DISTINCT j.card) INTO b FROM privado.grupo_pedido p JOIN privado.grupo_pedido_junto j ON j.pedido_id = p.id
   WHERE p.texto ILIKE '%CASA TERREA EM CONDOMÍNIO NA PONTA NEGRA ATÉ 7,5k MOBILIADA%' AND p.enviada_em > now() - interval '10 days';
  IF b <> 1 THEN RAISE EXCEPTION 'Karla/Juliana: % cards (esperado 1)', b; END IF;
  -- pedidos diferentes da mesma pessoa continuam separados (a Elcy: locação 3.800 e compra 600 mil)
  SELECT count(DISTINCT j.card) INTO b FROM privado.grupo_pedido p JOIN privado.grupo_pedido_junto j ON j.pedido_id = p.id
   WHERE p.id IN (1944, 1948);
  IF b <> 2 THEN RAISE EXCEPTION 'Elcy: % cards (esperado 2)', b; END IF;
  -- Karla Nogueira x Natasha (0,81, sala no Soberane): pessoas e textos diferentes, ficam separadas
  SELECT count(DISTINCT j.card) INTO b FROM privado.grupo_pedido p JOIN privado.grupo_pedido_junto j ON j.pedido_id = p.id
   WHERE p.texto ILIKE 'Alguém com sala%soberane%alugar%' AND p.enviada_em BETWEEN '2026-10-13' AND '2026-10-16';
  IF b < 2 THEN RAISE EXCEPTION 'Soberane: % cards (esperado 2)', b; END IF;
  -- o nosso grupo
  IF NOT privado.grupo_e_nosso('559291005912-1563982274', NULL) OR NOT privado.grupo_e_nosso(NULL, 'altarquia imob easy ai a sinistra do mercado')
     OR privado.grupo_e_nosso('x', 'Top imóveis venda e aluguéis') THEN
    RAISE EXCEPTION 'grupo_e_nosso errado';
  END IF;
  RAISE NOTICE 'teste 418: ok';
END $$;

-- o radar: nenhum pedido dos nossos grupos, e nenhum texto repetido em dois cards
WITH l AS (SELECT x FROM jsonb_array_elements(site_captacao_grupos('todos', 24 * 7, 300)->'pedidos') x)
SELECT count(*) AS cards,
       count(*) FILTER (WHERE x->>'grupo' ILIKE '%imob easy%') AS do_nosso_grupo,
       count(*) FILTER (WHERE (x->>'grupos') ILIKE '%IMOB EASY%') AS com_o_nosso_na_lista,
       count(*) - count(DISTINCT privado.grupo_texto_normal(x->>'texto')) AS texto_repetido
  FROM l;
SELECT (site_captacao_grupos_demanda(30)->>'pedidos')::int AS demanda_pedidos;
SELECT count(*) AS no_painel FROM jsonb_each(site_painel_metricas(current_date - 7, current_date, 'dia')) LIMIT 1;
