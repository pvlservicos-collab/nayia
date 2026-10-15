CREATE OR REPLACE FUNCTION public.captacao_olx_guardar(p_telefone text, p_campo text, p_valor text)
 RETURNS text
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_lead bigint;
  v_campo text := lower(btrim(coalesce(p_campo, '')));
  v_valor text := btrim(coalesce(p_valor, ''));
  v_prox jsonb;
  v_antes text := '';
  v_pct numeric;
  v_txt text := lower(nay_sem_acento(coalesce(p_valor, '')));
BEGIN
  SELECT l.id INTO v_lead FROM captacao_leads l JOIN captacao_olx o ON o.lead_id = l.id WHERE l.telefone_chave = nay_fone_chave(p_telefone);
  IF v_lead IS NULL THEN RETURN 'ERRO: este proprietario nao e da OLX'; END IF;
  IF v_campo NOT IN ('condominio_nome', 'elevador', 'taxa_condominio', 'iptu', 'lances_escada', 'bloco', 'andar', 'torre',
                     'metragem_terreno', 'numero_casa', 'endereco', 'sol', 'honorarios', 'condominio_incluso', 'outros',
                     'outros_detalhe', 'indicacao') THEN
    RETURN 'ERRO: campo desconhecido (' || v_campo || '). Use o campo da pergunta que voce fez.';
  END IF;
  IF v_valor = '' THEN v_valor := 'nao sabe'; END IF;

  -- OS 6% (o roteiro do Pedro): menos de 5% vai para o Pedro; "tem que acrescentar" ganha a margem de 10%
  IF v_campo = 'honorarios' THEN
    v_pct := (SELECT replace((regexp_match(v_txt, '(\d+(?:[.,]\d+)?)\s*(%|por cento)'))[1], ',', '.')::numeric);
    IF v_pct IS NOT NULL AND v_pct < 5 THEN
      UPDATE captacao_olx SET respostas = respostas || jsonb_build_object(v_campo, v_valor), atualizado_em = now() WHERE lead_id = v_lead;
      RETURN 'ele propos honorarios ABAIXO de 5% (' || v_valor || '): isso e com o Pedro. Chame escalar_ao_tel com assunto '
             || '"honorarios abaixo de 5%" e disse = o que ele escreveu, e responda SILENCIO. Nao comente o percentual.';
    END IF;
    IF v_txt ~ '(nao|acrescent|por fora|liquido|em cima|fora)' AND v_txt !~ 'inclus' THEN
      v_antes := 'ele disse que os 6% NAO estao inclusos: comece a resposta com exatamente "Tudo bem, podemos trabalhar com uma margem de 10% a mais." ';
    END IF;
  END IF;

  UPDATE captacao_olx SET respostas = respostas || jsonb_build_object(v_campo, v_valor), atualizado_em = now() WHERE lead_id = v_lead;
  UPDATE captacao_leads SET pergunta_pendente = NULL, atualizado_em = now() WHERE id = v_lead;
  v_prox := captacao_olx_proxima(p_telefone);
  IF coalesce((v_prox->>'fim')::boolean, false) THEN
    RETURN 'anotado. ' || v_antes || 'O roteiro acabou: agradeca em uma linha ("Ok, obrigada!" ou "Certo, obrigada pela informacao!") '
           || 'e chame encerrar_conversa com motivo = concluido. Nao faca mais nenhuma pergunta.';
  END IF;
  RETURN 'anotado. ' || v_antes || 'Agora, na MESMA resposta, depois de uma confirmacao curta ("Certo." / "Entendi, anotei aqui."), '
         || 'faca a proxima pergunta com EXATAMENTE estas palavras (campo ' || (v_prox->>'campo') || '): "' || (v_prox->>'pergunta') || '"';
END $function$;
