CREATE OR REPLACE FUNCTION public.captacao_encerrar(p_telefone text, p_motivo text)
 RETURNS text
 LANGUAGE plpgsql
AS $function$
DECLARE
  l        captacao_leads;
  v_motivo text := lower(coalesce(nullif(btrim(p_motivo), ''), 'concluido'));
  v_ultima text;
BEGIN
  SELECT * INTO l FROM captacao_leads WHERE telefone_chave = nay_fone_chave(p_telefone);
  IF l.id IS NULL THEN
    RETURN 'não encerrei: número fora da lista.';
  END IF;

  SELECT texto INTO v_ultima FROM captacao_mensagens
   WHERE lead_id = l.id AND direcao = 'recebida' ORDER BY id DESC LIMIT 1;

  -- A PAREDE (Tel, 15/09). Numero errado e quem pediu para sair passam direto;
  -- todo o resto ouve a pergunta dos outros imoveis antes do fim.
  IF v_motivo <> 'numero_errado'
     AND NOT captacao_pediu_para_sair(v_ultima)
     AND NOT captacao_ja_perguntou_outros(l.id) THEN
    UPDATE captacao_leads SET etapa = 'aguardando_outros', atualizado_em = now() WHERE id = l.id;
    RETURN 'ainda NAO encerrei. Antes de terminar, falta perguntar dos outros imoveis. '
        || 'Diga exatamente isto, e nada mais: "' || captacao_frase_outros(l.id) || '"'
        || ' Quando ele responder, ai sim chame encerrar_conversa.';
  END IF;

  UPDATE captacao_leads
     SET status = 'concluido',
         etapa = 'concluido',
         pergunta_pendente = NULL,
         opt_out = CASE WHEN v_motivo IN ('opt_out', 'numero_errado') THEN true ELSE opt_out END,
         motivo_fim = v_motivo,
         fechado_em = now(),
         atualizado_em = now()
   WHERE id = l.id;
  RETURN 'conversa encerrada. despeça-se em uma linha curta e não faça mais perguntas.';
END;
$function$;
