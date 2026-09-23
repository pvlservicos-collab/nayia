-- =====================================================================
-- NAI -- 72: depois de informar, ela pergunta se serve (Tel, 21/09/2026)
--
-- Do treino, rodada 2, caso 6. Ele: "depois dela responder a pergunta sobre
-- mobilia ela tem que perguntar ao corretor tipo uma cta a cada informacao
-- que ela responder do imovel: Serve para seu cliente?"
--
-- O QUE E: hoje ela responde o dado e para. O corretor fica com a informacao
-- na mao e a conversa morre ali -- ele que se vire para dar o proximo passo.
-- A pergunta devolve a bola: ou ele diz que serve e caminha para a visita, ou
-- diz que nao e ela descobre o que falta, em vez de ficar esperando.
--
-- A OUTRA METADE DO JULGAMENTO NAO ERA ERRO. Ele escreveu que ela "mandou o
-- card do Conquista rio negro sem mandar as fotos". Fui conferir: mandou 10.
-- Os quatro casos da rodada 2 que mandaram card mandaram foto junto (10, 7,
-- 21 e 31). Ele julgou antes de o painel passar a mostrar "(fotos)" -- o
-- campo ela_respondeu_agora guarda so texto. Ponto cego da tela, corrigido
-- no arquivo 71. Nada a mudar na Nay por causa disso.
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

  IF position('## Depois de informar, devolva a bola' IN v_texto) > 0 THEN
    RAISE NOTICE 'A regra ja esta no prompt. Nao duplico.';
    RETURN;
  END IF;

  v_novo := v_texto ||
E'\n## Depois de informar, devolva a bola\n' ||
E'Respondeu um dado do imovel, fecha com uma pergunta curta que devolva a\n' ||
E'conversa para ele. Sem isso a informacao morre na mao dele e a conversa\n' ||
E'para -- e quem tem que dar o proximo passo e voce, nao ele.\n' ||
E'- Ele: "esse tem mobilia?" -> "E semi-mobiliado, Sr. Carlos. Serve para o\n' ||
E'  seu cliente?"\n' ||
E'- Ele: "qual o valor?" -> "O aluguel e R$ 2.600. Fica dentro do que ele\n' ||
E'  procura?"\n' ||
E'- Ele: "tem vaga?" -> "Tem uma vaga coberta. Atende?"\n' ||
E'Uma pergunta so, e curta. Quando ele ja tiver dito que serve, nao pergunte\n' ||
E'de novo: siga para o proximo passo.\n';

  SELECT coalesce(max(versao), 0) + 1 INTO v_versao
    FROM nai_prompt_historico WHERE papel = 'corretor';

  PERFORM nai_salvar_prompt('corretor', v_novo, v_versao,
    'treino rodada 2: CTA depois de informar um dado do imovel (caso 6)');

  RAISE NOTICE 'prompt do corretor: % -> % chars (versao % guardada)',
    length(v_texto), length(v_novo), v_versao;
END $$;

-- O julgamento fica marcado como aplicado: nao volta na rodada 3.
UPDATE nai_treino_julgamento SET
  aplicada_em = now(),
  aplicada_como = '72_cta: "depois de informar, devolva a bola". A parte das fotos nao era erro -- ela mandou 10, o painel e que nao mostrava (corrigido no 71).'
 WHERE caso_id = 6 AND aplicada_em IS NULL;

COMMIT;

SELECT papel, length(texto) AS chars,
       (texto LIKE '%Depois de informar, devolva a bola%') AS tem_a_cta
  FROM nai_prompt WHERE papel = 'corretor';
