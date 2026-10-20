-- 443 (Pedro, 20/10/2026: "um checklist de visita agendada mostrando se ela falou com todos ... (v) proprietario (v)
-- corretor (v) motoboy"; perguntado, ele escolheu "a Nay passa a avisar" o motoboy): quando a visita confirmada pelo
-- corretor passa para a Rayssa, o acompanhante ativo da equipe (nai_motoboy) recebe a visita completa e a pergunta se
-- consegue acompanhar. A Nay não responde o acompanhante (186): a resposta dele é lida pelo checklist do grupo.
BEGIN;
SET LOCAL lock_timeout = '3s';
INSERT INTO nai_config (chave, valor) VALUES ('visita_avisar_motoboy', 'sim') ON CONFLICT (chave) DO NOTHING;
CREATE OR REPLACE FUNCTION public.nai_visita_para_a_rayssa(p_visita bigint, p_turno bigint)
 RETURNS text
 LANGUAGE plpgsql
AS $function$
DECLARE
  v       nai_visita;
  dono    record;
  v_prop  bigint;
  v_apr   bigint := nai_aprovador_contato();
  v_min_h int := nai_cfg_int('antecedencia_minima_horas', 2);
  v_dono  text;
  v_urg   text := '';
  moto    record;
BEGIN
  SELECT * INTO v FROM nai_visita WHERE id = p_visita FOR UPDATE;
  IF v.id IS NULL THEN RETURN NULL; END IF;
  SELECT * INTO dono FROM nai_proprietario_do_imovel(v.codigo);
  IF v.prop_telefone_manual IS NOT NULL THEN
    dono.telefone := v.prop_telefone_manual;
    dono.motivo   := NULL;
  END IF;
  IF dono.motivo IS NULL THEN
    v_prop := nai_contato_do_cadastro(dono.telefone, dono.nome);
  END IF;

  IF v_prop IS NOT NULL AND v_prop <> v.corretor_id THEN
    -- o dono é gravado ANTES: a trava da caixa (nai_saida_validar) só deixa sair
    -- para o proprietário da visita
    UPDATE nai_visita SET proprietario_id = v_prop, proprietario_cadastro = dono.cadastro_id,
                          proprietario_nome = dono.nome, ult_msg_prop_em = now()
     WHERE id = v.id;
    -- a 1ª solicitação ao proprietário: o mesmo texto de nai_pedir_ao_proprietario
    PERFORM nai_enfileirar_texto(p_turno, v.id, v_prop, 'proprietario',
      nai_apresentacao_prop(v_prop) || nai_saudacao() || coalesce(', ' || nai_vocativo(dono.nome), '')
        || '! Tudo bem? Aqui é a Nay, da Imob Easy. Temos um pedido de visita ' || nai_ref_imovel_prop(v.codigo)
        || ' para ' || nai_quando_humano(v.quando) || '. Tem como receber a visita nesse horário?',
      'p_solicita', 500);
    v_dono := 'Já mandei ao proprietário' || coalesce(' (' || nullif(btrim(coalesce(dono.nome, '')), '') || ')', '')
              || ' o pedido da visita; a resposta dele chega na aba Proprietários';
  ELSE
    v_dono := 'NÃO consegui mandar ao proprietário (' ||
      CASE dono.motivo WHEN 'sem_telefone' THEN 'sem telefone no cadastro'
                       WHEN 'tratar_com_outra_pessoa' THEN 'o cadastro diz: ' || coalesce(dono.nome, '')
                       WHEN 'dois_donos' THEN 'o imóvel tem dois proprietários no cadastro'
                       WHEN 'sem_cadastro' THEN 'imóvel sem proprietário cadastrado'
                       ELSE 'o telefone do proprietário é o do próprio corretor' END || '): fale você com ele';
  END IF;
  -- 443 (Pedro, 20/10/2026: a Nay passa a avisar o motoboy): o acompanhante ativo da equipe recebe a visita completa
  -- junto com o pedido ao proprietário. O checklist do grupo (nay-olx, olx/visitas_parceria.py) marca se saiu e se ele
  -- respondeu. Desligar: nai_config visita_avisar_motoboy = nao.
  IF coalesce(nai_cfg('visita_avisar_motoboy', 'sim'), 'sim') = 'sim' THEN
    SELECT * INTO moto FROM nai_motoboy();
    IF moto.contato_id IS NOT NULL AND moto.contato_id <> v.corretor_id THEN
      UPDATE nai_visita SET motoboy_id = moto.contato_id, ult_msg_moto_em = now() WHERE id = v.id;
      PERFORM nai_enfileirar_texto(p_turno, v.id, moto.contato_id, 'motoboy',
        nai_texto_visita_completa(v.id, 'Oi, ' || coalesce(nullif(split_part(btrim(coalesce(moto.nome, '')), ' ', 1), ''), 'tudo bem')
          || '! Aqui é a Nay, da Imob Easy. Pedido de visita (o horário ainda está sendo confirmado com o proprietário)')
          || E'\n\nVocê consegue acompanhar? Me responde SIM ou NÃO, por favor.',
        'visita_motoboy', 520);
      PERFORM nai_evento(v.id, 'motoboy_avisado', left(coalesce(moto.nome, ''), 200));
    END IF;
  END IF;

  IF v.quando IS NOT NULL AND v.quando < now() + make_interval(hours => v_min_h) THEN
    v_urg := ' EM CIMA DA HORA';
  END IF;

  UPDATE nai_visita SET estado = 'com_rayssa', aguardando = 'equipe', atualizado_em = now() WHERE id = v.id;
  PERFORM nai_evento(v.id, 'com_a_rayssa', left(v_dono, 200));
  IF v_apr IS NOT NULL THEN
    PERFORM nai_enfileirar_texto(p_turno, v.id, v_apr, 'equipe',
      nai_texto_visita_completa(v.id, nai_cfg('aprovador_visita_nome', 'Rayssa') || ', visita confirmada pelo corretor'
        || v_urg || '. ' || v_dono || '. A partir de agora ela é sua: o corretor está na aba Visitas do CRM e eu não'
        || ' respondo mais ele até a visita acabar'),
      'visita_com_a_rayssa', 450);
  END IF;
  PERFORM nai_avisar_tel(p_turno, v.id,
    nai_texto_visita_completa(v.id, 'Tel, visita confirmada' || v_urg || ' e passada para a Rayssa. ' || v_dono),
    'visita_com_a_rayssa');
  RETURN 'com_a_rayssa';
END $function$;
COMMIT;
