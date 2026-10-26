-- monta um corretor, uma visita confirmada com um lembrete JÁ NA FILA (pendente), cancela pelo
-- corretor, e confere que o lembrete pendente foi bloqueado (não sai mais)
DO $$
DECLARE v_corretor bigint; v_turno bigint; v_visita bigint; v_saida bigint; v_bloqueio text; v_estado text;
BEGIN
  INSERT INTO nai_contato (chave, telefone, nome_whatsapp) VALUES ('5592999990502', '5592999990502', 'Corretora Teste 502')
    RETURNING id INTO v_corretor;
  INSERT INTO nai_turno (contato_id, papel) VALUES (v_corretor, 'corretor') RETURNING id INTO v_turno;
  INSERT INTO nai_visita (corretor_id, codigo, estado, quando, criado_em, atualizado_em)
    VALUES (v_corretor, 1, 'confirmada', now() + interval '1 hour', now(), now())
    RETURNING id INTO v_visita;
  -- o lembrete que a agenda já tinha colocado na fila, ainda pendente
  INSERT INTO nai_saida (visita_id, contato_id, papel_destino, chave_destino, tipo, texto, estado)
    VALUES (v_visita, v_corretor, 'corretor', '5592999990502', 'texto', 'lembrete de teste', 'pendente')
    RETURNING id INTO v_saida;

  PERFORM nai_cancelar_visita(v_turno, '1', 'teste 502');

  SELECT estado, bloqueio INTO v_estado, v_bloqueio FROM nai_saida WHERE id = v_saida;
  RAISE NOTICE 'lembrete pendente ficou: estado=%, bloqueio=%', v_estado, v_bloqueio;
  IF v_estado <> 'bloqueado' THEN RAISE EXCEPTION 'FALHOU: o lembrete pendente deveria ter sido bloqueado'; END IF;

  SELECT estado INTO v_estado FROM nai_visita WHERE id = v_visita;
  RAISE NOTICE 'visita ficou: estado=%', v_estado;
  IF v_estado <> 'cancelada' THEN RAISE EXCEPTION 'FALHOU: a visita deveria estar cancelada'; END IF;
END $$;
