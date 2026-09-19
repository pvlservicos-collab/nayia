-- =====================================================================
-- NAI -- 16: o PROMPT passa a morar no banco (Tel, 15/09/2026)
--
-- Ele: "quero um painel de métricas de resposta, e acesso a toda configuração
-- dela, prompt, regras, tudo lá -- se eu altero lá, altera no n8n".
--
-- Hoje o prompt mora dentro do fluxo do n8n: mudar o texto exige import e
-- reinício (a Nay fica ~40s fora). Aqui ele passa a morar em `nai_prompt`, e o
-- fluxo lê a cada mensagem, pelo cabeçalho do turno. Editar no painel vale na
-- mensagem seguinte, sem deploy.
--
-- Nada é apagado: toda gravação guarda a versão anterior em
-- `nai_prompt_historico`, e dá para voltar com um UPDATE.
-- =====================================================================

CREATE TABLE IF NOT EXISTS nai_prompt (
  papel         text PRIMARY KEY,          -- corretor | proprietario | motoboy
  texto         text NOT NULL,
  versao        int  NOT NULL DEFAULT 1,
  atualizado_em timestamptz NOT NULL DEFAULT now(),
  atualizado_por text
);
COMMENT ON TABLE nai_prompt IS
  'O prompt de cada papel da NAI. O fluxo do n8n le daqui a cada mensagem (Tel, 15/09).';

CREATE TABLE IF NOT EXISTS nai_prompt_historico (
  id        bigserial PRIMARY KEY,
  papel     text NOT NULL,
  versao    int  NOT NULL,
  texto     text NOT NULL,
  salvo_em  timestamptz NOT NULL DEFAULT now(),
  salvo_por text
);
CREATE INDEX IF NOT EXISTS nai_prompt_hist_papel ON nai_prompt_historico (papel, versao DESC);

-- Grava um prompt novo e guarda o anterior. A versao e a trava contra
-- sobrescrita: quem salvou com versao velha recebe o numero atual de volta e
-- decide o que fazer (mesmo desenho do editor de fluxo do site).
-- SECURITY DEFINER: quem chama (o painel) NÃO tem escrita em `nai_prompt` --
-- de propósito. Ela grava em nome do dono, depois de conferir papel, versão e
-- texto vazio. Assim o painel muda o prompt sem ganhar acesso às tabelas.
CREATE OR REPLACE FUNCTION nai_salvar_prompt(p_papel text, p_texto text, p_versao int, p_por text)
RETURNS TABLE(ok boolean, versao int, motivo text)
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE v_atual int; v_texto text;
BEGIN
  SELECT p.versao, p.texto INTO v_atual, v_texto FROM nai_prompt p WHERE p.papel = p_papel FOR UPDATE;
  IF v_atual IS NULL THEN
    RETURN QUERY SELECT false, 0, 'papel desconhecido: use corretor, proprietario ou motoboy'::text; RETURN;
  END IF;
  IF p_versao IS NOT NULL AND p_versao <> v_atual THEN
    RETURN QUERY SELECT false, v_atual, 'alguem salvou antes de voce (versao ' || v_atual || ')'::text; RETURN;
  END IF;
  IF btrim(coalesce(p_texto, '')) = '' THEN
    RETURN QUERY SELECT false, v_atual, 'o prompt vazio deixaria a Nay sem instrucao'::text; RETURN;
  END IF;
  INSERT INTO nai_prompt_historico (papel, versao, texto, salvo_por)
  VALUES (p_papel, v_atual, v_texto, p_por);
  UPDATE nai_prompt
     SET texto = p_texto, versao = v_atual + 1, atualizado_em = now(), atualizado_por = p_por
   WHERE papel = p_papel;
  RETURN QUERY SELECT true, v_atual + 1, 'gravado'::text;
END;
$$;

-- O prompt que o fluxo usa. Sem linha na tabela, devolve NULL -- e o fluxo
-- cai no texto que ja esta dentro dele, entao nada quebra.
CREATE OR REPLACE FUNCTION nai_prompt_de(p_papel text)
RETURNS text LANGUAGE sql STABLE AS $$
  SELECT nullif(btrim(texto), '') FROM nai_prompt WHERE papel = p_papel;
$$;
