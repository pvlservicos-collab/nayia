-- 176 -- "Parar Nay" e "Nay voltar a atender" no card do contato (Pedro,
-- 29/09/2026). São o ASSUMIR e o DEVOLVER do Tel, pelo CRM, nas DUAS linhas
-- da pessoa (telefone e @lid -- o ASSUMIR do WhatsApp mexe só na chave que ele
-- digitou). Quem parou fica no motivo ("parada no CRM por Rayssa").
-- Voltar limpa qualquer parada: o Tel pelo celular (30 min), ASSUMIR, escalada,
-- visita parada. Reenviar a última mensagem para a Nay é do CRM (ela entra de
-- novo pelo webhook da NAI).

BEGIN;
SET LOCAL lock_timeout = '5s';

CREATE OR REPLACE FUNCTION crm_nay_parar(p_telefone text, p_quem text)
RETURNS TABLE(ok boolean, mensagem text)
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public SET lock_timeout = '3s' AS $$
DECLARE
  v_ids bigint[];
  v_n int;
BEGIN
  SELECT p.ids INTO v_ids FROM crm_pessoas(ARRAY[p_telefone]) p LIMIT 1;
  IF v_ids IS NULL OR cardinality(v_ids) = 0 THEN
    -- a Nay ainda não conhece: cria pelo telefone, para a parada valer já
    PERFORM nai_contato_do_cadastro(p_telefone, NULL);
    SELECT p.ids INTO v_ids FROM crm_pessoas(ARRAY[p_telefone]) p LIMIT 1;
  END IF;
  IF v_ids IS NULL OR cardinality(v_ids) = 0 THEN
    RETURN QUERY SELECT false, 'Não achei esse contato na Nay.'; RETURN;
  END IF;
  UPDATE nai_contato
     SET humano_assumiu_em = now(),
         humano_motivo = 'parada no CRM por ' || coalesce(nullif(btrim(p_quem), ''), 'alguém')
   WHERE id = ANY (v_ids);
  GET DIAGNOSTICS v_n = ROW_COUNT;
  RETURN QUERY SELECT true, 'A Nay parou nesta conversa. Ela não manda nada até alguém clicar em "Nay voltar a atender".';
END $$;

CREATE OR REPLACE FUNCTION crm_nay_voltar(p_telefone text, p_quem text)
RETURNS TABLE(ok boolean, mensagem text)
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public SET lock_timeout = '3s' AS $$
DECLARE
  v_ids bigint[];
BEGIN
  SELECT p.ids INTO v_ids FROM crm_pessoas(ARRAY[p_telefone]) p LIMIT 1;
  IF v_ids IS NULL OR cardinality(v_ids) = 0 THEN
    RETURN QUERY SELECT true, 'A Nay já atende esta conversa.'; RETURN;
  END IF;
  UPDATE nai_contato SET humano_assumiu_em = NULL, humano_motivo = NULL WHERE id = ANY (v_ids);
  RETURN QUERY SELECT true, 'A Nay voltou a atender esta conversa.';
END $$;

REVOKE ALL ON FUNCTION crm_nay_parar(text, text), crm_nay_voltar(text, text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION crm_nay_parar(text, text), crm_nay_voltar(text, text) TO nay_disparo;

COMMIT;
