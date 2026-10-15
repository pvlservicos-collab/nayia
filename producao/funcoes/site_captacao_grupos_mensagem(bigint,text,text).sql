CREATE OR REPLACE FUNCTION public.site_captacao_grupos_mensagem(p_id bigint, p_texto text, p_quem text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'privado'
AS $function$
DECLARE
  q       privado.grupo_pedido;
  e       privado.grupo_captacao_estado;
  v_fone  text;
  v_texto text := btrim(coalesce(p_texto, ''), ' ' || chr(9) || chr(10) || chr(13));
  v_turno bigint;
  v_dest  bigint;
  v_said  bigint;
  v_fila  record;
  v_resumo text;
BEGIN
  SELECT * INTO e FROM privado.grupo_captacao_estado WHERE id = 1;
  IF coalesce(e.config->>'envio_manual', 'false') <> 'true' THEN
    RETURN jsonb_build_object('erro', 'O envio manual está desligado na configuração (envio_manual).');
  END IF;
  SELECT * INTO q FROM privado.grupo_pedido WHERE id = p_id;
  IF q.id IS NULL THEN RETURN jsonb_build_object('erro', 'Não achei essa solicitação.'); END IF;
  IF q.fonte = 'teste' THEN
    RETURN jsonb_build_object('erro', 'Isto é um teste colado na tela: não tem corretor para receber.');
  END IF;
  IF v_texto = '' THEN RETURN jsonb_build_object('erro', 'Escreva a mensagem.'); END IF;
  IF length(v_texto) > 1500 THEN RETURN jsonb_build_object('erro', 'A mensagem passou de 1.500 caracteres.'); END IF;
  v_fone := regexp_replace(coalesce(q.remetente, ''), '\D', '', 'g');
  IF length(v_fone) NOT BETWEEN 10 AND 13 OR nai_chave(v_fone) IS NULL THEN
    RETURN jsonb_build_object('erro', 'Não tenho o telefone de quem escreveu (a mensagem veio sem número). Fale com a pessoa pelo grupo.');
  END IF;
  IF EXISTS (SELECT 1 FROM privado.grupo_pedido_mensagem m
              WHERE nai_chave(m.telefone) = nai_chave(v_fone) AND m.texto = v_texto AND m.enviado_em > now() - interval '10 minutes') THEN
    RETURN jsonb_build_object('erro', 'Essa mesma mensagem já foi para ele há menos de 10 minutos.');
  END IF;

  INSERT INTO nai_turno (contato_id, papel, texto)
  VALUES (nai_contato_do_cadastro(nai_cfg('tel_telefone'), 'Tel'), 'tel',
          left('captação ativa, mensagem de negociação (' || coalesce(nullif(btrim(p_quem), ''), 'site') || ') para '
               || v_fone || ', pedido ' || q.id, 500))
  RETURNING id INTO v_turno;
  v_dest := nai_contato_do_cadastro(v_fone, q.remetente_nome);
  v_said := nai_enfileirar_texto(v_turno, NULL, v_dest, 'entrega', v_texto, 'captacao_ativa_negociacao', 1);
  IF v_said IS NULL THEN
    RAISE EXCEPTION 'não consegui pôr a mensagem na fila (contato %)', v_dest;
  END IF;
  UPDATE nai_saida SET enviar_apos = now() + interval '2 seconds' WHERE turno_id = v_turno AND estado = 'pendente';
  UPDATE nai_turno SET fechado_em = now() WHERE id = v_turno;

  SELECT count(*) FILTER (WHERE s.estado = 'bloqueado') AS barradas,
         string_agg(DISTINCT s.bloqueio, '; ') FILTER (WHERE s.estado = 'bloqueado') AS motivos
    INTO v_fila FROM nai_saida s WHERE s.turno_id = v_turno;
  v_resumo := CASE WHEN v_fila.barradas > 0 THEN 'Barrada: ' || coalesce(v_fila.motivos, '?')
                   ELSE 'Na fila de envio, pelo número da Parceria.' END;
  INSERT INTO privado.grupo_pedido_mensagem (pedido_id, telefone, texto, turno_id, resumo, quem)
  VALUES (q.id, v_fone, v_texto, v_turno, v_resumo, nullif(btrim(coalesce(p_quem, '')), ''));
  RETURN jsonb_build_object('ok', v_fila.barradas = 0, 'resumo', v_resumo, 'turno', v_turno);
END
$function$;
