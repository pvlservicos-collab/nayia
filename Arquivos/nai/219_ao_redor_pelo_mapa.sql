-- 219 (30/09/2026): O "NÃO" VEM COM OS IMÓVEIS AO REDOR, PELO MAPA.
-- Pedro: "pode enviar o não de forma carinhosa, mas já oferecendo imóveis ao
-- redor; quero que tenhamos na nossa base de dados, agora que temos o mapa, essa
-- visão de oferecer imóveis ao redor com as características pedidas".
--
-- "Aqui perto" era nay_bairros_proximos: a ZONA inteira (Ponta Negra -> São
-- Raimundo, Glória...) e nada para vários bairros de uma vez. Agora sai do mapa
-- (geo_bairro_vizinho, migração 149): os bairros que fazem DIVISA com o pedido ou
-- estão a até 3 km, do mais perto ao mais longe. Com as mesmas características
-- (negócio, tipo, quartos, mobília) e, se a faixa de valor estiver vazia, os mais
-- em conta também ao redor. Bairro que o mapa não conhece cai na regra antiga.
--
-- Caso real (Maria Soraia): "Adrianópolis, Vieira Alves, mobiliado, 1 ou 2
-- quartos, até 4 mil" -> não tem nos dois; a 2,5 km, no Chapada, o #5746.
BEGIN;
SET LOCAL lock_timeout = '3s';

CREATE OR REPLACE FUNCTION nai_bairros_ao_redor(p_bairros text[])
 RETURNS text[] LANGUAGE sql STABLE AS $$
  WITH ped AS (SELECT DISTINCT nay_normalizar_lugar(b, true) AS n FROM unnest(p_bairros) b WHERE coalesce(btrim(b), '') <> ''),
  viz AS (SELECT nay_normalizar_lugar(v.vizinho, true) AS n, min(v.km) AS km
            FROM geo_bairro_vizinho v JOIN ped ON nay_normalizar_lugar(v.bairro, true) = ped.n
           WHERE v.divisa OR v.km <= 3
           GROUP BY 1),
  cat AS (SELECT DISTINCT i.bairro, nay_normalizar_lugar(i.bairro, true) AS n
            FROM imoveis i WHERE coalesce(btrim(i.bairro), '') <> ''),
  junto AS (SELECT c.bairro, min(viz.km) AS km
              FROM viz JOIN cat c ON c.n = viz.n OR viz.n LIKE c.n || ' %'   -- "dom pedro i" x "Dom Pedro"
             WHERE c.n NOT IN (SELECT n FROM ped)
             GROUP BY c.bairro)
  SELECT coalesce(
    (SELECT array_agg(bairro ORDER BY km) FROM junto),
    -- o mapa não conhece o bairro: a regra antiga (a zona), sem o próprio pedido
    (SELECT array_agg(b) FROM unnest(nay_bairros_proximos(p_bairros[1])) b WHERE b <> ALL (p_bairros)));
$$;

CREATE OR REPLACE FUNCTION pg_temp.trocar(p_fn regprocedure, p_de text, p_para text, p_vezes int DEFAULT 1)
 RETURNS void LANGUAGE plpgsql AS $$
DECLARE
  d text := pg_get_functiondef(p_fn);
  n int := (length(d) - length(replace(d, p_de, ''))) / length(p_de);
BEGIN
  IF n <> p_vezes THEN
    RAISE EXCEPTION 'trocar em %: esperava % vez(es), achei % -- %', p_fn, p_vezes, n, left(p_de, 60);
  END IF;
  EXECUTE replace(d, p_de, p_para);
END $$;

-- os bairros ao redor saem do mapa, para um ou vários bairros pedidos
SELECT pg_temp.trocar('nai_buscar_por_perfil(bigint,text,text,text,text)',
$a$  v_viz := CASE WHEN v_livre THEN '{}'::text[]
                WHEN cardinality(v_lug_bairros) = 1 THEN nay_bairros_proximos(v_lug_bairros[1])
                WHEN v_lug_bairros IS NOT NULL THEN '{}'::text[]
                ELSE nay_bairros_proximos(btrim(coalesce(p_bairro, ''))) END;
  IF coalesce(array_length(v_viz, 1), 0) > 1 THEN$a$,
$b$  -- 219: AO REDOR PELO MAPA -- divisa ou até 3 km dos bairros pedidos (um ou vários)
  v_viz := CASE WHEN v_livre THEN '{}'::text[]
                ELSE coalesce(nai_bairros_ao_redor(coalesce(v_lug_bairros, ARRAY(
                       SELECT DISTINCT i.bairro FROM imoveis i
                        WHERE coalesce(btrim(i.bairro), '') <> ''
                          AND nay_normalizar_lugar(i.bairro, true) LIKE '%' || nay_normalizar_lugar(p_bairro, true) || '%'))),
                       '{}'::text[]) END;
  IF coalesce(array_length(v_viz, 1), 0) > 0 THEN$b$);

-- faixa vazia: os mais em conta também ao redor
SELECT pg_temp.trocar('nai_buscar_por_perfil(bigint,text,text,text,text)',
$a$    v_mais_barato := v_aqui IS NOT NULL;
$a$, $b$    -- 219: nos bairros pedidos não coube nada? os mais em conta ao redor
    IF v_aqui IS NULL AND coalesce(array_length(v_viz, 1), 0) > 0 THEN
      SELECT string_agg(nai_bloco_oferta(z.c, v_negocio), E'\n\n' ORDER BY z.v DESC) INTO v_alt FROM (
        SELECT i.codigo AS c,
               CASE WHEN v_negocio = 'venda' THEN i.valor_venda
                    ELSE coalesce(i.valor_aluguel, i.valor_venda) END AS v
          FROM imoveis i
         WHERE i.bairro = ANY (v_viz)
           AND nai_oferta_serve(i, k.telefone, NULL, v_q, v_sem, v_com, v_negocio, v_tipo)
           AND (v_q_min IS NULL OR coalesce(i.quartos, 0) BETWEEN v_q_min AND v_q_max)
           AND CASE WHEN v_negocio = 'venda'
                    THEN coalesce(i.valor_venda, 0) > 0
                         AND i.valor_venda <= v_teto * (1 + nai_cfg_int('faixa_acima_pct', 10) / 100.0)
                    ELSE coalesce(i.valor_aluguel, 0) > 0
                         AND i.valor_aluguel <= v_teto * (1 + nai_cfg_int('faixa_acima_pct', 10) / 100.0) END
         ORDER BY 2 DESC LIMIT 5) z;
    END IF;
    v_mais_barato := v_aqui IS NOT NULL OR v_alt IS NOT NULL;
$b$);

-- o "não" carinhoso, já com as opções ao redor
SELECT pg_temp.trocar('nai_buscar_por_perfil(bigint,text,text,text,text)',
$a$    v_txt := 'No ' || v_nome_b || ', não tenho ' || v_nada || ' nesse perfil disponível no momento.' || E'\n\n' ||
             'Mas tenho estas opções aqui perto:' || E'\n\n' || v_alt;$a$,
$b$    v_txt := 'No ' || v_nome_b || ' eu não tenho ' || v_nada || ' nesse perfil agora, mas separei estas opções bem pertinho de lá'
             || CASE WHEN v_mais_barato THEN ', um pouco mais em conta' ELSE '' END || ':' || E'\n\n' || v_alt;$b$);

SELECT pg_temp.trocar('nai_buscar_por_perfil(bigint,text,text,text,text)',
$a$                 || ' nesse perfil, nem nos bairros aqui perto.' END$a$,
$b$                 || ' nesse perfil agora, nem nos bairros aqui pertinho.' END$b$);

-- um imóvel só, mas de fora do que ele pediu (ao redor, ou mais em conta): o card
-- vem com a frase que explica, e não solto como se fosse o que ele pediu
SELECT pg_temp.trocar('nai_buscar_por_perfil(bigint,text,text,text,text)',
$a$    RETURN QUERY SELECT
      (SELECT cc.texto_pronto FROM nai_card_do_imovel(
         (regexp_match(coalesce(v_aqui, '') || coalesce(v_alt, ''), ' #([0-9]{3,5})\*'))[1]::int) cc),$a$,
$b$    RETURN QUERY SELECT
      (CASE WHEN v_aqui IS NULL AND NOT v_livre
              THEN 'No ' || v_nome_b || ' eu não tenho ' || v_nada || ' nesse perfil agora, mas bem pertinho de lá eu tenho este'
                   || CASE WHEN v_mais_barato THEN ', um pouco mais em conta' ELSE '' END || ':' || E'\n\n'
            WHEN v_mais_barato
              THEN 'Nessa faixa de valor eu não tenho, mas tenho este um pouco mais em conta:' || E'\n\n'
            ELSE '' END
       || (SELECT cc.texto_pronto FROM nai_card_do_imovel(
         (regexp_match(coalesce(v_aqui, '') || coalesce(v_alt, ''), ' #([0-9]{3,5})\*'))[1]::int) cc)),$b$);
COMMIT;
