-- 179a -- a visita vai direto ao proprietário (Tel, 29/09/2026, pelo Pedro:
-- "já é pra implementar mandar direto para o proprietário sem perguntar ou
-- confirmar, ela vai só avisar o Tel e o outro número lá +55 92 8595-6408
-- que está falando com o proprietário, isso após a confirmação do corretor").
--
-- Até aqui (141): o "sim" do corretor punha a visita em 'aguardando_rayssa' e
-- o pedido ia ao número da Imob Easy (aprovador_visita_telefone, o 8595-6408)
-- esperando SIM <n>. Sem o SIM a visita ficava parada -- foi o que aconteceu
-- com a #1048 (29/09 16h): dois lembretes, nenhuma resposta, e às 13h ela
-- caiu no Tel.
--
-- Agora o "sim" do corretor já é a aprovação: a Nay segue para o proprietário
-- pelo mesmo caminho que o SIM seguia (nai_visita_seguir_para_proprietario) e
-- só AVISA o Tel e o número da Imob Easy. Ficam de pé as duas conferências que
-- o SIM também fazia: em cima da hora (antecedencia_minima_horas) a visita é
-- do Tel, e sem telefone do proprietário nai_pedir_ao_proprietario passa ao
-- Tel (como sempre).
--
-- Interruptor, sem deploy: nai_config.visita_sem_aprovacao = 'sim' (novo) ou
-- 'nao' (volta o pedido de SIM ao número da Imob Easy, o corpo antigo, intacto).

BEGIN;
SET LOCAL lock_timeout = '5s';

INSERT INTO nai_config (chave, valor, descricao)
VALUES ('visita_sem_aprovacao', 'sim',
        'sim = o "sim" do corretor ja leva a visita ao proprietario; a Nay so avisa o Tel e o aprovador (179). nao = pede SIM <n> ao aprovador antes (141).')
ON CONFLICT (chave) DO NOTHING;

CREATE OR REPLACE FUNCTION public.nai_visita_corretor_confirmou(p_visita bigint, p_turno bigint)
 RETURNS void
 LANGUAGE plpgsql
AS $function$
DECLARE
  v       nai_visita;
  v_apr   bigint := nai_aprovador_contato();
  v_min_h int := nai_cfg_int('antecedencia_minima_horas', 2);
  dono    record;
  v_pede  text;
  v_res   text;
  v_dono  text;
BEGIN
  SELECT * INTO v FROM nai_visita WHERE id = p_visita FOR UPDATE;
  IF v.id IS NULL OR v.estado <> 'confirmando' THEN RETURN; END IF;

  -- 179: o "sim" do corretor ja e a aprovacao
  IF nai_cfg('visita_sem_aprovacao', 'sim') = 'sim' THEN
    UPDATE nai_visita SET confirmada_corretor_em = now(), aprovada_em = now(),
                          aprovada_por = 'automática (o corretor confirmou)', atualizado_em = now()
     WHERE id = v.id;
    PERFORM nai_evento(v.id, 'corretor_confirmou', nai_hora_exata(v.quando));
    PERFORM nai_evento(v.id, 'aprovada', 'automática');

    -- em cima da hora continua sendo do Tel (a mesma conferência do SIM)
    IF v.quando < now() + make_interval(hours => v_min_h) THEN
      UPDATE nai_visita SET estado = 'com_tel', aguardando = 'tel', atualizado_em = now() WHERE id = v.id;
      PERFORM nai_avisar_tel(p_turno, v.id,
        nai_texto_visita_completa(v.id, 'Tel, o corretor confirmou mas a visita é em cima da hora (menos de ' || v_min_h
          || 'h) -- ela é sua. Parei o chat do corretor. Visita'),
        'visita_urgente');
      PERFORM nai_parar_chat(v.corretor_id, 'visita #' || v.id || ': em cima da hora');
      RETURN;
    END IF;

    -- sem telefone do proprietário, nai_pedir_ao_proprietario passa ao Tel e avisa
    v_res := nai_visita_seguir_para_proprietario(v.id, p_turno);
    IF v_res = 'com_tel' THEN RETURN; END IF;

    SELECT * INTO dono FROM nai_proprietario_do_imovel(v.codigo);
    v_dono := coalesce(' (' || nullif(btrim(coalesce(dono.nome, '')), '') || ')', '');
    PERFORM nai_avisar_tel(p_turno, v.id,
      nai_texto_visita_completa(v.id, 'Tel, o corretor confirmou e já estou falando com o proprietário' || v_dono
        || ' para fechar a visita'),
      'visita_com_proprietario');
    IF v_apr IS NOT NULL THEN
      PERFORM nai_enfileirar_texto(p_turno, v.id, v_apr, 'equipe',
        nai_texto_visita_completa(v.id, nai_cfg('aprovador_visita_nome', 'Rayssa')
          || ', só para você saber: o corretor confirmou e já estou falando com o proprietário' || v_dono
          || ' sobre a visita'),
        'visita_com_proprietario', 450);
    END IF;
    RETURN;
  END IF;

  -- 141 (visita_sem_aprovacao = 'nao'): pede o SIM ao aprovador
  UPDATE nai_visita SET estado = 'aguardando_rayssa', aguardando = 'equipe', confirmada_corretor_em = now(),
                        rayssa_msg_em = now(), rayssa_lembretes = 0, atualizado_em = now()
   WHERE id = v.id;
  PERFORM nai_evento(v.id, 'corretor_confirmou', nai_hora_exata(v.quando));

  SELECT * INTO dono FROM nai_proprietario_do_imovel(v.codigo);
  v_pede := CASE WHEN dono.motivo IS NULL
                 THEN 'Está tudo certo? Responda SIM ' || v.id || ' para eu falar com o proprietário, ou NÃO ' || v.id || '.'
                 ELSE 'Falta o telefone do proprietário. Me manda assim: TELEFONE ' || v.id
                      || ' 92 99999-9999 -- e depois SIM ' || v.id || '. Ou NÃO ' || v.id || '.' END;
  IF v_apr IS NOT NULL THEN
    PERFORM nai_enfileirar_texto(p_turno, v.id, v_apr, 'equipe',
      nai_texto_visita_completa(v.id, nai_cfg('aprovador_visita_nome', 'Rayssa') || ', pedido de visita para confirmar')
      || E'\n\n' || v_pede, 'aprovar_visita', 450);
  END IF;
  PERFORM nai_avisar_tel(p_turno, v.id,
    nai_texto_visita_completa(v.id, 'Tel, novo pedido de visita (a ' || nai_cfg('aprovador_visita_nome', 'Rayssa') || ' vai confirmar)'),
    'visita_pedida');
END;
$function$;

COMMIT;
