\set ON_ERROR_STOP on
BEGIN;
-- No teste ela disse "ja te mando a lista para pessoa juridica" e NADA saiu:
-- a lista e uma so e ja tem o item de PJ e o de autonomo. Promessa de uma
-- lista que nao existe e o mesmo defeito das fotos prometidas (CLAUDE.md:
-- capacidade ausente vira promessa).
DO $$
DECLARE v_texto text; v_novo text; v_versao int;
  a text := E'- Ele pediu a documentação: diga numa linha que já manda ("Claro! Já te mando a lista."). Quem manda a lista de documentos é o sistema, logo atrás — você não escreve a lista.\n';
BEGIN
  SELECT texto INTO v_texto FROM nai_prompt WHERE papel='corretor';
  IF position('A lista é uma só' IN v_texto) > 0 THEN RAISE NOTICE 'ja aplicado'; RETURN; END IF;
  IF position(a IN v_texto) = 0 THEN RAISE EXCEPTION 'a linha dos documentos mudou'; END IF;
  v_novo := replace(v_texto, a,
E'- Ele pediu a documentação: diga numa linha que já manda ("Claro! Já te mando a lista."). Quem manda a lista de documentos é o sistema, logo atrás — você não escreve a lista.\n' ||
E'- A lista é uma só e já cobre empresa (PJ) e autônomo. Ele perguntou de PJ ou de autônomo depois de receber a lista: responda pelo item que já está nela ("Para PJ vai o contrato social, o CNPJ e os documentos dos sócios, Sr. Carlos."), sem prometer outra lista.\n');
  SELECT coalesce(max(versao),0)+1 INTO v_versao FROM nai_prompt_historico WHERE papel='corretor';
  PERFORM nai_salvar_prompt('corretor', v_novo, v_versao, 'a lista de documentos ja cobre PJ e autonomo (Tel, 22/09)');
  RAISE NOTICE 'prompt: % -> % chars (versao %)', length(v_texto), length(v_novo), v_versao;
END $$;
COMMIT;
