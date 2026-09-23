-- =====================================================================
-- NAI -- 101: colar o card do imovel E pedir imovel (Tel, 23/09/2026)
--
-- Ele: "e esse porque nao respondeu? +55 92 9151-7209".
--
-- O CASO: Corretor Andre Miranda (CRECI 2221), que ESTA na lista de
-- corretores, escreveu ontem as 22:18:
--     [card colado] "📍 Condominio Parque Imperial ... Codigo: 5717"
--     "Boa noite Nay"
--     "Ainda esta disponivel ?"
-- A porta respondeu "conversa que ja existia: quem responde e o Tel" e ela
-- ficou calada. O mesmo tinha acontecido as 18:40 com outro corretor, que
-- colou o card do Ibiza Flex e perguntou "Ainda disponivel?".
--
-- POR QUE (e um buraco logico, nao um esquecimento):
-- Para conversa ANTIGA -- as que ficaram com o Tel no religamento de 22/09 --
-- a porta so abre com: citou o imovel PELO NOME, pediu foto de um codigo, ou
-- pediu perfil. E a regra do nome tem um `NOT v_cod` na frente:
--
--     IF NOT v_cod AND <citou o nome> THEN abre
--
-- Ou seja: quem escreve "o Acquarelle ainda ta disponivel?" e atendido, e
-- quem COLA O CARD com o codigo -- a forma mais clara que existe de dizer de
-- qual imovel fala -- e recusado. O `NOT v_cod` estava ali para nao chamar a
-- busca por nome a toa, e acabou fechando a porta para o caso mais obvio.
--
-- A REGRA DO TEL CONTINUA INTEIRA (22/09: "nao responda as pessoas que ja
-- estavam conversando com o Tel antes, so se elas pedirem imoveis
-- claramente"). Colar o card de um imovel NOSSO e perguntar dele e pedir
-- imovel claramente -- e o codigo tem que ser de imovel que existe no nosso
-- catalogo, senao nao vale.
-- =====================================================================

\set ON_ERROR_STOP on

BEGIN;

DO $mig$
DECLARE v_def text; v_alvo text; v_bloco text;
BEGIN
  v_def := pg_get_functiondef('nai_deve_atender(text,text,integer)'::regprocedure);
  IF position('colou o card' IN v_def) > 0 THEN
    RAISE NOTICE 'a porta ja aceita o card colado'; RETURN;
  END IF;

  v_alvo := '  -- CITOU UM IMOVEL NOSSO PELO NOME (Tel, 16/09). Vale o mesmo que pedir foto';
  IF position(v_alvo IN v_def) = 0 THEN
    RAISE EXCEPTION 'nao achei o bloco do nome na porta';
  END IF;

  v_bloco := $bloco$  -- COLOU O CARD, OU ESCREVEU O CODIGO (101, Tel 23/09). E o caso mais
  -- claro de "falar de imovel nosso" que existe -- e era o unico que a porta
  -- recusava, porque a regra do nome logo abaixo comeca com `NOT v_cod`.
  -- O codigo tem que ser de imovel que existe: numero solto nao abre porta.
  IF v_cod AND EXISTS (
       SELECT 1 FROM imoveis i
        WHERE i.codigo::text = ANY (coalesce(nay_codigos_citados(coalesce(p_texto, '')), '{}'::text[]))) THEN
    UPDATE nai_contato SET liberado_em = now(),
                           liberado_motivo = left('colou o card / citou o codigo: ' || coalesce(p_texto, ''), 200)
     WHERE chave = v_chave;
    RETURN QUERY SELECT true, 'colou o card de um imovel nosso'::text; RETURN;
  END IF;

$bloco$ || v_alvo;

  EXECUTE replace(v_def, v_alvo, v_bloco);
  RAISE NOTICE 'porta: card colado agora abre a conversa';
END $mig$;

COMMIT;

-- O QUE TEM QUE ABRIR                                        e o que NAO pode.
SELECT (nai_deve_atender('559291517209', t, NULL)).* , left(t, 50) AS escreveu
  FROM unnest(ARRAY[
    E'📍 Condomínio Parque Imperial\n• Bairro: Parque 10\nCódigo: 5717\nAinda está disponível ?',
    'Ainda está disponível ?',
    'bom dia, tudo bem?',
    'o contrato foi assinado dia 15/09',
    'meu CRECI é 2221'
  ]) t;
