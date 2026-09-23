\set ON_ERROR_STOP on
BEGIN;
-- A lista quem manda e o sistema (93). Sem esta linha ela escreve a lista
-- dela, com os itens que achar que existem.
DO $$
DECLARE v_texto text; v_novo text; v_versao int;
  a text := E'- Não está em nenhuma das duas: chame escalar_ao_tel e responda SILENCIO. Daí em diante quem responde é o Tel.\n';
BEGIN
  SELECT texto INTO v_texto FROM nai_prompt WHERE papel='corretor';
  IF position('a lista de documentos' IN v_texto) > 0 THEN RAISE NOTICE 'ja aplicado'; RETURN; END IF;
  IF position(a IN v_texto) = 0 THEN RAISE EXCEPTION 'o ponto de insercao mudou'; END IF;
  v_novo := replace(v_texto, a, a ||
E'- Ele pediu a documentação: diga numa linha que já manda ("Claro! Já te mando a lista."). Quem manda a lista de documentos é o sistema, logo atrás — você não escreve a lista.\n');
  SELECT coalesce(max(versao),0)+1 INTO v_versao FROM nai_prompt_historico WHERE papel='corretor';
  PERFORM nai_salvar_prompt('corretor', v_novo, v_versao, 'a lista de documentos quem manda e o sistema (Tel, 22/09)');
  RAISE NOTICE 'prompt: % -> % chars (versao %)', length(v_texto), length(v_novo), v_versao;
END $$;
COMMIT;
