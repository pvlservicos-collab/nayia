-- =====================================================================
-- NAI -- 69: o card vai inteiro, e as fotos vao junto (Tel, 21/09/2026)
--
-- Vem do treino, ciclo 1. Dois dos tres casos que ele julgou apontam a mesma
-- coisa por dois lados:
--
--   caso 3 -- "me manda o card do 5727"
--     Ela mandou o card e PERGUNTOU "Quer que eu te mande as fotos dele?".
--     Ele: "ela nao mandou o card... quando a pessoa perguntar ela manda o
--     card ja e as fotos".
--
--   caso 2 -- ele perguntou de imovel no Mirante
--     Ela respondeu so com o codigo e o valor. Ele: "e para mandar o card
--     sempre, quando voce achar lista mas tem que mandar o card direito, a
--     pessoa teve que pedir o card com as informacoes do imovel porque voce
--     nao mandou".
--
-- A REGRA DE PERGUNTAR ERA MINHA, DE ONTEM. No 68 eu trouxe da descricao da
-- ferramenta `imovel_por_codigo` a linha "ao apresentar um imovel, ofereca --
-- pergunte se ele quer as fotos". Estava na descricao desde antes, mas quando
-- virou regra de prompt o modelo passou a obedecer ao pe da letra e a
-- perguntar toda vez. O caso 3 e o efeito disso. Sai agora.
--
-- NADA MAIS DO 68 MUDA: as outras seis regras que vieram das ferramentas
-- continuam onde estao.
-- =====================================================================

\set ON_ERROR_STOP on

BEGIN;

DO $$
DECLARE
  v_texto  text;
  v_novo   text;
  v_versao int;
BEGIN
  SELECT texto INTO v_texto FROM nai_prompt WHERE papel = 'corretor';
  IF v_texto IS NULL THEN
    RAISE EXCEPTION 'nai_prompt do corretor nao existe';
  END IF;

  v_novo := v_texto;

  -- ---------------------------------------------------------------
  -- 1. A regra de PERGUNTAR pelas fotos vira a regra de MANDAR.
  -- ---------------------------------------------------------------
  v_novo := replace(v_novo,
E'## Ofereca as fotos ao apresentar\nDepois de apresentar um imovel, pergunte se ele quer as fotos. Quem manda as\nfotos e o sistema, nao voce -- voce oferece.\n- "Quer que eu te mande as fotos dele?"\n',
E'## As fotos vao junto, sem perguntar\nApresentou um imovel, as fotos vao atras. Quem manda e o sistema, mas voce\nnao pergunta antes: perguntar faz o corretor ter que pedir de novo uma coisa\nque ele ja pediu.\n- Ele: "me manda o card do 5727" -> o card, e as fotos na sequencia.\n- "Quer que eu te mande as fotos?" fica fora das suas respostas.\nSo pergunte de qual imovel sao as fotos quando voce nao souber qual e o\nimovel da conversa.\n');

  IF v_novo = v_texto THEN
    RAISE NOTICE 'ATENCAO: a regra de oferecer fotos nao foi achada para troca.';
  END IF;

  -- ---------------------------------------------------------------
  -- 2. O CARD INTEIRO, sempre. Vai depois da secao das sete regras.
  -- ---------------------------------------------------------------
  IF position('## O card vai inteiro' IN v_novo) = 0 THEN
    v_novo := v_novo ||
E'\n## O card vai inteiro, nunca so o codigo e o valor\n' ||
E'Quando voce falar de um imovel para o corretor, manda o card como a\n' ||
E'ferramenta devolveu: bairro, area, comodos, vaga, mobilia, valor e codigo.\n' ||
E'Codigo e valor soltos nao dizem nada a quem vai mostrar o imovel a um\n' ||
E'cliente, e obrigam ele a pedir o resto.\n' ||
E'- Ele pergunta se tem no condominio X -> diga que tem E mande o card.\n' ||
E'- A busca devolveu uma lista -> mande a lista como veio; quando ele\n' ||
E'  escolher um, mande o card inteiro daquele.\n' ||
E'- "no Mirante tenho o 5727 por 2.500" sozinho nao e resposta: e o comeco\n' ||
E'  de uma, e o corretor vai ter que pedir o resto.\n';
  END IF;

  IF v_novo = v_texto THEN
    RAISE NOTICE 'Nada mudou no prompt.';
    RETURN;
  END IF;

  SELECT coalesce(max(versao), 0) + 1 INTO v_versao
    FROM nai_prompt_historico WHERE papel = 'corretor';

  PERFORM nai_salvar_prompt('corretor', v_novo, v_versao,
    'treino ciclo 1: card inteiro e fotos sem perguntar (casos 2 e 3)');

  RAISE NOTICE 'prompt do corretor: % -> % chars (versao % guardada)',
    length(v_texto), length(v_novo), v_versao;
END $$;

COMMIT;

SELECT papel, length(texto) AS chars,
       (texto LIKE '%As fotos vao junto, sem perguntar%') AS regra_das_fotos_nova,
       (texto LIKE '%O card vai inteiro%')                AS regra_do_card,
       (texto LIKE '%Ofereca as fotos ao apresentar%')    AS regra_velha_ainda_la
  FROM nai_prompt WHERE papel = 'corretor';
