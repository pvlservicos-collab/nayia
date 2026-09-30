-- 218 (30/09/2026): A MARIA SORAIA MANDOU O FILTRO INTEIRO E NÃO RECEBEU OPÇÃO.
-- Pedro: "ela tá errando ... a menina já mandou os filtros, é só ela mandar as
-- opções". Ela escreveu: "Mobiliado / R$4,000 / 1 quarto ou 2 / Adrianópolis,
-- Vieira Alves, por essa região"; depois "mobiliado para a região da Ponta Negra /
-- 2 quartos / até 4 mil". Três defeitos na busca, medidos reproduzindo a chamada:
--
-- 1. "1 OU 2" VIRAVA 12 QUARTOS. v_q juntava os dígitos ("1 ou 2" -> 12) e
--    nai_oferta_serve pede quartos IGUAL -> nada, em bairro nenhum. Agora é faixa:
--    "1 ou 2" = de 1 a 2; "2 ou mais", "no mínimo 2", "2+" = 2 para cima; um
--    número só continua exato, como antes.
-- 2. VÁRIOS LUGARES NA MESMA RESPOSTA. "Adrianópolis, Vieiralves" buscava só o
--    Nossa Senhora das Graças (o conjunto da 206) e perdia o Adrianópolis -- e,
--    antes da 206, a frase inteira não batia com bairro nenhum. Agora cada pedaço
--    (vírgula, "e", "ou", "/") vira os bairros dele, e a lista diz "No Adrianópolis
--    e Vieiralves ...".
-- 3. "PONTA NEGRA 2 QUARTOS" VIRAVA "PONTA NEGRA II QUARTOS". nai_corrigir_nomes
--    trocava a janela "ponta negra 2" pelo nome "... Ponta Negra II" do vocabulário:
--    o número de quartos sumia. Número solto não é pedaço de nome escrito errado.
BEGIN;
SET LOCAL lock_timeout = '3s';

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

-- 1. QUARTOS EM FAIXA ------------------------------------------------------
SELECT pg_temp.trocar('nai_buscar_por_perfil(bigint,text,text,text,text)',
$a$  v_q      int := NULLIF(regexp_replace(coalesce(p_quartos, ''), '[^0-9]', '', 'g'), '')::int;$a$,
$b$  v_q      int;            -- 218: um número só = exato (como antes); faixa fica em v_q_min/v_q_max
  v_q_min  int;
  v_q_max  int;
  v_multi  boolean := false;  -- 218: vários lugares na mesma resposta$b$);

SELECT pg_temp.trocar('nai_buscar_por_perfil(bigint,text,text,text,text)',
$a$  SELECT * INTO k FROM nai_contato WHERE id = t.contato_id;
$a$, $b$  SELECT * INTO k FROM nai_contato WHERE id = t.contato_id;

  -- 218: QUARTOS -- "1 ou 2" é de 1 a 2 (antes virava 12); "2 ou mais" é 2 para cima
  SELECT min(x[1]::int), max(x[1]::int) INTO v_q_min, v_q_max
    FROM regexp_matches(coalesce(p_quartos, ''), '([0-9]{1,2})', 'g') AS x
   WHERE x[1]::int BETWEEN 1 AND 10;
  IF v_q_min IS NOT NULL AND lower(unaccent(coalesce(p_quartos, ''))) ~ '(\+|ou mais|no minimo|pelo menos|a partir)' THEN
    v_q_max := 10;
  END IF;
  v_q := CASE WHEN v_q_min IS NOT NULL AND v_q_min = v_q_max THEN v_q_min END;
$b$);

SELECT pg_temp.trocar('nai_buscar_por_perfil(bigint,text,text,text,text)',
$a$               OR v_tipo IS NOT NULL OR v_q IS NOT NULL;$a$,
$b$               OR v_tipo IS NOT NULL OR v_q_min IS NOT NULL;$b$);

SELECT pg_temp.trocar('nai_buscar_por_perfil(bigint,text,text,text,text)',
$a$       AND nai_oferta_serve(i, k.telefone, v_teto, v_q, v_sem, v_com, v_negocio, v_tipo)
$a$, $b$       AND nai_oferta_serve(i, k.telefone, v_teto, v_q, v_sem, v_com, v_negocio, v_tipo)
       AND (v_q_min IS NULL OR coalesce(i.quartos, 0) BETWEEN v_q_min AND v_q_max)  -- 218
$b$, 2);

SELECT pg_temp.trocar('nai_buscar_por_perfil(bigint,text,text,text,text)',
$a$           AND nai_oferta_serve(i, k.telefone, v_teto, v_q, v_sem, v_com, v_negocio, NULL)
$a$, $b$           AND nai_oferta_serve(i, k.telefone, v_teto, v_q, v_sem, v_com, v_negocio, NULL)
           AND (v_q_min IS NULL OR coalesce(i.quartos, 0) BETWEEN v_q_min AND v_q_max)  -- 218
$b$);

-- 2. VÁRIOS LUGARES --------------------------------------------------------
SELECT pg_temp.trocar('nai_buscar_por_perfil(bigint,text,text,text,text)',
$a$  v_lug_bairros := nai_bairros_do_lugar(p_bairro);
  IF v_lug_bairros IS NOT NULL THEN
    v_lug_rx := (SELECT string_agg('(' || l.expressao || ')', '|') FROM nai_lugar_citado(p_bairro) l
                  WHERE l.tipo = 'conjunto');
    v_lug_rotulo := nai_lugar_rotulo(p_bairro);$a$,
$b$  v_lug_bairros := nai_bairros_do_lugar(p_bairro);
  -- 218: VÁRIOS LUGARES ("Adrianópolis, Vieiralves"): cada pedaço vira os bairros
  -- dele -- o do conjunto/avenida, ou o bairro do catálogo que bate com o nome
  IF p_bairro ~ '(,|;|/|\me\M|\mou\M)' THEN
    SELECT array_agg(DISTINCT z.b), nai_lista_pt(array_agg(DISTINCT z.nome))
      INTO v_lug_bairros, v_lug_rotulo
      FROM (SELECT initcap(btrim(p.x)) AS nome,
                   unnest(coalesce(nai_bairros_do_lugar(p.x),
                          ARRAY(SELECT DISTINCT i.bairro FROM imoveis i
                                 WHERE coalesce(btrim(i.bairro), '') <> ''
                                   AND nay_normalizar_lugar(i.bairro, true) LIKE '%' || nay_normalizar_lugar(p.x, true) || '%'))) AS b
              FROM unnest(regexp_split_to_array(p_bairro, '\s*(,|;|/|\me\M|\mou\M)\s*')) AS p(x)
             WHERE length(btrim(p.x)) >= 3) z;
    v_multi := v_lug_bairros IS NOT NULL;
  END IF;
  IF v_lug_bairros IS NOT NULL THEN
    v_lug_rx := (SELECT string_agg('(' || l.expressao || ')', '|') FROM nai_lugar_citado(p_bairro) l
                  WHERE l.tipo = 'conjunto');
    IF NOT v_multi THEN v_lug_rotulo := nai_lugar_rotulo(p_bairro); END IF;$b$);

-- com vários lugares o rótulo é a lista deles (e não o "No Vieiralves" da área)
SELECT pg_temp.trocar('nai_buscar_por_perfil(bigint,text,text,text,text)',
$a$  IF v_lug_rotulo IS NOT NULL AND NOT EXISTS (SELECT 1 FROM nai_area_citada(p_bairro)) THEN$a$,
$b$  IF v_lug_rotulo IS NOT NULL AND (v_multi OR NOT EXISTS (SELECT 1 FROM nai_area_citada(p_bairro))) THEN$b$);

-- 4. "ATÉ 4 MIL" NÃO PODE DAR "NÃO TENHO" QUANDO HÁ MAIS EM CONTA ----------
-- A busca mostra a FAIXA perto do valor (faixa_abaixo_pct / faixa_acima_pct: de
-- 3.200 a 4.400 para "até 4 mil"). A Ponta Negra tinha o #5724 (2 quartos,
-- mobiliado, R$ 2.600) e a Nay disse que não tinha nada. A faixa continua sendo
-- a primeira escolha; vazia, entram os que cabem no valor, os mais perto dele
-- primeiro, com o aviso de que são mais em conta.
SELECT pg_temp.trocar('nai_buscar_por_perfil(bigint,text,text,text,text)',
$a$  v_multi  boolean := false;  -- 218: vários lugares na mesma resposta$a$,
$b$  v_multi  boolean := false;  -- 218: vários lugares na mesma resposta
  v_mais_barato boolean := false;  -- 218: a faixa vazia, e saíram os mais em conta$b$);

SELECT pg_temp.trocar('nai_buscar_por_perfil(bigint,text,text,text,text)',
$a$  -- NADA AQUI NEM PERTO (105, Tel 23/09: "nao e para ocorrer esse tipo de$a$,
$b$  -- 218: A FAIXA VAZIA, MAS HÁ O QUE CABE NO VALOR ("até 4 mil" e o #5724 de
  -- R$ 2.600 ficava de fora da faixa de 3.200 a 4.400)
  IF v_aqui IS NULL AND v_alt IS NULL AND v_teto IS NOT NULL THEN
    SELECT string_agg(nai_bloco_oferta(z.c, v_negocio), E'\n\n' ORDER BY z.v DESC) INTO v_aqui FROM (
      SELECT i.codigo AS c,
             CASE WHEN v_negocio = 'venda' THEN i.valor_venda
                  ELSE coalesce(i.valor_aluguel, i.valor_venda) END AS v
        FROM imoveis i
       WHERE (v_livre OR nay_normalizar_lugar(i.bairro, true) LIKE '%' || nay_normalizar_lugar(p_bairro, true) || '%'
              OR i.bairro = ANY (v_lug_bairros))
         AND nai_oferta_serve(i, k.telefone, NULL, v_q, v_sem, v_com, v_negocio, v_tipo)
         AND (v_q_min IS NULL OR coalesce(i.quartos, 0) BETWEEN v_q_min AND v_q_max)
         AND CASE WHEN v_negocio = 'venda'
                  THEN coalesce(i.valor_venda, 0) > 0
                       AND i.valor_venda <= v_teto * (1 + nai_cfg_int('faixa_acima_pct', 10) / 100.0)
                  ELSE coalesce(i.valor_aluguel, 0) > 0
                       AND i.valor_aluguel <= v_teto * (1 + nai_cfg_int('faixa_acima_pct', 10) / 100.0) END
       ORDER BY 2 DESC LIMIT 5) z;
    v_mais_barato := v_aqui IS NOT NULL;
    IF v_mais_barato THEN
      PERFORM nai_anotar(p_turno, 7, 'faixa_vazia_mais_em_conta', 'mudou', 'nada na faixa do valor: saíram os que cabem nele');
    END IF;
  END IF;

  -- NADA AQUI NEM PERTO (105, Tel 23/09: "nao e para ocorrer esse tipo de$b$);

SELECT pg_temp.trocar('nai_buscar_por_perfil(bigint,text,text,text,text)',
$a$    v_txt := CASE WHEN v_livre THEN 'Tenho estas opções:'
                  ELSE 'No ' || v_nome_b || ' eu tenho estas opções:' END$a$,
$b$    v_txt := CASE WHEN v_mais_barato AND v_livre
                    THEN 'Nessa faixa de valor eu não tenho, mas tenho estas opções mais em conta:'
                  WHEN v_mais_barato
                    THEN 'No ' || v_nome_b || ', nessa faixa de valor eu não tenho, mas tenho estas opções mais em conta:'
                  WHEN v_livre THEN 'Tenho estas opções:'
                  ELSE 'No ' || v_nome_b || ' eu tenho estas opções:' END$b$);

-- 3. NÚMERO NÃO É NOME ESCRITO ERRADO --------------------------------------
SELECT pg_temp.trocar('nai_corrigir_nomes(text)',
$a$             'para','pra','com','sem','por','pelo','pela','e','ou','que','se']));
$a$, $b$             'para','pra','com','sem','por','pelo','pela','e','ou','que','se']));
      -- 218: número solto na janela não é pedaço de nome ("ponta negra 2 quartos"
      -- virava "ponta negra ii quartos" e o número de quartos sumia)
      CONTINUE WHEN j > 1 AND EXISTS (SELECT 1 FROM unnest(v_palavras[i : i + j - 1]) w
                                       WHERE regexp_replace(w, '[^[:alnum:]]', '', 'g') ~ '^[0-9]+$');
$b$);

INSERT INTO nai_caso (quem, frase, pergunta, esperado, regra) VALUES
  ('Pedro 30/09', 'ponta negra 2 quartos', 'nomes', 'ponta negra 2 quartos', 'número de quartos não vira nome (II)');
COMMIT;
