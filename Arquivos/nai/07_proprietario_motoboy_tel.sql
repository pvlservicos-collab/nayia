-- =====================================================================
-- NAI atendimento locacao -- 07: proprietario, Fernando e comandos do Tel
-- =====================================================================

CREATE OR REPLACE FUNCTION nai_acesso_normalizar(p text)
RETURNS text LANGUAGE sql IMMUTABLE AS $$
  SELECT CASE
    WHEN x ~ '(fechadura|senha|eletr)' THEN 'fechadura'
    WHEN x ~ '(acompanh|eu abro|ele abre|ela abre|estar la|estarei|proprietario abre|dono abre|abrir)' THEN 'proprietario_acompanha'
    WHEN x ~ '(pegar|buscar|retirar|pega a chave|busca a chave|comigo|com o proprietario|portaria)' THEN 'buscar_chave'
    WHEN x ~ '(chave.*(conosco|com voces|com a gente|imobiliaria|easy|escritorio)|chave_conosco)' THEN 'chave_conosco'
    WHEN x IN ('chave_conosco', 'buscar_chave', 'fechadura', 'proprietario_acompanha') THEN x
    ELSE NULL END
  FROM (SELECT lower(translate(coalesce(p, ''), 'áàâãéêíóôõúç', 'aaaaeeiooouc')) AS x) t;
$$;

-- Linha do acesso para o CORRETOR (nunca senha, nunca nome do proprietario:
-- regra do Tel, "o contato do proprietario voce NUNCA passa").
CREATE OR REPLACE FUNCTION nai_linha_acesso_corretor(p_acesso text)
RETURNS text LANGUAGE sql IMMUTABLE AS $$
  SELECT CASE p_acesso
    -- Chave conosco: o corretor nao precisa saber do arranjo (Tel, 12/09).
    WHEN 'chave_conosco' THEN '🔑 A chave fica por nossa conta, deixa que eu providencio.'
    WHEN 'buscar_chave' THEN '🔑 O Fernando pega a chave antes e abre pra vocês.'
    WHEN 'fechadura' THEN '🔐 O imóvel tem fechadura eletrônica, o Fernando abre pra vocês.'
    WHEN 'proprietario_acompanha' THEN '🙋 O proprietário vai estar lá pra abrir. Chega no horário certinho, tá?'
    ELSE '' END;
$$;

-- Linha do acesso para o FERNANDO (equipe: pode tudo, menos a senha antes da hora).
CREATE OR REPLACE FUNCTION nai_linha_acesso_motoboy(v nai_visita)
RETURNS text LANGUAGE sql STABLE AS $$
  SELECT CASE v.acesso
    WHEN 'chave_conosco' THEN 'A chave está com a gente.'
    WHEN 'buscar_chave' THEN 'A chave fica com o proprietário' || coalesce(': ' || v.acesso_detalhe, '') || '. Precisa pegar antes e devolver depois.'
    WHEN 'fechadura' THEN 'É fechadura eletrônica: te mando a senha ' || nai_cfg_int('aviso_motoboy_min', 30) || ' minutos antes.'
    WHEN 'proprietario_acompanha' THEN 'O proprietário vai estar lá para abrir.'
    ELSE 'O acesso ainda vou confirmar com o Tel.' END;
$$;

-- Depois que o proprietario aceitou o horario: acerta o acesso e, com
-- tudo certo, confirma com ele e chama o Fernando. p_devolver = true
-- devolve o texto para o PROPRIETARIO (o agente dele diz); false enfileira.
CREATE OR REPLACE FUNCTION nai_prosseguir_acesso(p_visita bigint, p_turno bigint, p_devolver boolean)
RETURNS text LANGUAGE plpgsql AS $$
DECLARE
  v       nai_visita;
  c       nai_contato;
  ac      nai_acesso_imovel;
  v_texto text;
  v_moto  text;
BEGIN
  SELECT * INTO v FROM nai_visita WHERE id = p_visita FOR UPDATE;
  SELECT * INTO c FROM nai_contato WHERE id = v.corretor_id;

  IF v.acesso IS NULL THEN
    SELECT * INTO ac FROM nai_acesso_imovel WHERE codigo = v.codigo;
    IF ac.codigo IS NOT NULL THEN
      UPDATE nai_visita SET acesso = ac.acesso, acesso_detalhe = coalesce(acesso_detalhe, ac.detalhe) WHERE id = v.id
      RETURNING * INTO v;
    ELSIF EXISTS (SELECT 1 FROM imovel_privado p WHERE p.codigo = v.codigo AND p.proprietario_acompanha) THEN
      UPDATE nai_visita SET acesso = 'proprietario_acompanha' WHERE id = v.id RETURNING * INTO v;
    END IF;
  END IF;

  IF v.acesso IS NULL THEN
    -- Pergunta curta (Tel, 13/09: "ela so pergunta: E como e para entrar? precisa de chave?").
    v_texto := 'E como é para entrar? precisa de chave?';
    UPDATE nai_visita SET estado = 'aguardando_acesso', aguardando = 'proprietario', atualizado_em = now() WHERE id = v.id;
  ELSIF v.acesso = 'fechadura' AND v.senha IS NULL THEN
    v_texto := 'Obrigada! Pode me passar a senha da fechadura? Ela fica só com o Fernando, que acompanha a visita.';
    UPDATE nai_visita SET estado = 'aguardando_acesso', aguardando = 'proprietario', atualizado_em = now() WHERE id = v.id;
  ELSIF v.acesso = 'buscar_chave' AND v.acesso_detalhe IS NULL THEN
    v_texto := 'Obrigada! Onde e a partir de que horas o Fernando pode pegar a chave?';
    UPDATE nai_visita SET estado = 'aguardando_acesso', aguardando = 'proprietario', atualizado_em = now() WHERE id = v.id;
  ELSE
    -- Tudo certo com o proprietario: confirma com ele e chama o Fernando.
    -- Cards c_prop ("Visita confirmada ... de forma humanizada") e, com a
    -- chave conosco, novo_5 ("so passando para avisar que vamos fazer uma visita").
    v_texto := CASE WHEN v.acesso = 'chave_conosco'
      THEN 'Obrigada! Só passando para avisar que a visita fica ' || nai_quando_humano(v.quando) || '. '
      ELSE 'Combinado, então: visita confirmada ' || nai_quando_humano(v.quando) || '. ' END ||
      -- sem nome/CPF do visitante: no fluxo v17 eles chegam DEPOIS da confirmacao
      'O Fernando, da nossa equipe, acompanha a visita. Qualquer novidade eu aviso por aqui.';
    -- Card "Avisar motoboy", literal (revisao de 13/09): sem o acesso aqui -- o
    -- acesso vai no "Fechado, Fernando, agendei aqui", depois que ele confirma (card novo_8).
    v_moto := 'Olá, reservamos uma visita ao imóvel ' || nai_endereco_interno(v.codigo) ||
      coalesce(' do proprietário ' || v.proprietario_nome, '') || ', ' || nai_hora_exata(v.quando) ||
      ', pelo corretor ' || coalesce(c.nome_completo, c.nome_whatsapp, '') || ' (' || nai_fone_fmt(c.telefone) || ').' ||
      ' Posso confirmar que você vai acompanhar?';
    UPDATE nai_visita SET estado = 'aguardando_motoboy', aguardando = 'motoboy', ult_msg_moto_em = now(),
                          reenvios_moto = 0, atualizado_em = now() WHERE id = v.id;
    IF v.motoboy_id IS NULL THEN
      UPDATE nai_visita SET estado = 'com_tel', aguardando = 'tel' WHERE id = v.id;
      PERFORM nai_avisar_tel(p_turno, v.id, 'Tel, a visita #' || v.id || ' (' || nai_ref_imovel(v.codigo) || ', ' ||
        nai_hora_exata(v.quando) || ') foi aceita pelo proprietário, mas não tenho o Fernando cadastrado na equipe.', 'sem_motoboy');
    ELSE
      PERFORM nai_enfileirar_texto(p_turno, v.id, v.motoboy_id, 'motoboy', v_moto, 'flag_fernando', 600);
    END IF;
    PERFORM nai_evento(v.id, 'proprietario_ok', v.acesso);
  END IF;

  IF p_devolver THEN RETURN v_texto; END IF;
  PERFORM nai_enfileirar_texto(p_turno, v.id, v.proprietario_id, 'proprietario', v_texto, 'acesso_ou_confirmacao', 500);
  RETURN NULL;
END;
$$;

-- -------------------------------------------- resposta do proprietario
CREATE OR REPLACE FUNCTION nai_resposta_proprietario(p_turno bigint, p_decisao text, p_quando text,
                                                     p_acesso text, p_detalhe text, p_senha text)
RETURNS TABLE(texto_pronto text, instrucao_para_voce text)
LANGUAGE plpgsql AS $$
DECLARE
  t      nai_turno;
  v      nai_visita;
  k      nai_contato;
  dec    text := lower(coalesce(p_decisao, ''));
  q      timestamptz := nai_ler_quando(p_quando);
  v_ac   text := nai_acesso_normalizar(p_acesso);
  v_txt  text;
BEGIN
  SELECT * INTO t FROM nai_turno WHERE id = p_turno;
  IF t.id IS NULL OR t.papel <> 'proprietario' THEN
    RETURN QUERY SELECT NULL::text, 'esta ferramenta e so para quando quem escreve e o PROPRIETARIO.'::text; RETURN;
  END IF;
  SELECT * INTO k FROM nai_contato WHERE id = t.contato_id;

  IF t.visita_id IS NULL THEN
    -- Sem visita definida: nada se decide; o Tel fica sabendo.
    PERFORM nai_avisar_tel(p_turno, NULL, 'Tel, o proprietário ' || coalesce(k.nome_whatsapp, '') || ' (' ||
      nai_fone_fmt(k.telefone) || ') escreveu e não sei de qual visita é: "' || left(coalesce(t.texto, ''), 300) ||
      E'"\nParei de responder esse contato. Para eu voltar: DEVOLVER ' || nai_fone_fmt(k.telefone) || '.', 'proprietario_sem_visita');
    PERFORM nai_parar_chat(k.id, 'proprietario sem visita definida');
    RETURN QUERY SELECT NULL::text,
      'ja avisei o Tel. A pessoa NAO fica sabendo (regra do Tel, 12/09): responda exatamente SILENCIO.'::text; RETURN;
  END IF;
  SELECT * INTO v FROM nai_visita WHERE id = t.visita_id FOR UPDATE;
  IF NOT nai_visita_aberta(v.estado) THEN
    RETURN QUERY SELECT 'Obrigada! Essa visita já foi encerrada, qualquer coisa te aviso por aqui.'::text, NULL::text; RETURN;
  END IF;

  -- Aprende o acesso (sem senha) para a proxima visita deste imovel.
  IF v_ac IS NOT NULL THEN
    UPDATE nai_visita SET acesso = v_ac, acesso_detalhe = coalesce(NULLIF(btrim(coalesce(p_detalhe, '')), ''), acesso_detalhe)
     WHERE id = v.id RETURNING * INTO v;
    INSERT INTO nai_acesso_imovel (codigo, acesso, detalhe, fonte)
         VALUES (v.codigo, v_ac, NULLIF(btrim(coalesce(p_detalhe, '')), ''), 'proprietario')
    ON CONFLICT (codigo) DO UPDATE SET acesso = EXCLUDED.acesso,
      detalhe = coalesce(EXCLUDED.detalhe, nai_acesso_imovel.detalhe), fonte = 'proprietario', atualizado_em = now();
  ELSIF p_detalhe IS NOT NULL AND btrim(p_detalhe) <> '' AND v.acesso = 'buscar_chave' THEN
    UPDATE nai_visita SET acesso_detalhe = btrim(p_detalhe) WHERE id = v.id RETURNING * INTO v;
    UPDATE nai_acesso_imovel SET detalhe = btrim(p_detalhe), atualizado_em = now() WHERE codigo = v.codigo;
  END IF;
  IF nullif(btrim(coalesce(p_senha, '')), '') IS NOT NULL THEN
    UPDATE nai_visita SET senha = btrim(p_senha), acesso = coalesce(acesso, 'fechadura') WHERE id = v.id RETURNING * INTO v;
  END IF;

  IF dec IN ('aceita', 'sim', 'confirma') THEN
    IF v.estado NOT IN ('aguardando_proprietario', 'negociando', 'aguardando_acesso') THEN
      RETURN QUERY SELECT 'Obrigada!'::text, 'nao havia nada esperando confirmacao dele; so agradeca.'::text; RETURN;
    END IF;
    UPDATE nai_visita SET prop_ok_em = coalesce(prop_ok_em, now()), aguardando = NULL, atualizado_em = now()
     WHERE id = v.id;
    PERFORM nai_evento(v.id, 'proprietario_aceitou', NULL);
    v_txt := nai_prosseguir_acesso(v.id, p_turno, true);
    RETURN QUERY SELECT v_txt, 'diga o texto_pronto como veio, sem acrescentar pergunta.'::text; RETURN;
  END IF;

  IF dec = 'acesso' THEN
    IF v.prop_ok_em IS NULL THEN
      UPDATE nai_visita SET prop_ok_em = now() WHERE id = v.id;
    END IF;
    v_txt := nai_prosseguir_acesso(v.id, p_turno, true);
    RETURN QUERY SELECT v_txt, 'diga o texto_pronto como veio.'::text; RETURN;
  END IF;

  IF dec IN ('outro_horario', 'recusa', 'nao') THEN
    IF q IS NULL THEN
      UPDATE nai_visita SET estado = 'negociando', aguardando = 'proprietario', atualizado_em = now() WHERE id = v.id;
      PERFORM nai_evento(v.id, 'proprietario_recusou', NULL);
      RETURN QUERY SELECT 'Sem problemas! Qual outro horário fica bom pra você receber a visita?'::text,
        'quando ele disser, chame resposta_do_proprietario com decisao outro_horario e o horario.'::text; RETURN;
    END IF;
    IF q <= now() + interval '10 minutes' THEN
      RETURN QUERY SELECT 'Esse horário já passou. Qual outro fica bom?'::text, NULL::text; RETURN;
    END IF;
    UPDATE nai_visita SET quando_sugerido = q, estado = 'negociando', aguardando = 'corretor', atualizado_em = now()
     WHERE id = v.id;
    PERFORM nai_evento(v.id, 'proprietario_sugeriu', nai_hora_exata(q));
    PERFORM nai_enfileirar_texto(p_turno, v.id, v.corretor_id, 'corretor',
      coalesce(nai_vocativo((SELECT coalesce(nome_completo, nome_whatsapp) FROM nai_contato WHERE id = v.corretor_id)) || ', ', '') ||
      'o proprietário não consegue ' || nai_quando_humano(v.quando) || ', mas sugeriu ' || nai_quando_humano(q) ||
      '. Funciona pro seu cliente?', 'proprietario_sugeriu', 400);
    -- sem "vou ver e te retorno" (Tel, 13/09): o proprietario ouve de novo quando houver resposta.
    RETURN QUERY SELECT NULL::text, 'levei o horario ao corretor. responda exatamente SILENCIO.'::text;
    RETURN;
  END IF;

  IF dec = 'cancela' THEN
    UPDATE nai_visita SET estado = 'com_tel', aguardando = 'tel', atualizado_em = now() WHERE id = v.id;
    PERFORM nai_evento(v.id, 'proprietario_nao_quer', p_detalhe);
    PERFORM nai_avisar_tel(p_turno, v.id, 'Tel, o proprietário do ' || nai_ref_imovel(v.codigo) ||
      ' não quer (ou não pode) a visita #' || v.id || ' (' || nai_hora_exata(v.quando) || '): "' || left(coalesce(t.texto, ''), 300) ||
      E'"\nParei com o proprietário e com o corretor até você responder.\nMe responda VISITA ' || v.id || ' CANCELA ou VISITA ' || v.id || ' HORARIO <novo horário>.', 'proprietario_nao_quer');
    PERFORM nai_parar_chat(t.contato_id, 'visita #' || v.id || ': proprietario nao quer');
    PERFORM nai_parar_chat(v.corretor_id, 'visita #' || v.id || ': proprietario nao quer');
    -- CALADA (Tel, 12/09): foi para o Tel, o corretor nao e avisado.
    RETURN QUERY SELECT NULL::text,
      'ja avisei o Tel. A pessoa NAO fica sabendo (regra do Tel, 12/09): responda exatamente SILENCIO.'::text; RETURN;
  END IF;

  -- duvida ou qualquer outra coisa: e com o Tel (proprietario fora de agenda).
  PERFORM nai_avisar_tel(p_turno, v.id, 'Tel, o proprietário do ' || nai_ref_imovel(v.codigo) || ' (visita #' || v.id ||
    ') perguntou: "' || left(coalesce(nullif(p_detalhe, ''), t.texto, ''), 300) ||
    E'"\nParei de responder o proprietário. Qualquer comando VISITA ' || v.id || ' seu me devolve a conversa.', 'proprietario_duvida');
  PERFORM nai_parar_chat(t.contato_id, 'visita #' || v.id || ': pergunta do proprietario');
  RETURN QUERY SELECT NULL::text,
      'ja avisei o Tel. A pessoa NAO fica sabendo (regra do Tel, 12/09): responda exatamente SILENCIO.'::text;
END;
$$;

-- --------------------------------------------------- visita confirmada
CREATE OR REPLACE FUNCTION nai_confirmar_visita(p_visita bigint, p_turno bigint)
RETURNS void LANGUAGE plpgsql AS $$
DECLARE v nai_visita; c nai_contato; m record; v_nome text; d record; v_pede text;
BEGIN
  SELECT * INTO v FROM nai_visita WHERE id = p_visita FOR UPDATE;
  SELECT * INTO c FROM nai_contato WHERE id = v.corretor_id;
  SELECT * INTO m FROM nai_motoboy();
  v_nome := nai_vocativo(coalesce(c.nome_completo, c.nome_whatsapp));
  UPDATE nai_visita SET estado = 'confirmada', aguardando = NULL, confirmada_em = now(), atualizado_em = now()
   WHERE id = v.id;
  PERFORM nai_evento(v.id, 'confirmada', NULL);
  PERFORM nai_enfileirar_texto(p_turno, v.id, v.corretor_id, 'corretor',
    'Visita confirmada' || coalesce(', ' || v_nome, '') || '! 🙌 ' || initcap(left(nai_quando_humano(v.quando), 1)) ||
    substr(nai_quando_humano(v.quando), 2) || ', no ' || nai_ref_imovel(v.codigo) || '.' ||
    E'\nQuem vai acompanhar sua visita é o Fernando' || coalesce(', ' || nai_fone_fmt(m.telefone), '') || '.' ||
    CASE WHEN nai_linha_acesso_corretor(v.acesso) <> '' THEN E'\n' || nai_linha_acesso_corretor(v.acesso) ELSE '' END,
    'visita_confirmada', 400);
  -- Fluxo v17 (Tel, 13/09): SO AGORA os dados. Cards "Checa os dados do
  -- corretor" -> CORRETOR CONHECIDO / CORRETOR NOVO, sem o "vou confirmar aqui
  -- a visita" (ela ja esta confirmada) -- "tira o vou confirmar e pede claramente".
  SELECT * INTO d FROM nai_dados_corretor(c.id);
  IF NOT coalesce(d.completo, false) THEN
    v_pede := 'Me passa o ' || nai_lista_pt(ARRAY_REMOVE(ARRAY[
      CASE WHEN d.nome_completo IS NULL THEN 'seu nome completo' END,
      CASE WHEN d.cpf IS NULL THEN 'o CPF' END,
      CASE WHEN d.creci IS NULL THEN 'o CRECI' END], NULL)) || '?';
  ELSIF v.visitante_nome IS NULL OR v.visitante_cpf IS NULL THEN
    v_pede := 'Me passa o nome completo e o CPF do visitante?';
  END IF;
  IF v_pede IS NOT NULL THEN
    PERFORM nai_enfileirar_texto(p_turno, v.id, v.corretor_id, 'corretor', v_pede, 'pedir_dados', 401);
    UPDATE nai_visita SET lembretes_dados = 0,
           proximo_lembrete_dados_em = now() + make_interval(mins => nai_cfg_int('dados_primeiro_lembrete_min', 3))
     WHERE id = v.id;
  END IF;
END;
$$;

-- ----------------------------------------------------- resposta do Fernando
CREATE OR REPLACE FUNCTION nai_resposta_motoboy(p_turno bigint, p_visita text, p_decisao text, p_obs text)
RETURNS TABLE(texto_pronto text, instrucao_para_voce text)
LANGUAGE plpgsql AS $$
DECLARE
  t   nai_turno;
  v   nai_visita;
  dec text := lower(coalesce(p_decisao, ''));
  v_id bigint := coalesce(NULLIF(regexp_replace(coalesce(p_visita, ''), '\D', '', 'g'), '')::bigint, NULL);
BEGIN
  SELECT * INTO t FROM nai_turno WHERE id = p_turno;
  IF t.id IS NULL OR t.papel <> 'motoboy' THEN
    RETURN QUERY SELECT NULL::text, 'so para quando quem escreve e o Fernando.'::text; RETURN;
  END IF;
  -- A visita: a do cabecalho; senao, a que ele citou -- mas SO se for dele.
  SELECT * INTO v FROM nai_visita x
   WHERE x.id = coalesce(t.visita_id, v_id)
     AND nai_visita_aberta(x.estado)
     AND (x.motoboy_id = t.contato_id OR t.teste);
  IF v.id IS NULL THEN
    RETURN QUERY SELECT NULL::text, 'nao sei de qual visita ele fala. mostre a lista do contexto e pergunte qual (pelo numero da visita).'::text; RETURN;
  END IF;

  IF dec IN ('confirma', 'sim', 'ok') THEN
    UPDATE nai_visita SET moto_ok_em = now(), atualizado_em = now() WHERE id = v.id RETURNING * INTO v;
    PERFORM nai_evento(v.id, 'motoboy_ok', p_obs);
    IF v.prop_ok_em IS NOT NULL AND v.estado = 'aguardando_motoboy' THEN
      PERFORM nai_confirmar_visita(v.id, p_turno);
    END IF;
    RETURN QUERY SELECT nai_texto_motoboy_ok(v), 'diga o texto_pronto como veio.'::text; RETURN;
  END IF;

  IF dec IN ('nao_pode', 'nao', 'problema', 'imprevisto') THEN
    UPDATE nai_visita SET estado = 'com_tel', aguardando = 'tel', moto_ok_em = NULL, atualizado_em = now() WHERE id = v.id;
    PERFORM nai_evento(v.id, 'motoboy_nao_pode', p_obs);
    PERFORM nai_avisar_tel(p_turno, v.id, 'Tel, o Fernando disse que NÃO consegue acompanhar a visita #' || v.id || ' (' ||
      nai_ref_imovel(v.codigo) || ', ' || nai_hora_exata(v.quando) || ')' || coalesce(': "' || left(p_obs, 300) || '"', '') ||
      E'.\nNão existe acompanhante reserva. Parei com o Fernando e com o corretor até você responder.\nMe responda VISITA ' || v.id || ' HORARIO <novo> ou VISITA ' || v.id || ' CANCELA.',
      'motoboy_nao_pode');
    PERFORM nai_parar_chat(t.contato_id, 'visita #' || v.id || ': Fernando nao pode');
    PERFORM nai_parar_chat(v.corretor_id, 'visita #' || v.id || ': Fernando nao pode');
    -- CALADA (Tel, 12/09): foi para o Tel, o corretor nao e avisado.
    RETURN QUERY SELECT NULL::text,
      'ja avisei o Tel. A pessoa NAO fica sabendo (regra do Tel, 12/09): responda exatamente SILENCIO.'::text; RETURN;
  END IF;

  PERFORM nai_avisar_tel(p_turno, v.id, 'Tel, o Fernando escreveu sobre a visita #' || v.id || ': "' ||
    left(coalesce(nullif(p_obs, ''), t.texto, ''), 300) || E'"\nParei de responder o Fernando até você mandar um VISITA ' || v.id || ' ...', 'motoboy_outro');
  PERFORM nai_parar_chat(t.contato_id, 'visita #' || v.id || ': mensagem do Fernando');
  RETURN QUERY SELECT NULL::text,
      'ja avisei o Tel. A pessoa NAO fica sabendo (regra do Tel, 12/09): responda exatamente SILENCIO.'::text;
END;
$$;

-- ------------------------------------------------------- comandos do Tel
-- VISITAS | VISITA <id> OK | VISITA <id> CANCELA [motivo]
-- VISITA <id> HORARIO <15h | 15:30 | 12/09 15h> | VISITA <id> AVISA <10h>
-- VISITA <id> FERNANDO OK | ACESSO <codigo> <chave com a gente | ...>
CREATE OR REPLACE FUNCTION nai_ler_hora_tel(p text, p_base timestamptz)
RETURNS timestamptz LANGUAGE plpgsql STABLE AS $$
DECLARE
  m  text[];
  d  date := (coalesce(p_base, now()) AT TIME ZONE 'America/Manaus')::date;
  h  int; mi int;
BEGIN
  m := regexp_match(p, '(\d{1,2})/(\d{1,2})');
  IF m IS NOT NULL THEN
    d := make_date(extract(year FROM now() AT TIME ZONE 'America/Manaus')::int, m[2]::int, m[1]::int);
  END IF;
  m := regexp_match(p, '(\d{1,2})\s*(?:h|:)\s*(\d{2})?(?!\d|/)');
  IF m IS NULL THEN RETURN NULL; END IF;
  h := m[1]::int; mi := coalesce(m[2], '0')::int;
  IF h > 23 OR mi > 59 THEN RETURN NULL; END IF;
  -- Sem data e a hora de hoje ja passou: e amanha. O Tel responde "VISITA 12
  -- AVISA 10h" as 23h querendo dizer amanha as 10h -- antes voltava "nao entendi".
  IF regexp_match(p, '(\d{1,2})/(\d{1,2})') IS NULL
     AND make_timestamptz(extract(year FROM d)::int, extract(month FROM d)::int, extract(day FROM d)::int, h, mi, 0, 'America/Manaus') <= now() THEN
    d := d + 1;
  END IF;
  RETURN make_timestamptz(extract(year FROM d)::int, extract(month FROM d)::int, extract(day FROM d)::int, h, mi, 0, 'America/Manaus');
EXCEPTION WHEN others THEN RETURN NULL;
END;
$$;

CREATE OR REPLACE FUNCTION nai_e_comando_tel(p text)
RETURNS boolean LANGUAGE sql IMMUTABLE AS $$
  SELECT coalesce(p, '') ~* '^\s*(@?nay[\s,:;.!-]*)?(visitas\s*$|visita\s+#?\d+\s+\S|acesso\s+\d{3,5}\s+\S|(assumir|devolver)\s+\S)';
$$;

CREATE OR REPLACE FUNCTION nai_comando_tel(p_turno bigint, p_texto text)
RETURNS TABLE(msg_tel text)
LANGUAGE plpgsql AS $$
DECLARE
  t     nai_turno;
  s     text := regexp_replace(btrim(coalesce(p_texto, '')), '^\s*@?nay[\s,:;.!-]*', '', 'i');
  m     text[];
  v     nai_visita;
  q     timestamptz;
  v_ac  text;
  linhas text;
  v_msg text;
  v_lib int := 0;
BEGIN
  SELECT * INTO t FROM nai_turno WHERE id = p_turno;
  IF t.id IS NULL OR t.papel <> 'tel' THEN
    RETURN QUERY SELECT 'comando so do Tel.'::text; RETURN;
  END IF;

  IF s ~* '^visitas\s*$' THEN
    SELECT string_agg('#' || x.id || ' · ' || nai_ref_imovel(x.codigo) || ' · ' || nai_hora_exata(x.quando) || ' · ' || x.estado ||
                      coalesce(' (esperando ' || x.aguardando || ')', ''), E'\n' ORDER BY x.quando)
      INTO linhas FROM nai_visita x WHERE nai_visita_aberta(x.estado);
    v_msg := coalesce(E'Visitas em andamento:\n' || linhas, 'Nenhuma visita em andamento.');
    PERFORM nai_enfileirar_texto(p_turno, NULL, t.contato_id, 'turno', v_msg, 'comando_tel', 1);
    RETURN QUERY SELECT v_msg; RETURN;
  END IF;

  -- ASSUMIR <telefone> / DEVOLVER <telefone>: o Tel pega ou devolve a conversa.
  m := regexp_match(s, '^(assumir|devolver)\s+(.+)$', 'i');
  IF m IS NOT NULL THEN
    IF nai_chave(m[2]) IS NULL THEN
      v_msg := 'Não entendi o telefone. Use: ASSUMIR 92 99999-8888  ou  DEVOLVER 92 99999-8888';
    ELSIF lower(m[1]) = 'assumir' THEN
      PERFORM nai_contato_do_cadastro(m[2], NULL);
      UPDATE nai_contato SET humano_assumiu_em = coalesce(humano_assumiu_em, now()), humano_motivo = 'comando ASSUMIR do Tel'
       WHERE chave = nai_chave(m[2]);
      v_msg := 'Feito: a conversa com ' || nai_fone_fmt(m[2]) || ' é sua. A NAI não manda mais nada para essa pessoa até você mandar DEVOLVER ' || btrim(m[2]) || '.';
    ELSE
      UPDATE nai_contato SET humano_assumiu_em = NULL, humano_motivo = NULL WHERE chave = nai_chave(m[2]);
      v_msg := 'Feito: a NAI volta a atender ' || nai_fone_fmt(m[2]) || '.';
    END IF;
    PERFORM nai_enfileirar_texto(p_turno, NULL, t.contato_id, 'turno', v_msg, 'comando_tel', 1);
    RETURN QUERY SELECT v_msg; RETURN;
  END IF;

  m := regexp_match(s, '^acesso\s+(\d{3,5})\s+(.+)$', 'i');
  IF m IS NOT NULL THEN
    v_ac := nai_acesso_normalizar(m[2]);
    IF v_ac IS NULL OR NOT EXISTS (SELECT 1 FROM imoveis WHERE codigo = m[1]::int) THEN
      v_msg := 'Não entendi. Use: ACESSO 5611 chave com a gente / buscar a chave na portaria / fechadura / proprietário abre';
    ELSE
      INSERT INTO nai_acesso_imovel (codigo, acesso, detalhe, fonte) VALUES (m[1]::int, v_ac, m[2], 'tel')
      ON CONFLICT (codigo) DO UPDATE SET acesso = EXCLUDED.acesso, detalhe = EXCLUDED.detalhe, fonte = 'tel', atualizado_em = now();
      v_msg := 'Guardei: no ' || nai_ref_imovel(m[1]::int) || ' o acesso é ' || v_ac || '.';
    END IF;
    PERFORM nai_enfileirar_texto(p_turno, NULL, t.contato_id, 'turno', v_msg, 'comando_tel', 1);
    RETURN QUERY SELECT v_msg; RETURN;
  END IF;

  m := regexp_match(s, '^visita\s+#?(\d+)\s+(.*)$', 'i');
  IF m IS NULL THEN RETURN QUERY SELECT NULL::text; RETURN; END IF;
  SELECT * INTO v FROM nai_visita WHERE id = m[1]::bigint FOR UPDATE;
  IF v.id IS NULL OR NOT nai_visita_aberta(v.estado) THEN
    v_msg := 'Não achei a visita #' || m[1] || ' em andamento. Mande VISITAS para ver a lista.';
    PERFORM nai_enfileirar_texto(p_turno, NULL, t.contato_id, 'turno', v_msg, 'comando_tel', 1);
    RETURN QUERY SELECT v_msg; RETURN;
  END IF;

  IF m[2] ~* '^(fernando|motoboy)\s+(ok|confirm)' THEN
    UPDATE nai_visita SET moto_ok_em = now() WHERE id = v.id RETURNING * INTO v;
    IF v.prop_ok_em IS NOT NULL THEN PERFORM nai_confirmar_visita(v.id, p_turno); END IF;
    v_msg := 'Feito: Fernando confirmado na visita #' || v.id || CASE WHEN v.prop_ok_em IS NOT NULL THEN '. Confirmei ao corretor.' ELSE '. Ainda falta o proprietário.' END;
  ELSIF m[2] ~* '^(ok|confirm|pode)' THEN
    UPDATE nai_visita SET prop_ok_em = now(), quando = coalesce(quando_sugerido, quando) WHERE id = v.id;
    PERFORM nai_evento(v.id, 'tel_confirmou_proprietario', NULL);
    IF (SELECT acesso FROM nai_visita WHERE id = v.id) IS NULL AND NOT EXISTS (SELECT 1 FROM nai_acesso_imovel WHERE codigo = v.codigo) THEN
      UPDATE nai_visita SET acesso_detalhe = 'combinado pelo Tel' WHERE id = v.id;
    END IF;
    -- Sem conversa com o proprietario (foi o Tel): segue direto para o Fernando.
    IF v.proprietario_id IS NULL OR v.estado = 'com_tel' THEN
      UPDATE nai_visita SET acesso = coalesce(acesso, (SELECT acesso FROM nai_acesso_imovel WHERE codigo = v.codigo)) WHERE id = v.id;
      UPDATE nai_visita SET estado = 'aguardando_acesso' WHERE id = v.id AND acesso IS NULL;
      IF (SELECT acesso FROM nai_visita WHERE id = v.id) IS NULL THEN
        v_msg := 'Anotado o OK do proprietário na visita #' || v.id || '. Como é o acesso? Responda: ACESSO ' || v.codigo || ' chave com a gente / buscar a chave / fechadura / proprietário abre — e depois VISITA ' || v.id || ' OK de novo.';
        PERFORM nai_enfileirar_texto(p_turno, NULL, t.contato_id, 'turno', v_msg, 'comando_tel', 1);
        RETURN QUERY SELECT v_msg; RETURN;
      END IF;
      UPDATE nai_visita SET senha = coalesce(senha, 'com o Tel') WHERE id = v.id AND acesso = 'fechadura';
      UPDATE nai_visita SET acesso_detalhe = coalesce(acesso_detalhe, 'combinado pelo Tel') WHERE id = v.id AND acesso = 'buscar_chave';
    END IF;
    PERFORM nai_prosseguir_acesso(v.id, p_turno, false);
    v_msg := 'Feito: visita #' || v.id || ' com o OK do proprietário. Estou chamando o Fernando.';
  ELSIF m[2] ~* '^cancel' THEN
    UPDATE nai_visita SET estado = 'cancelada', aguardando = NULL, motivo = 'Tel: ' || m[2], senha = NULL,
                          encerrada_em = now(), atualizado_em = now() WHERE id = v.id;
    PERFORM nai_evento(v.id, 'cancelada_pelo_tel', m[2]);
    PERFORM nai_enfileirar_texto(p_turno, v.id, v.corretor_id, 'corretor',
      coalesce(nai_vocativo((SELECT coalesce(nome_completo, nome_whatsapp) FROM nai_contato WHERE id = v.corretor_id)) || ', ', '') ||
      'a visita de ' || nai_quando_humano(v.quando) || ' no ' || nai_ref_imovel(v.codigo) ||
      ' não vai dar certo. Quer que eu veja outro horário?', 'cancelada_pelo_tel', 400);
    IF v.motoboy_id IS NOT NULL AND (v.moto_ok_em IS NOT NULL OR v.ult_msg_moto_em IS NOT NULL) THEN
      PERFORM nai_enfileirar_texto(p_turno, v.id, v.motoboy_id, 'motoboy',
        'Fernando, a visita do ' || nai_ref_imovel(v.codigo) || ' de ' || nai_hora_exata(v.quando) || ' foi cancelada.', 'cancelada', 600);
    END IF;
    v_msg := 'Feito: visita #' || v.id || ' cancelada e o corretor avisado.';
  ELSIF m[2] ~* '^hor' THEN
    q := nai_ler_hora_tel(m[2], v.quando);
    IF q IS NULL OR q <= now() THEN
      v_msg := 'Não entendi o horário. Use: VISITA ' || v.id || ' HORARIO 16h  ou  VISITA ' || v.id || ' HORARIO 13/09 16h';
    ELSE
      UPDATE nai_visita SET quando_sugerido = q, estado = 'negociando', aguardando = 'corretor', atualizado_em = now() WHERE id = v.id;
      PERFORM nai_evento(v.id, 'tel_sugeriu_horario', nai_hora_exata(q));
      -- Mesmo card p_repassa do caminho do proprietario: com o tratamento
      -- ("Sr. Pedro, o proprietario nao consegue..."). No teste ao vivo de 13/09
      -- saia sem tratamento e com letra minuscula quando quem mandava era o Tel.
      PERFORM nai_enfileirar_texto(p_turno, v.id, v.corretor_id, 'corretor',
        coalesce(nai_vocativo((SELECT coalesce(nome_completo, nome_whatsapp) FROM nai_contato WHERE id = v.corretor_id)) || ', ', '') ||
        'o proprietário não consegue ' || nai_quando_humano(v.quando) || ', mas sugeriu ' || nai_quando_humano(q) || '. Funciona pro seu cliente?',
        'tel_sugeriu', 400);
      v_msg := 'Feito: perguntei ao corretor se ' || nai_hora_exata(q) || ' serve.';
    END IF;
  ELSIF m[2] ~* '^avis' THEN
    q := nai_ler_hora_tel(m[2], now());
    IF q IS NULL OR q <= now() THEN
      v_msg := 'Não entendi a hora. Use: VISITA ' || v.id || ' AVISA 10h';
    ELSE
      UPDATE nai_visita SET proximo_aviso_prop_em = q WHERE id = v.id;
      -- Card "Acionar o Tel" (2h antes): a resposta dele devolve a visita ao proprietario.
      UPDATE nai_visita SET estado = 'aguardando_proprietario', aguardando = 'proprietario', atualizado_em = now()
       WHERE id = v.id AND estado = 'com_tel' AND proprietario_id IS NOT NULL AND prop_ok_em IS NULL;
      v_msg := 'Combinado: mando o próximo aviso ao proprietário ' || nai_hora_exata(q) || '. Se ele não responder em ' ||
               nai_cfg_int('reenvio_proprietario_min', 30) || ' minutos, te aviso para ligar.';
    END IF;
  ELSE
    v_msg := 'Comandos: VISITAS · VISITA ' || v.id || ' OK · VISITA ' || v.id || ' CANCELA · VISITA ' || v.id ||
             ' HORARIO 16h · VISITA ' || v.id || ' AVISA 10h · VISITA ' || v.id || ' FERNANDO OK · ACESSO <código> <como> · ASSUMIR <telefone> · DEVOLVER <telefone>';
  END IF;
  -- Quando o fluxo para, a Nay para os chats (13/09); o comando do Tel sobre a
  -- visita e o "pode seguir": volta a atender quem estava parado por ELA.
  IF v_msg NOT LIKE 'Comandos:%' AND v_msg NOT LIKE 'Não entendi%' THEN
    v_lib := nai_liberar_chats_da_visita(v.id);
    IF v_lib > 0 THEN v_msg := v_msg || ' Voltei a atender quem estava parado por essa visita.'; END IF;
  END IF;
  PERFORM nai_enfileirar_texto(p_turno, NULL, t.contato_id, 'turno', v_msg, 'comando_tel', 1);
  RETURN QUERY SELECT v_msg;
END;
$$;

-- "O Fernando, da nossa equipe, acompanha a visita. O visitante e X, CPF Y,
-- com o corretor Z." -- a parte do card c_prop que vai ao proprietario.
CREATE OR REPLACE FUNCTION nai_frase_visitante(v nai_visita)
RETURNS text LANGUAGE sql STABLE AS $$
  SELECT 'O Fernando, da nossa equipe, acompanha a visita. O visitante é ' || coalesce(v.visitante_nome, 'o cliente do corretor') ||
         coalesce(', CPF ' || nai_cpf_fmt(v.visitante_cpf), '') ||
         coalesce(', com o corretor ' || coalesce(c.nome_completo, nay_nome_de_pessoa(c.nome_whatsapp)), '') || '.'
    FROM nai_contato c WHERE c.id = v.corretor_id;
$$;

-- Os dados do visitante, que vao ao proprietario DEPOIS da visita confirmada
-- (fluxo v17): "O visitante e {nome}, CPF {cpf}, com o corretor {corretor}."
CREATE OR REPLACE FUNCTION nai_texto_dados_visitante(v nai_visita)
RETURNS text LANGUAGE sql STABLE AS $$
  SELECT 'O visitante é ' || coalesce(v.visitante_nome, 'o cliente do corretor') ||
         coalesce(', CPF ' || nai_cpf_fmt(v.visitante_cpf), '') ||
         coalesce(', com o corretor ' || coalesce(c.nome_completo, nay_nome_de_pessoa(c.nome_whatsapp)), '') || '.'
    FROM nai_contato c WHERE c.id = v.corretor_id;
$$;

-- O que a NAI diz ao Fernando quando ele confirma (card novo_8: agenda e
-- avisa o acesso). Cada ramo e um card do fluxo: pv_chave, pv_senha,
-- novo_9 (proprietario acompanha: contato dele) e novo_10 (chave conosco).
CREATE OR REPLACE FUNCTION nai_texto_motoboy_ok(v nai_visita)
RETURNS text LANGUAGE sql STABLE AS $$
  SELECT 'Fechado, Fernando, agendei aqui: ' || nai_ref_imovel(v.codigo) || ', ' || nai_hora_exata(v.quando) || '. ' ||
    CASE v.acesso
      WHEN 'chave_conosco' THEN 'A chave está com a gente: separa ela pra visita, por favor.'
      WHEN 'buscar_chave' THEN 'A chave fica com o proprietário' || coalesce(' (' || v.acesso_detalhe || ')', '') ||
                               ': pega antes da visita e devolve depois, tá?'
      WHEN 'fechadura' THEN 'É fechadura eletrônica: te mando a senha ' || nai_cfg_int('aviso_motoboy_min', 30) || ' minutos antes.'
      WHEN 'proprietario_acompanha' THEN 'Quem abre é o proprietário' || coalesce(', ' || nai_vocativo(v.proprietario_nome), '') ||
           coalesce(' (' || nai_fone_fmt((SELECT telefone FROM nai_contato WHERE id = v.proprietario_id)) || ')', '') ||
           ': combina com ele de se encontrarem lá no horário.'
      ELSE 'O acesso eu confirmo com o Tel e te aviso.' END;
$$;

-- ------------------------------------------------------ o Tel assumiu
-- Chamada pelo fluxo quando chega mensagem que SAIU do numero da Nay sem ter
-- sido mandada pela API (fromMe e nao fromApi): o Tel digitou no celular.
-- CHECK DUPLO contra o eco: se o ID ou o texto batem com algo que a propria
-- NAI/Nay mandou, e mensagem nossa e nada muda.
CREATE OR REPLACE FUNCTION nai_tel_assumiu(p_tel text, p_message_id text, p_texto text)
RETURNS jsonb LANGUAGE plpgsql AS $$
DECLARE v_chave text := nai_chave(p_tel); v_eco boolean;
BEGIN
  IF v_chave IS NULL OR v_chave = nai_chave(nai_cfg('tel_telefone')) THEN
    RETURN jsonb_build_object('ok', false, 'motivo', 'sem_contato_ou_e_o_tel');
  END IF;
  v_eco := (nullif(p_message_id, '') IS NOT NULL AND (
              EXISTS (SELECT 1 FROM nai_saida s WHERE s.message_id = p_message_id)
           OR EXISTS (SELECT 1 FROM mensagem_saida m WHERE m.message_id = p_message_id)))
        OR EXISTS (SELECT 1 FROM nai_saida s
                    WHERE s.chave_destino = v_chave AND s.estado IN ('enviado', 'enviando')
                      AND s.criado_em > now() - interval '15 minutes'
                      AND nullif(btrim(coalesce(p_texto, '')), '') IS NOT NULL
                      AND (btrim(s.texto) = btrim(p_texto) OR btrim(s.resposta->>'texto_final') = btrim(p_texto)
                           OR position(btrim(p_texto) IN coalesce(s.texto, '')) > 0));
  IF v_eco THEN RETURN jsonb_build_object('ok', true, 'eco_nosso', true); END IF;
  PERFORM nai_contato_do_cadastro(p_tel, NULL);
  UPDATE nai_contato SET humano_assumiu_em = coalesce(humano_assumiu_em, now()),
                         humano_motivo = coalesce(humano_motivo, 'o Tel escreveu pelo celular')
   WHERE chave = v_chave;
  RETURN jsonb_build_object('ok', true, 'tel_assumiu', true);
END;
$$;
