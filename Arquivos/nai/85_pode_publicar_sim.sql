-- =====================================================================
-- NAI -- 85: "posso publicar?" -> "Pode publicar sim!" (Tel, 22/09/2026)
--
-- Ele: "coloca na memoria que se alguem perguntar se pode publicar, a Nay
-- responde pode publicar sim".
--
-- Ja existia a regra do pedido de parceria (arquivo 76, caso 97 do treino):
-- "posso anunciar os imoveis de voces?" -> "pode trabalhar sim! ja esta no
-- nosso grupo?". A pergunta com PUBLICAR e a mesma coisa dita de outro jeito,
-- e a resposta passa a usar a palavra dele. A pergunta do grupo continua, que
-- e o que o Tel pediu na rodada 5.
-- =====================================================================

\set ON_ERROR_STOP on

BEGIN;

DO $$
DECLARE
  v_texto text; v_novo text; v_versao int;
  a text := E'- Ele perguntou se pode anunciar ou trabalhar com os nossos imóveis: "Boa tarde, pode trabalhar sim! O Sr. já está no nosso grupo, o Imóveis para Anunciar Easy?"\n';
BEGIN
  SELECT texto INTO v_texto FROM nai_prompt WHERE papel = 'corretor';
  IF position('Pode publicar sim' IN v_texto) > 0 THEN RAISE NOTICE 'ja aplicado'; RETURN; END IF;
  IF position(a IN v_texto) = 0 THEN RAISE EXCEPTION 'a linha da parceria mudou -- confira o prompt'; END IF;
  v_novo := replace(v_texto, a,
E'- Ele perguntou se pode publicar, anunciar, divulgar ou trabalhar com os nossos imóveis: diga que pode, com a palavra que ele usou, e pergunte do grupo.\n' ||
E'  - "posso publicar os imóveis de vocês?" → "Pode publicar sim, Sr. Carlos! O Sr. já está no nosso grupo, o Imóveis para Anunciar Easy?"\n' ||
E'  - "posso anunciar os de aluguel?" → "Pode anunciar sim! O Sr. já está no nosso grupo, o Imóveis para Anunciar Easy?"\n');
  SELECT coalesce(max(versao), 0) + 1 INTO v_versao FROM nai_prompt_historico WHERE papel = 'corretor';
  PERFORM nai_salvar_prompt('corretor', v_novo, v_versao, 'posso publicar? -> pode publicar sim (Tel, 22/09)');
  RAISE NOTICE 'prompt: % -> % chars (versao %)', length(v_texto), length(v_novo), v_versao;
END $$;

COMMIT;

SELECT texto LIKE '%Pode publicar sim%' AS tem_a_regra FROM nai_prompt WHERE papel = 'corretor';
