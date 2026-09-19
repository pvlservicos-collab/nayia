-- =====================================================================
-- NAI -- 35b: o encaixe da apresentacao na primeira mensagem ao proprietario.
--
-- Gerado por `scratchpad/patch_apresentacao.py` a partir do que estava NO
-- BANCO. Um acrescimo, nenhuma remocao: a chamada a `nai_apresentacao_prop`
-- na frente do texto -- e ela devolve vazio quando nao e a primeira vez, ou
-- quando a frase estiver vazia na configuracao.
--
-- Rode `35_apresentacao_ao_proprietario.sql` ANTES deste arquivo.
-- =====================================================================

CREATE OR REPLACE FUNCTION public.nai_pedir_ao_proprietario(p_visita bigint, p_turno bigint)
 RETURNS text
 LANGUAGE plpgsql
AS $function$
DECLARE
  v       nai_visita;
  c       nai_contato;
  dono    record;
  v_prop  bigint;
  v_voc   text;
  v_texto text;
BEGIN
  SELECT * INTO v FROM nai_visita WHERE id = p_visita FOR UPDATE;
  SELECT * INTO c FROM nai_contato WHERE id = v.corretor_id;
  SELECT * INTO dono FROM nai_proprietario_do_imovel(v.codigo);
  IF dono.motivo IS NULL THEN
    v_prop := nai_contato_do_cadastro(dono.telefone, dono.nome);
  END IF;

  -- Sem telefone, cadastro dizendo "tratar com", dois donos -- ou o
  -- "proprietario" e o proprio corretor: o Tel resolve.
  IF v_prop IS NULL OR v_prop = v.corretor_id THEN
    UPDATE nai_visita SET estado = 'com_tel', aguardando = 'tel', atualizado_em = now() WHERE id = v.id;
    PERFORM nai_evento(v.id, 'proprietario_sem_contato', coalesce(dono.motivo, 'mesmo_contato'));
    PERFORM nai_avisar_tel(p_turno, v.id,
      'Tel, pedido de visita no ' || nai_ref_imovel(v.codigo) || ', ' || nai_hora_exata(v.quando) || '.' ||
      E'\nCorretor: ' || coalesce(c.nome_completo, c.nome_whatsapp, '') || ' (' || nai_fone_fmt(c.telefone) || ')' ||
      E'\nNão consigo falar com o proprietário (' ||
      CASE dono.motivo WHEN 'sem_telefone' THEN 'sem telefone no cadastro'
                       WHEN 'tratar_com_outra_pessoa' THEN 'o cadastro diz: ' || coalesce(dono.nome, '')
                       WHEN 'dois_donos' THEN 'o imóvel tem dois proprietários no cadastro'
                       WHEN 'sem_cadastro' THEN 'imóvel sem proprietário cadastrado'
                       ELSE 'o telefone do proprietário é o do próprio corretor' END || ').' ||
      E'\nParei de responder esse corretor até você responder.\nQuando resolver, me responda:\nVISITA ' || v.id || E' OK  (proprietário confirmou)\nVISITA ' || v.id ||
      E' HORARIO 16h  (ele pediu outro horário)\nVISITA ' || v.id || ' CANCELA',
      'sem_proprietario');
    PERFORM nai_parar_chat(v.corretor_id, 'visita #' || v.id || ': sem contato do proprietario');
    RETURN 'com_tel';
  END IF;

  v_voc := nai_vocativo(dono.nome);
  -- Card p_solicita, humanizado como o Tel pediu ("hoje a tarde", sem data numerica).
  -- A APRESENTACAO (Tel, 15/09), so na primeira vez com este proprietario: ele
  -- ja fala com a Imob Easy em outro numero, e sem isto a mensagem chega de um
  -- desconhecido pedindo para entrar no imovel dele.
  v_texto := nai_apresentacao_prop(v_prop) ||
             nai_saudacao() || coalesce(', ' || v_voc, '') || '! Tudo bem? Aqui é a Nay, da Imob Easy. ' ||
             'Temos um pedido de visita ' || nai_ref_imovel_prop(v.codigo) ||
             ' para ' || nai_quando_humano(v.quando) || '. Tem como receber a visita nesse horário?';

  UPDATE nai_visita SET proprietario_id = v_prop, proprietario_cadastro = dono.cadastro_id,
                        proprietario_nome = dono.nome, estado = 'aguardando_proprietario', aguardando = 'proprietario',
                        ult_msg_prop_em = now(), reenvios_prop = 0, atualizado_em = now()
   WHERE id = v.id;
  PERFORM nai_enfileirar_texto(p_turno, v.id, v_prop, 'proprietario', v_texto, 'p_solicita', 500);
  RETURN 'pedido';
END;
$function$;
