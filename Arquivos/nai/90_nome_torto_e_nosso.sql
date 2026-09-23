-- =====================================================================
-- NAI -- 90: nome torto continua sendo o nosso imovel (Tel, 22/09/2026)
--
-- Ele: "como ele ja viu o nome no grupo ele esta falando de um imovel nosso
-- sim, entao ela faz uma assimilacao... mas saindo o mesmo tom".
--
-- O sistema ja identifica o imovel pelo nome parecido (arquivo 89). Falta a
-- fala: sem esta linha ela pode estranhar o nome e devolver a pergunta ("o
-- Sr. quis dizer o Acquarelle?"), que e justamente o tom que ele nao quer.
-- =====================================================================
\set ON_ERROR_STOP on
BEGIN;
DO $$
DECLARE
  v_texto text; v_novo text; v_versao int;
  a text := E'- Vieiralves é a parte nobre de Nossa Senhora das Graças: passe bairro "Vieiralves" e fale Vieiralves, como ele falou.\n';
BEGIN
  SELECT texto INTO v_texto FROM nai_prompt WHERE papel = 'corretor';
  IF position('escreveu o nome torto' IN v_texto) > 0 THEN RAISE NOTICE 'ja aplicado'; RETURN; END IF;
  IF position(a IN v_texto) = 0 THEN RAISE EXCEPTION 'a linha do Vieiralves mudou -- confira o prompt'; END IF;
  v_novo := replace(v_texto, a, a ||
E'- Ele falou por áudio ou escreveu o nome torto ("aquarele", "mirante da flor", "park golfe"): é um imóvel nosso, que ele viu no grupo. A ferramenta devolve o certo; responda no tom de sempre, com o nome como está no cadastro, sem perguntar se ele quis dizer outro.\n');
  SELECT coalesce(max(versao), 0) + 1 INTO v_versao FROM nai_prompt_historico WHERE papel = 'corretor';
  PERFORM nai_salvar_prompt('corretor', v_novo, v_versao, 'nome torto do audio e imovel nosso (Tel, 22/09)');
  RAISE NOTICE 'prompt: % -> % chars (versao %)', length(v_texto), length(v_novo), v_versao;
END $$;
COMMIT;
SELECT length(texto) AS chars, texto LIKE '%escreveu o nome torto%' AS tem_a_regra FROM nai_prompt WHERE papel='corretor';
