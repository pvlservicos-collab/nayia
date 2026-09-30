-- 198 (Pedro, 30/09/2026): o checklist de fechamento preenchido no CRM (aba
-- Fechamento) vai ao WhatsApp do Tel ("no número pessoal dele, por enquanto"),
-- pela caixa da Nay, como os outros avisos ao Tel (nai_avisar_tel ->
-- nai_config.tel_telefone). O texto vem pronto do CRM (lib/checklistFechamento).
-- Só uma função nova; nada existente muda.
BEGIN;
CREATE OR REPLACE FUNCTION crm_checklist_preenchido(p_tipo text, p_texto text, p_quem text)
 RETURNS TABLE(ok boolean, mensagem text)
 LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $$
BEGIN
  IF p_tipo NOT IN ('locacao', 'venda') OR coalesce(btrim(p_texto), '') = '' THEN
    RETURN QUERY SELECT false, 'Checklist vazio.'::text;
    RETURN;
  END IF;
  PERFORM nai_avisar_tel(NULL, NULL, left(p_texto, 3800), 'checklist_preenchido');
  RETURN QUERY SELECT true, 'Enviado ao Tel.'::text;
END $$;
GRANT EXECUTE ON FUNCTION crm_checklist_preenchido(text, text, text) TO nay_disparo;
COMMIT;
