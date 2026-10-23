CREATE OR REPLACE FUNCTION public.captacao_nay_perfil_salvar(p_nome text, p_prompt_papel text, p_roteiro text, p_descricao text DEFAULT ''::text, p_listas text DEFAULT ''::text, p_por text DEFAULT NULL::text)
 RETURNS text
 LANGUAGE plpgsql
AS $function$
DECLARE
  v nai_prompt;
BEGIN
  SELECT * INTO v FROM nai_prompt WHERE papel = p_prompt_papel;
  IF v.papel IS NULL THEN RETURN 'não existe o prompt ' || coalesce(p_prompt_papel, '(vazio)') || ' em nai_prompt'; END IF;
  INSERT INTO captacao_nay_perfil (nome, descricao, listas, prompt_papel, roteiro, prompt_retrato, prompt_versao, salvo_por)
  VALUES (p_nome, coalesce(p_descricao, ''), coalesce(p_listas, ''), p_prompt_papel, p_roteiro, v.texto, v.versao, p_por)
  ON CONFLICT (nome) DO UPDATE SET descricao = EXCLUDED.descricao, listas = EXCLUDED.listas,
         prompt_papel = EXCLUDED.prompt_papel, roteiro = EXCLUDED.roteiro, prompt_retrato = EXCLUDED.prompt_retrato,
         prompt_versao = EXCLUDED.prompt_versao, salvo_em = now(), salvo_por = EXCLUDED.salvo_por;
  RETURN 'perfil ' || p_nome || ' salvo com o prompt ' || p_prompt_papel || ' v' || v.versao;
END $function$;
