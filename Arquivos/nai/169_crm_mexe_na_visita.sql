-- 169 -- O CRM mexe na visita (Pedro, 29/09/2026): "quando eu clico na agenda
-- da visita abre ela em um popup à direita para eu excluir, marcar como
-- realizada ou mudar, e eu posso arrastar ela pela agenda".
--
-- As decisões dele (29/09), que é o que cada função faz:
--   * MUDAR O HORÁRIO: ninguém é avisado -- "a pessoa manualmente faz isso,
--     até porque vai ser mais tipo o cliente diz que vai atrasar". É o REMARCA
--     do Tel SEM as três mensagens. Os lembretes automáticos seguem o horário
--     novo, mas só os que ainda estão no futuro: atrasar 20 min não pode
--     reenviar agora o "daqui a 1 hora" que o corretor já recebeu.
--   * EXCLUIR: some da agenda, ninguém é avisado. A linha fica (histórico e
--     chaves estrangeiras), com `excluida_em` (169a); a visita aberta vira
--     cancelada para a Nay parar de cuidar dela, a mensagem dela que ainda
--     estava na fila é barrada, e o chat parado por ela volta a ser atendido.
--   * REALIZADA: a Nay pergunta ao corretor como foi -- a MESMA rotina do
--     `nai_agenda_tick` (pós-visita + lembrete de devolver a chave ao André).
--
-- Quem fez vai no evento da visita ("por <nome no CRM>"). As três são
-- SECURITY DEFINER para o `nay_disparo`, que só tem EXECUTE. Patch em cima das
-- versões vivas de crm_visitas e crm_contato_historico (só o filtro novo).

BEGIN;
SET LOCAL lock_timeout = '5s';

-- as leituras do CRM não mostram a excluída
CREATE OR REPLACE FUNCTION public.crm_visitas(p_desde date DEFAULT NULL::date, p_ate date DEFAULT NULL::date)
 RETURNS TABLE(id bigint, codigo integer, imovel text, estado text, aberta boolean, aguardando text, urgente boolean, acesso text, quando timestamp with time zone, quando_sugerido timestamp with time zone, criado_em timestamp with time zone, confirmada_corretor_em timestamp with time zone, aprovada_em timestamp with time zone, aprovada_por text, prop_ok_em timestamp with time zone, moto_ok_em timestamp with time zone, confirmada_em timestamp with time zone, pos_visita_em timestamp with time zone, encerrada_em timestamp with time zone, atualizado_em timestamp with time zone, resultado text, motivo text, corretor_nome text, corretor_chaves text[], proprietario_nome text, visitante_nome text)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
 SET jit TO 'off'
AS $function$
  -- `nai_chave` custa ~30 us: por visita, contra 1.538 corretores e 1.620
  -- @lid, eram 5 s (medido em 29/09). Calculadas uma vez só, aqui.
  WITH corr AS MATERIALIZED (
    SELECT nai_chave(cr.telefone) AS chave, cr.nome FROM corretores cr
  ),
  lid_map AS MATERIALIZED (
    SELECT 'lid:' || regexp_replace(i.lid, '\D', '', 'g') AS lid_chave, nai_chave(i.telefone) AS fone_chave
      FROM identidade_lid i WHERE coalesce(i.telefone, '') <> ''
  )
  SELECT v.id, v.codigo, nai_ref_imovel(v.codigo), v.estado, nai_visita_aberta(v.estado), v.aguardando,
         coalesce(v.urgente, false), v.acesso, v.quando, v.quando_sugerido,
         v.criado_em, v.confirmada_corretor_em, v.aprovada_em, v.aprovada_por,
         v.prop_ok_em, v.moto_ok_em, v.confirmada_em, v.pos_visita_em,
         v.encerrada_em, v.atualizado_em, v.resultado, v.motivo,
         coalesce(nullif(btrim(c.nome_completo), ''), nullif(btrim(co.nome), ''), nullif(btrim(c.nome_whatsapp), '')),
         ARRAY(SELECT DISTINCT x FROM (
                 SELECT c.chave
                 UNION SELECT m.fone_chave FROM lid_map m WHERE m.lid_chave = c.chave
                 UNION SELECT m.lid_chave FROM lid_map m WHERE m.fone_chave = c.chave
               ) u(x) WHERE x IS NOT NULL),
         v.proprietario_nome, v.visitante_nome
    FROM nai_visita v
    LEFT JOIN nai_contato c ON c.id = v.corretor_id
    LEFT JOIN LATERAL (SELECT cr.nome FROM corr cr WHERE cr.chave = c.chave LIMIT 1) co ON true
   WHERE v.estado <> 'coletando'
     AND v.excluida_em IS NULL
     AND (nai_visita_aberta(v.estado)
          OR ((p_desde IS NULL OR coalesce(v.quando, v.criado_em) >= p_desde::timestamptz)
              AND (p_ate IS NULL OR coalesce(v.quando, v.criado_em) < (p_ate + 1)::timestamptz)))
   ORDER BY nai_visita_aberta(v.estado) DESC, coalesce(v.quando, v.criado_em) DESC
   LIMIT 500
$function$;

CREATE OR REPLACE FUNCTION public.crm_contato_historico(p_telefone text, p_limite integer DEFAULT 60)
 RETURNS TABLE(quando timestamp with time zone, tipo text, codigo integer, imovel text, detalhe text)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
 SET jit TO 'off'
AS $function$
  WITH p AS MATERIALIZED (SELECT * FROM crm_pessoas(ARRAY[p_telefone])),
  irmaos AS (SELECT unnest(p.ids) AS id FROM p),
  ev AS (
    SELECT e.enviado_em AS quando, 'recebeu'::text AS tipo,
           nullif(regexp_replace(coalesce(e.codigo, ''), '\D', '', 'g'), '')::int AS codigo, NULL::text AS detalhe
      FROM envios e, p
     WHERE e.destino IS DISTINCT FROM 'grupo' AND nai_chave(e.telefone) = ANY (p.chaves)
    UNION ALL
    SELECT t.criado_em, 'pediu', t.codigo, left(regexp_replace(coalesce(t.texto, ''), '\s+', ' ', 'g'), 160)
      FROM nai_turno t
     WHERE t.contato_id IN (SELECT id FROM irmaos) AND t.codigo IS NOT NULL AND NOT coalesce(t.teste, false)
    UNION ALL
    SELECT coalesce(v.quando, v.criado_em), 'visita', v.codigo, v.estado
      FROM nai_visita v
     WHERE v.estado <> 'coletando' AND v.excluida_em IS NULL
       AND (v.corretor_id IN (SELECT id FROM irmaos) OR v.proprietario_id IN (SELECT id FROM irmaos))
  )
  SELECT ev.quando, ev.tipo, ev.codigo, CASE WHEN ev.codigo IS NOT NULL THEN nai_ref_imovel(ev.codigo) END, ev.detalhe
    FROM ev WHERE ev.quando IS NOT NULL
   ORDER BY ev.quando DESC
   LIMIT greatest(1, least(coalesce(p_limite, 60), 300))
$function$;

-- ------------------------------------------------------------ mudar o horário
CREATE OR REPLACE FUNCTION crm_visita_mudar_horario(p_visita bigint, p_quando timestamptz, p_quem text)
RETURNS TABLE(ok boolean, mensagem text)
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public SET lock_timeout = '3s' AS $$
DECLARE
  v nai_visita;
  v_lemb interval := make_interval(mins => nai_cfg_int('lembrete_corretor_min', 60));
  v_moto interval := make_interval(mins => nai_cfg_int('aviso_motoboy_min', 30));
  v_tel  interval := make_interval(hours => nai_cfg_int('aviso_tel_horas_antes', 2));
  fmt constant text := 'DD/MM HH24:MI';
BEGIN
  SELECT * INTO v FROM nai_visita WHERE id = p_visita FOR UPDATE;
  IF v.id IS NULL OR v.excluida_em IS NOT NULL THEN
    RETURN QUERY SELECT false, 'Não achei essa visita.'; RETURN;
  END IF;
  IF v.estado IN ('realizada', 'encerrada', 'cancelada', 'expirada', 'coletando') THEN
    RETURN QUERY SELECT false, 'Essa visita já terminou (' || v.estado || '): o horário não muda mais.'; RETURN;
  END IF;
  IF p_quando IS NULL OR p_quando <= now() THEN
    RETURN QUERY SELECT false, 'Esse horário já passou.'; RETURN;
  END IF;
  IF p_quando > now() + interval '120 days' THEN
    RETURN QUERY SELECT false, 'Horário longe demais (mais de 4 meses).'; RETURN;
  END IF;
  IF p_quando = v.quando THEN
    RETURN QUERY SELECT true, 'O horário já era esse.'; RETURN;
  END IF;

  UPDATE nai_visita
     SET quando = p_quando,
         quando_sugerido = CASE WHEN quando_sugerido IS NOT DISTINCT FROM p_quando THEN NULL ELSE quando_sugerido END,
         -- cada lembrete volta a valer só se a hora dele ainda não passou
         lembrete_periodo_em = CASE WHEN nai_inicio_periodo(p_quando) > now() THEN NULL ELSE lembrete_periodo_em END,
         lembrete_1h_em      = CASE WHEN p_quando - v_lemb > now() THEN NULL ELSE lembrete_1h_em END,
         aviso_motoboy_em    = CASE WHEN p_quando - v_moto > now() THEN NULL ELSE aviso_motoboy_em END,
         aviso_tel_em        = CASE WHEN p_quando - v_tel  > now() THEN NULL ELSE aviso_tel_em END,
         atualizado_em = now()
   WHERE id = v.id;
  PERFORM nai_evento(v.id, 'horario_mudado_no_crm',
    coalesce(to_char(v.quando AT TIME ZONE 'America/Manaus', fmt), '?') || ' → ' ||
    to_char(p_quando AT TIME ZONE 'America/Manaus', fmt) || ' (por ' || coalesce(nullif(btrim(p_quem), ''), 'CRM') || ')');
  RETURN QUERY SELECT true, 'Horário mudado para ' || to_char(p_quando AT TIME ZONE 'America/Manaus', fmt) || '. Ninguém foi avisado.';
END $$;

-- ------------------------------------------------------------ realizada
CREATE OR REPLACE FUNCTION crm_visita_realizada(p_visita bigint, p_quem text)
RETURNS TABLE(ok boolean, mensagem text)
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public SET lock_timeout = '3s' AS $$
DECLARE
  v nai_visita;
  c nai_contato;
  v_nome text;
  v_extra text := '';
BEGIN
  SELECT * INTO v FROM nai_visita WHERE id = p_visita FOR UPDATE;
  IF v.id IS NULL OR v.excluida_em IS NOT NULL THEN
    RETURN QUERY SELECT false, 'Não achei essa visita.'; RETURN;
  END IF;
  IF v.estado IN ('realizada', 'encerrada', 'cancelada', 'expirada', 'coletando') THEN
    RETURN QUERY SELECT false, 'Essa visita já está ' || v.estado || '.'; RETURN;
  END IF;
  IF v.quando IS NULL OR v.quando > now() THEN
    RETURN QUERY SELECT false, 'A visita ainda não aconteceu (é ' || coalesce(to_char(v.quando AT TIME ZONE 'America/Manaus', 'DD/MM "às" HH24:MI'), 'sem data') || ').'; RETURN;
  END IF;

  -- a mesma rotina do nai_agenda_tick, 1h depois da visita
  SELECT * INTO c FROM nai_contato WHERE id = v.corretor_id;
  v_nome := nai_vocativo(coalesce(c.nome_completo, c.nome_whatsapp));
  PERFORM nai_enfileirar_texto(NULL, v.id, v.corretor_id, 'corretor',
    'E aí' || coalesce(', ' || v_nome, '') || ', como foi a visita no ' || nai_ref_imovel(v.codigo) || '? O cliente gostou?',
    'pos_visita', 1);
  IF v.acesso = 'buscar_chave' AND v.motoboy_id IS NOT NULL AND v.devolver_chave_em IS NULL THEN
    PERFORM nai_enfileirar_texto(NULL, v.id, v.motoboy_id, 'motoboy',
      '' || nai_acompanhante() || ', não esquece de devolver a chave do ' || nai_ref_imovel(v.codigo) || ' ao proprietário.', 'devolver_chave', 2);
    UPDATE nai_visita SET devolver_chave_em = now() WHERE id = v.id;
    v_extra := ' e lembrei o ' || nai_acompanhante() || ' de devolver a chave';
  END IF;
  UPDATE nai_visita SET pos_visita_em = now(), estado = 'realizada', aguardando = NULL, senha = NULL, atualizado_em = now()
   WHERE id = v.id;
  PERFORM nai_evento(v.id, 'realizada', 'marcada no CRM por ' || coalesce(nullif(btrim(p_quem), ''), 'alguém'));
  PERFORM nai_liberar_chats_da_visita(v.id);
  RETURN QUERY SELECT true, 'Marcada como realizada. A Nay perguntou ao corretor como foi' || v_extra || '.';
END $$;

-- ------------------------------------------------------------ excluir
CREATE OR REPLACE FUNCTION crm_visita_excluir(p_visita bigint, p_quem text)
RETURNS TABLE(ok boolean, mensagem text)
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public SET lock_timeout = '3s' AS $$
DECLARE
  v nai_visita;
  v_barradas int;
  quem text := coalesce(nullif(btrim(p_quem), ''), 'CRM');
BEGIN
  SELECT * INTO v FROM nai_visita WHERE id = p_visita FOR UPDATE;
  IF v.id IS NULL THEN RETURN QUERY SELECT false, 'Não achei essa visita.'; RETURN; END IF;
  IF v.excluida_em IS NOT NULL THEN RETURN QUERY SELECT true, 'Essa visita já tinha sido excluída.'; RETURN; END IF;

  UPDATE nai_visita
     SET excluida_em = now(), excluida_por = quem,
         estado = CASE WHEN estado IN ('encerrada', 'cancelada', 'expirada') THEN estado ELSE 'cancelada' END,
         aguardando = NULL, senha = NULL,
         encerrada_em = coalesce(encerrada_em, now()),
         motivo = coalesce(motivo, 'Excluída no CRM por ' || quem),
         atualizado_em = now()
   WHERE id = v.id;
  -- o que a Nay ainda ia mandar sobre ela não sai mais ("sem avisar ninguém")
  WITH b AS (
    UPDATE nai_saida SET estado = 'bloqueado', bloqueio = 'visita excluída no CRM'
     WHERE visita_id = v.id AND estado = 'pendente' RETURNING 1)
  SELECT count(*) INTO v_barradas FROM b;
  PERFORM nai_evento(v.id, 'excluida_no_crm', 'por ' || quem);
  PERFORM nai_liberar_chats_da_visita(v.id);
  RETURN QUERY SELECT true, 'Visita excluída. Ninguém foi avisado' ||
    CASE WHEN v_barradas > 0 THEN ' (' || v_barradas || ' mensagem da fila não sai mais)' ELSE '' END || '.';
END $$;

REVOKE ALL ON FUNCTION crm_visita_mudar_horario(bigint, timestamptz, text), crm_visita_realizada(bigint, text),
                       crm_visita_excluir(bigint, text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION crm_visita_mudar_horario(bigint, timestamptz, text), crm_visita_realizada(bigint, text),
                          crm_visita_excluir(bigint, text) TO nay_disparo;

COMMIT;
