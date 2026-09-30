CREATE OR REPLACE FUNCTION public.nai_confirmar_envio(p_id bigint, p_resposta jsonb)
 RETURNS text
 LANGUAGE plpgsql
AS $function$
DECLARE
  r      record;
  v_mid  text := coalesce(p_resposta->>'messageId', p_resposta->>'id', p_resposta->>'zaapId');
  v_cod  int;
  v_papel_t text;
  v_err  text;
  v_tent int;
BEGIN
  SELECT * INTO r FROM nai_saida WHERE id = p_id;
  IF r.id IS NULL THEN RETURN 'nao_existe'; END IF;
  IF r.estado <> 'enviando' THEN RETURN 'ja_tratada'; END IF;

  IF nullif(btrim(coalesce(v_mid, '')), '') IS NULL THEN
    -- 151: erro passageiro da Z-API -> de volta para a fila, até 2 vezes
    v_err := coalesce(p_resposta->'error'->>'message', p_resposta->>'error', p_resposta::text, '');
    v_tent := coalesce((r.resposta->>'tentativas')::int, 0) + 1;
    IF v_tent <= 2 AND v_err ~* '(^5\d\d|\m50[0-9]\M|bad gateway|service unavailable|gateway time|timeout|timed out|ETIMEDOUT|ECONNRESET|ECONNREFUSED|EAI_AGAIN|socket hang up)' THEN
      UPDATE nai_saida
         SET estado = 'pendente', enviar_apos = now() + make_interval(mins => v_tent),
             resposta = p_resposta || jsonb_build_object('tentativas', v_tent, 'ultimo_erro', left(v_err, 200))
       WHERE id = p_id;
      RETURN 'de_novo';
    END IF;

    UPDATE nai_saida SET estado = 'erro', resposta = p_resposta || jsonb_build_object('tentativas', v_tent), enviado_em = now()
     WHERE id = p_id;

    -- desistiu: se nada deste imóvel chegou nesta pessoa por este turno, a
    -- trava das 24h sai (senão nem o Tel conseguiria mandar de novo)
    IF r.codigo IS NOT NULL AND r.turno_id IS NOT NULL AND NOT EXISTS (
         SELECT 1 FROM nai_saida x
          WHERE x.turno_id = r.turno_id AND x.codigo = r.codigo AND x.chave_destino = r.chave_destino
            AND x.estado IN ('enviado', 'enviando', 'pendente')) THEN
      DELETE FROM imovel_enviado_no_dia
       WHERE chave = r.chave_destino AND codigo = r.codigo AND turno_id = r.turno_id;
    END IF;
    RETURN 'erro';
  END IF;

  UPDATE nai_saida SET estado = 'enviado', message_id = v_mid, resposta = p_resposta, enviado_em = now()
   WHERE id = p_id;

  INSERT INTO mensagem_saida (message_id, telefone, texto)
       VALUES (v_mid, r.telefone_final, coalesce(r.texto, r.imagem_url))
  ON CONFLICT (message_id) DO NOTHING;

  -- Card de imovel mandado a corretor vira linha em `envios` (o codigo sai
  -- do TEXTO desta mensagem, como no `Registrar saida` da Nay antiga).
  SELECT t.papel INTO v_papel_t FROM nai_turno t WHERE t.id = r.turno_id;
  IF r.tipo = 'texto' AND NOT r.redirecionado
     AND (r.papel_destino = 'corretor' OR (r.papel_destino = 'turno' AND v_papel_t = 'corretor')) THEN
    v_cod := (regexp_match(r.texto, 'C[oó]digo:\s*(\d{3,5})'))[1]::int;
    IF v_cod IS NOT NULL THEN
      INSERT INTO envios (codigo, telefone, destino, valor_enviado, message_id)
      SELECT i.codigo, r.telefone_final, 'corretor', coalesce(i.valor_aluguel, i.valor_venda, 0), v_mid
        FROM imoveis i WHERE i.codigo = v_cod;
    END IF;
  END IF;

  -- Marca na visita quando falamos com proprietario / Fernando.
  IF r.visita_id IS NOT NULL AND r.papel_destino = 'proprietario' THEN
    UPDATE nai_visita SET ult_msg_prop_em = now(), atualizado_em = now() WHERE id = r.visita_id;
  ELSIF r.visita_id IS NOT NULL AND r.papel_destino = 'motoboy' THEN
    UPDATE nai_visita SET ult_msg_moto_em = now(), atualizado_em = now() WHERE id = r.visita_id;
  END IF;
  RETURN 'enviado';
END;
$function$
;
