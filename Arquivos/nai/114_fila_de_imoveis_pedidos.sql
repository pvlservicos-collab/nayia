-- =====================================================================
-- NAI -- 114: pediu dois imoveis, recebe os dois (Tel, 23/09/2026)
--
-- Ele: "ve la no 81943439 porque ele pediu 2 imoveis e nao mandamos os 2, tem
-- que ter fila de mandagem conforme a solicitacao do cliente".
--
-- O CASO (turno 10647, 12:48). Ele colou DOIS imoveis numa mensagem so:
--   "pode ver se aina esta disponivel esse AREZZO? CONDOMINIO RESIDENCIAL
--    CONQUISTA TARUMA / 2 quartos / mobiliado / 2.1k (incluso a tx)..."
--
-- Ela mandou o card do Arezzo e, para o segundo, fez uma BUSCA POR BAIRRO
-- ("No Tarumã eu tenho estas opções") em vez de mandar o card dele. As fotos
-- sairam so de um.
--
-- DOIS MOTIVOS, e os dois sao consertados aqui:
--
--   1. O ARezzo NAO ERA RECONHECIDO PELO NOME. A regra do nome exato pedia 8
--      letras no nucleo, e "arezzo" tem 6. Medido: baixando para 6 entram
--      quatro condominios -- arezzo, everest, tapajos, topazio -- e fica de
--      fora "taruma", que tambem e nome de BAIRRO e nao pode virar imovel.
--
--   2. O FLUXO INTEIRO E DE UM IMOVEL SO. O turno guarda UM codigo, a
--      montagem manda UM card. Quando ele pede dois, o segundo se perde.
--      Agora existe fila: terminado o primeiro, os outros que ele pediu saem
--      atras, cada um com o seu card e as suas fotos, na ordem em que ele
--      escreveu.
--
-- O ESPACAMENTO DA 113 VALE AQUI TAMBEM: o card do segundo imovel so sai
-- depois das fotos do primeiro terminarem.
-- =====================================================================

\set ON_ERROR_STOP on

BEGIN;

-- 1 -------------------------- NOME CURTO TAMBEM E NOME (arezzo, tapajos...)
CREATE OR REPLACE FUNCTION public.nai_imovel_pelo_condominio(p_texto text, p_telefone text)
 RETURNS integer[]
 LANGUAGE sql
 STABLE
AS $function$
  -- O NOME ESCRITO CERTO MANDA. A parecenca e ULTIMO RECURSO: so entra quando
  -- nenhum nome bateu pela escrita.
  WITH certo AS (
    -- 1. nome inteiro, como esta no cadastro (16/09)
    SELECT v.codigos FROM vw_condominio_som v
     WHERE length(v.nome) >= 8
       AND position(lower(unaccent(v.nome)) IN lower(unaccent(coalesce(p_texto, '')))) > 0
    UNION ALL
    -- 2. o nucleo, sem Condominio/Residencial/Edificio (86).
    -- O piso caiu de 8 para 6 letras (114): "Arezzo" tem 6 e ficava invisivel.
    -- Isto e casamento EXATO de palavra, nao parecenca -- por isso da para
    -- baixar sem risco. O que NAO pode entrar e nucleo que tambem e nome de
    -- bairro: "Taruma" e condominio E bairro, e viraria imovel toda vez que
    -- alguem falasse do bairro.
    SELECT v.codigos FROM vw_condominio_som v
     WHERE length(coalesce(v.nucleo, '')) >= 6
       AND NOT EXISTS (SELECT 1 FROM imoveis i
                        WHERE lower(unaccent(coalesce(i.bairro, ''))) = lower(unaccent(v.nucleo)))
       AND lower(unaccent(coalesce(p_texto, ''))) ~
           ('\m' || regexp_replace(v.nucleo, '([.^$*+?()\[\]{}|\-])', '\\\1', 'g') || '\M')
    UNION ALL
    -- 3. a chave de som IGUAL (88): "aquarele" = Acquarelle
    SELECT v.codigos FROM vw_condominio_som v, nai_pedacos_de_nome(p_texto) g
     WHERE length(v.chave) >= 7 AND length(g.chave) >= 7
       AND (position(v.chave IN g.chave) > 0
            OR (length(g.chave) >= 9 AND v.chave LIKE g.chave || '%'))
  ),
  -- 4. PARECIDO (89), so se nada acima bateu
  parecido AS (
    SELECT v.codigos, similarity(v.chave, g.chave) AS s
      FROM vw_condominio_som v, nai_pedacos_de_nome(p_texto) g
     WHERE NOT EXISTS (SELECT 1 FROM certo)
       AND length(v.chave) >= 7 AND length(g.chave) >= 7
       AND similarity(v.chave, g.chave) >= 0.50
  ),
  melhor AS (
    SELECT codigos FROM parecido
     WHERE s >= (SELECT max(s) - 0.05 FROM parecido)
  )
  SELECT coalesce((SELECT array_agg(DISTINCT c)
                     FROM (SELECT unnest(codigos) AS c FROM certo
                           UNION ALL
                           SELECT unnest(codigos) FROM melhor) x), '{}');
$function$;

-- 2 --------------------- TUDO QUE ELE PEDIU, NA ORDEM EM QUE ESCREVEU
CREATE OR REPLACE FUNCTION public.nai_imoveis_pedidos(p_texto text, p_telefone text)
 RETURNS integer[]
 LANGUAGE sql
 STABLE
AS $function$
  WITH t AS (SELECT lower(unaccent(coalesce(p_texto, ''))) AS s),
  -- os codigos que ele escreveu, e que existem no catalogo
  por_codigo AS (
    SELECT x::int AS c, strpos(coalesce(p_texto, ''), x) AS pos
      FROM unnest(coalesce(nay_codigos_citados(coalesce(p_texto, '')), '{}'::text[])) x
     WHERE x ~ '^[0-9]{3,5}$'
       AND EXISTS (SELECT 1 FROM imoveis i WHERE i.codigo::text = x)
  ),
  -- e os que ele chamou pelo nome do condominio
  por_nome AS (
    SELECT unnest(v.codigos) AS c,
           coalesce(nullif(strpos(t.s, lower(unaccent(v.nucleo))), 0), 9999) AS pos
      FROM vw_condominio_som v, t
     WHERE v.codigos && nai_imovel_pelo_condominio(p_texto, p_telefone)
  )
  SELECT coalesce((
    SELECT array_agg(c ORDER BY pos, c)
      FROM (SELECT c, min(pos) AS pos
              FROM (SELECT * FROM por_codigo UNION ALL SELECT * FROM por_nome) u
             GROUP BY c) z), '{}');
$function$;

-- 3 ------------------------------- A FILA: O QUE SOBROU SAI ATRAS
CREATE OR REPLACE FUNCTION public.nai_fila_dos_outros_imoveis(p_turno bigint, p_escreveu text)
 RETURNS integer
 LANGUAGE plpgsql
AS $function$
DECLARE
  t       nai_turno;
  k       nai_contato;
  v_cods  int[];
  v_ja    int[];
  v_ordem int;
  c       int;
  f       record;
  v_card  text;
  n       int := 0;
  v_teto  int := 3;   -- no maximo tres a mais: fila nao e enxurrada
BEGIN
  SELECT * INTO t FROM nai_turno WHERE id = p_turno;
  IF t.id IS NULL THEN RETURN 0; END IF;
  SELECT * INTO k FROM nai_contato WHERE id = t.contato_id;

  v_cods := nai_imoveis_pedidos(coalesce(nullif(p_escreveu, ''), t.texto), k.telefone);
  IF coalesce(array_length(v_cods, 1), 0) < 2 THEN RETURN 0; END IF;

  -- o que JA foi para a caixa neste turno nao entra de novo
  SELECT coalesce(array_agg(DISTINCT s.codigo), '{}') INTO v_ja
    FROM nai_saida s WHERE s.turno_id = p_turno AND s.codigo IS NOT NULL;
  SELECT coalesce(max(s.ordem), 0) INTO v_ordem FROM nai_saida s WHERE s.turno_id = p_turno;

  FOREACH c IN ARRAY v_cods LOOP
    EXIT WHEN n >= v_teto;
    CONTINUE WHEN c = ANY (v_ja);
    -- imovel que a Nay nao pode oferecer (parceiro, fora do mercado) nao entra
    CONTINUE WHEN NOT EXISTS (SELECT 1 FROM imoveis i
                               WHERE i.codigo = c
                                 AND nay_esta_no_mercado(i.disponivel, i.bloqueado, i.publicado_no_site)
                                 AND NOT coalesce(i.e_parceiro, false));

    SELECT cc.texto_pronto INTO v_card FROM nai_card_do_imovel(c) cc;
    CONTINUE WHEN v_card IS NULL;

    v_ordem := v_ordem + 1;
    PERFORM nai_enfileirar_texto(p_turno, NULL, t.contato_id, 'turno', v_card, 'resposta', v_ordem);

    FOR f IN SELECT * FROM nai_imagens_do_envio(c) LOOP
      v_ordem := v_ordem + 1;
      INSERT INTO nai_saida (turno_id, contato_id, papel_destino, chave_destino, tipo, imagem_url, codigo, ordem, motivo)
           VALUES (p_turno, t.contato_id, 'turno', '', 'imagem', f.url, c, v_ordem,
                   CASE WHEN f.e_colagem THEN 'colagem' ELSE 'foto' END);
    END LOOP;

    n := n + 1;
  END LOOP;

  IF n > 0 THEN
    PERFORM nai_anotar(p_turno, 22, 'fila_de_imoveis', 'mudou',
                       'ele pediu ' || array_length(v_cods, 1) || ' imóveis; ' || n || ' foram para a fila');
  END IF;
  RETURN n;
END;
$function$;

-- 4 ------------------------------- LIGADA NA MONTAGEM, ANTES DO ESPACAMENTO
DO $mig$
DECLARE v_def text; v_alvo text;
BEGIN
  v_def := pg_get_functiondef('nai_enfileirar_resposta'::regproc);
  IF position('nai_fila_dos_outros_imoveis' IN v_def) > 0 THEN
    RAISE NOTICE 'a fila ja esta ligada'; RETURN;
  END IF;
  v_alvo := '  PERFORM nai_espacar_depois_das_fotos(p_turno);';
  IF position(v_alvo IN v_def) = 0 THEN
    RAISE EXCEPTION 'nao achei o espacamento da 113';
  END IF;
  EXECUTE replace(v_def, v_alvo,
       '  -- A FILA DOS OUTROS IMOVEIS (114): ele pediu dois, recebe dois.' || E'\n'
    || '  -- Vem ANTES do espacamento de proposito -- assim o card do segundo' || E'\n'
    || '  -- tambem espera as fotos do primeiro terminarem.' || E'\n'
    || '  PERFORM nai_fila_dos_outros_imoveis(p_turno, p_escreveu);' || E'\n' || E'\n'
    || v_alvo);
  RAISE NOTICE 'fila ligada na montagem';
END $mig$;

COMMIT;

SELECT 'o Arezzo agora e reconhecido?' AS o,
       nai_imovel_pelo_condominio('pode ver se aina está disponível esse Arezzo?', '') AS pelo_nome;
SELECT 'os dois imoveis da mensagem dele' AS o,
       nai_imoveis_pedidos('pode ver se aina está disponível esse Arezzo? Condomínio Residencial Conquista Tarumã / 2 quartos / mobiliado / 2.1k (incluso a tx)', '') AS na_ordem;
SELECT 'e o bairro Taruma nao vira imovel' AS o,
       nai_imovel_pelo_condominio('tem alguma coisa no Tarumã?', '') AS deve_vir_vazio;
