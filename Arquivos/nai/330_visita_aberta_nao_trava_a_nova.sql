-- 330 -- Agendar no CRM não dá mais "duplicate key ... nai_visita_uma_aberta"
--
-- Pedro, 09/10/2026: "tá dando erro na hora da Rayssa marcar uma visita às 16".
--
-- O índice nai_visita_uma_aberta deixa só UMA visita aberta por corretor e imóvel. A Úrsula tinha a #1081 no 5758
-- para 07/10 14:30, que ninguém marcou como realizada: continuou aberta. A Rayssa agendou de novo para hoje e o
-- INSERT bateu no índice (quatro vezes, das 11:56 às 12:39).
--
-- Agora, antes de criar a visita nova, crm_visita_agendar olha a aberta deste corretor neste imóvel:
--   * a que é de um dia que já passou (ou sem horário) é encerrada, com o motivo, e o que a Nay ainda ia mandar
--     sobre ela não sai mais; a nova nasce normalmente;
--   * a que ainda vai acontecer muda para o horário novo (o mesmo crm_visita_mudar_horario do botão), em vez de
--     nascer outra.
-- O pedido que veio da Nay (312) continua virando esta visita, como antes. Só a função muda; o índice fica.
BEGIN;
SET LOCAL lock_timeout = '3s';

DO $mig$
DECLARE
  v_def text := pg_get_functiondef('public.crm_visita_agendar(integer, text, text, timestamp with time zone, integer, text)'::regprocedure);
  v_ramo_velho text := $v$  IF v_da_nay IS NOT NULL THEN
    -- (com o apelido `v`: proprietario_nome também é coluna de SAÍDA desta função)$v$;
  v_ramo_novo text := $n$  -- 330: o índice nai_visita_uma_aberta deixa UMA visita aberta por corretor e imóvel. A que ficou aberta de um
  -- dia que já passou (ninguém marcou realizada) é encerrada; a que ainda vai acontecer muda para o horário novo.
  IF v_da_nay IS NULL THEN
    SELECT * INTO v_aberta FROM nai_visita v
     WHERE v.codigo = p_codigo AND v.corretor_id = v_cor
       AND v.estado NOT IN ('realizada', 'encerrada', 'cancelada', 'expirada')
     ORDER BY v.id DESC LIMIT 1
       FOR UPDATE;
    IF v_aberta.id IS NOT NULL AND (v_aberta.quando IS NULL OR v_aberta.quando < now()) THEN
      UPDATE nai_visita x
         SET estado = 'encerrada', aguardando = NULL, senha = NULL,
             encerrada_em = coalesce(x.encerrada_em, now()),
             motivo = coalesce(x.motivo, left('Ficou aberta; ' || v_quem || ' agendou outra no CRM', 200)),
             atualizado_em = now()
       WHERE x.id = v_aberta.id;
      UPDATE nai_saida s SET estado = 'bloqueado', bloqueio = 'visita encerrada: outra agendada no CRM'
       WHERE s.visita_id = v_aberta.id AND s.estado = 'pendente';
      PERFORM nai_evento(v_aberta.id, 'encerrada_por_outra',
        left(v_quem || ' agendou outra visita do mesmo corretor ao mesmo imóvel', 200));
      v_aviso := ' A de ' || coalesce(to_char(v_aberta.quando AT TIME ZONE 'America/Manaus', 'DD/MM HH24:MI'), 'antes')
                 || ' (#' || v_aberta.id || '), que tinha ficado aberta, foi encerrada.';
    ELSIF v_aberta.id IS NOT NULL THEN
      SELECT m.ok, m.mensagem INTO v_mudou, v_msg FROM crm_visita_mudar_horario(v_aberta.id, p_quando, v_quem) m;
      IF NOT coalesce(v_mudou, false) THEN
        RETURN QUERY SELECT false,
          coalesce(v_msg, 'Não consegui mudar a visita #' || v_aberta.id || '.') || ' (já existe a visita #' || v_aberta.id
            || ' deste corretor a este imóvel)',
          v_aberta.id, NULL::text, NULL::text, NULL::text, NULL::text, NULL::text, NULL::text;
        RETURN;
      END IF;
      UPDATE nai_visita x
         SET duracao_min = v_dur, criada_no_crm_por = coalesce(x.criada_no_crm_por, v_quem), atualizado_em = now()
       WHERE x.id = v_aberta.id;
      v_mudada := v_aberta.id;
      v_aviso := ' Já havia a visita #' || v_aberta.id || ' deste corretor a este imóvel ('
                 || to_char(v_aberta.quando AT TIME ZONE 'America/Manaus', 'DD/MM HH24:MI') || '): ela passou para o horário novo.';
    END IF;
  END IF;

  IF v_mudada IS NOT NULL THEN
    v_id := v_mudada;
  ELSIF v_da_nay IS NOT NULL THEN
    -- (com o apelido `v`: proprietario_nome também é coluna de SAÍDA desta função)$n$;
  v_msg_velha text := $v$    'Visita #' || v_id || ' agendada para ' || nai_hora_exata(p_quando) || '.',$v$;
  v_msg_nova  text := $n$    'Visita #' || v_id || ' agendada para ' || nai_hora_exata(p_quando) || '.' || v_aviso,$n$;
BEGIN
  IF position('330:' IN v_def) > 0 THEN RAISE EXCEPTION '330: já aplicada'; END IF;
  IF (length(v_def) - length(replace(v_def, v_ramo_velho, ''))) / length(v_ramo_velho) <> 1
     OR (length(v_def) - length(replace(v_def, v_msg_velha, ''))) / length(v_msg_velha) <> 1 THEN
    RAISE EXCEPTION '330: o trecho de crm_visita_agendar mudou no banco; leia a função viva antes';
  END IF;
  v_def := replace(v_def, v_ramo_velho, v_ramo_novo);
  v_def := replace(v_def, v_msg_velha, v_msg_nova);
  v_def := regexp_replace(v_def, '(\nDECLARE\n)',
    E'\\1  v_aberta nai_visita;\n  v_mudada bigint;\n  v_mudou  boolean;\n  v_msg    text;\n  v_aviso  text := '''';\n');
  EXECUTE v_def;
END
$mig$;

COMMIT;
