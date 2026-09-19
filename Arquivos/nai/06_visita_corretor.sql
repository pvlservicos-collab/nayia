-- =====================================================================
-- NAI atendimento locacao -- 06: a visita pelo lado do CORRETOR
--
-- Ferramentas do agente. Todas recebem o TURNO (vem do fluxo, o modelo nao
-- escolhe) e dele tiram quem e o corretor. O modelo so passa codigo,
-- horario e os dados que o corretor escreveu.
-- =====================================================================

-- A visita aberta deste corretor: pelo codigo, ou a unica no estado pedido.
CREATE OR REPLACE FUNCTION nai_visita_do_corretor(p_contato bigint, p_codigo text, p_estados text[])
RETURNS TABLE(visita_id bigint, qtd int)
LANGUAGE plpgsql STABLE AS $$
DECLARE v_cod int := NULLIF(regexp_replace(coalesce(p_codigo, ''), '\D', '', 'g'), '')::int;
BEGIN
  IF v_cod IS NOT NULL THEN
    RETURN QUERY SELECT x.id, 1 FROM nai_visita x
                  WHERE x.corretor_id = p_contato AND x.codigo = v_cod AND nai_visita_aberta(x.estado)
                    AND (p_estados IS NULL OR x.estado = ANY (p_estados))
                  ORDER BY x.id DESC LIMIT 1;
    RETURN;
  END IF;
  RETURN QUERY SELECT min(x.id), count(*)::int FROM nai_visita x
                WHERE x.corretor_id = p_contato AND nai_visita_aberta(x.estado)
                  AND (p_estados IS NULL OR x.estado = ANY (p_estados))
               HAVING count(*) > 0;
END;
$$;

CREATE OR REPLACE FUNCTION nai_lista_visitas_corretor(p_contato bigint)
RETURNS text LANGUAGE sql STABLE AS $$
  SELECT string_agg('• ' || nai_ref_imovel(x.codigo) || ' — ' || coalesce(nai_quando_humano(x.quando), 'sem horário'), E'\n' ORDER BY x.id)
    FROM nai_visita x WHERE x.corretor_id = p_contato AND nai_visita_aberta(x.estado);
$$;

-- --------------------------------------------------------- pedir visita
CREATE OR REPLACE FUNCTION nai_pedir_visita(p_turno bigint, p_codigo text, p_quando text, p_qualificado text)
RETURNS TABLE(texto_pronto text, instrucao_para_voce text)
LANGUAGE plpgsql AS $$
DECLARE
  t        nai_turno;
  k        nai_contato;
  i        imoveis;
  v_cod    int := NULLIF(regexp_replace(coalesce(p_codigo, ''), '\D', '', 'g'), '')::int;
  v_q      timestamptz := nai_ler_quando(p_quando);
  v_conf   text;
  v_v      nai_visita;
  v_id     bigint;
  v_dono   record;
  v_moto   record;
  v_urg    boolean;
  d        record;
  v_min_h  int := nai_cfg_int('antecedencia_minima_horas', 2);
BEGIN
  PERFORM nai_usou_ferramenta(p_turno, 'visita');
  SELECT * INTO t FROM nai_turno WHERE id = p_turno;
  IF t.id IS NULL OR t.papel <> 'corretor' THEN
    RETURN QUERY SELECT NULL::text, 'pedir_visita e so para o corretor. nao chame de novo neste turno.'::text; RETURN;
  END IF;
  SELECT * INTO k FROM nai_contato WHERE id = t.contato_id;

  IF v_cod IS NULL THEN
    RETURN QUERY SELECT NULL::text, 'voce ainda nao sabe QUAL imovel. pergunte ao corretor (ou mostre a lista com imovel_do_disparo) antes de chamar pedir_visita.'::text; RETURN;
  END IF;

  -- O codigo NAO pode vir da cabeca do modelo: ele escreveu, ou foi o unico
  -- card que mandamos para ele, ou ja existe visita aberta desse imovel.
  v_conf := nay_codigo_confirmado(k.telefone, v_cod::text, 72);
  IF v_conf = 'nao' AND NOT EXISTS (SELECT 1 FROM nai_visita x WHERE x.corretor_id = k.id AND x.codigo = v_cod AND nai_visita_aberta(x.estado)) THEN
    RETURN QUERY SELECT NULL::text,
      ('o codigo ' || v_cod || ' nao foi dito por ele nesta conversa. NAO suponha: pergunte de qual imovel ele fala, confirmando o nome ou o codigo, e so depois chame pedir_visita.')::text;
    RETURN;
  END IF;

  SELECT * INTO i FROM imoveis WHERE codigo = v_cod;
  IF i.codigo IS NULL THEN
    RETURN QUERY SELECT ('Não achei nenhum imóvel com o código ' || v_cod || '. Confere pra mim?')::text, NULL::text; RETURN;
  END IF;
  IF coalesce(i.e_parceiro, false) THEN
    RETURN QUERY SELECT NULL::text, 'esse imovel e de PARCERIA, a visita nao e com a gente: chame escalar_ao_tel com o pedido de visita e diga o texto_pronto que vier.'::text; RETURN;
  END IF;
  IF NOT nay_esta_no_mercado(i.disponivel, i.bloqueado, i.publicado_no_site) THEN
    RETURN QUERY SELECT ('Esse imóvel saiu do mercado' || coalesce(', ' || nai_vocativo(coalesce(k.nome_completo, k.nome_whatsapp)), '') || '. Quer que eu veja outro parecido pro seu cliente?')::text, NULL::text; RETURN;
  END IF;
  IF coalesce(i.valor_aluguel, 0) <= 0 THEN
    RETURN QUERY SELECT NULL::text, 'esse imovel e so de VENDA: a visita de venda segue pelo Tel. chame escalar_ao_tel com o pedido de visita (codigo e horario) e diga o texto_pronto que vier.'::text; RETURN;
  END IF;

  IF v_q IS NULL THEN
    RETURN QUERY SELECT 'Claro! Me informa o dia e o horário que fica bom pro seu cliente, ok?'::text,
      'ele nao disse dia e hora (ou nao deu para entender). quando ele disser, chame pedir_visita de novo com o horario no formato AAAA-MM-DD HH:MM.'::text;
    RETURN;
  END IF;
  -- v_regra: ja passou
  IF v_q <= now() + interval '10 minutes' THEN
    RETURN QUERY SELECT 'Esse horário já passou. Qual outro horário fica bom pro seu cliente?'::text,
      'quando ele disser outro horario, chame pedir_visita de novo.'::text;
    RETURN;
  END IF;
  IF v_q > now() + interval '45 days' THEN
    RETURN QUERY SELECT NULL::text, 'o horario ficou para daqui a mais de 45 dias: confirme a data com ele antes de chamar de novo.'::text; RETURN;
  END IF;

  -- SEM pergunta de renda (Tel, 12/09): isso vinha da regra 2 da tabela
  -- `regras` (14/08, da Nay antiga) e NAO existe em card nenhum do fluxo do
  -- site. O fluxo e a lista completa do que ela faz com o corretor. O
  -- parametro p_qualificado continua sendo aceito (para nao quebrar chamada
  -- antiga), mas nao segura mais nada.

  -- Ja existe visita aberta deste imovel com este corretor?
  SELECT * INTO v_v FROM nai_visita x WHERE x.corretor_id = k.id AND x.codigo = v_cod AND nai_visita_aberta(x.estado);
  IF v_v.id IS NOT NULL THEN
    RETURN QUERY SELECT NULL::text,
      ('ja existe visita em andamento desse imovel com ele (' || nai_status_humano(v_v) || ', ' ||
       coalesce(nai_quando_humano(v_v.quando), 'sem horario') || '). se ele quer OUTRO horario, chame mudar_horario_da_visita; se mandou nome/CPF, chame guardar_dados_da_visita; nao chame pedir_visita.')::text;
    RETURN;
  END IF;

  v_urg := v_q < now() + make_interval(hours => v_min_h);
  SELECT * INTO v_dono FROM nai_proprietario_do_imovel(v_cod);
  SELECT * INTO v_moto FROM nai_motoboy();

  INSERT INTO nai_visita (codigo, corretor_id, quando, estado, aguardando, urgente, qualificado,
                          proprietario_cadastro, proprietario_nome, motoboy_id, proximo_lembrete_dados_em)
       VALUES (v_cod, k.id, v_q, 'coletando', 'corretor', v_urg, NULL,
               v_dono.cadastro_id, v_dono.nome, v_moto.contato_id, NULL)
  RETURNING id INTO v_id;
  PERFORM nai_evento(v_id, 'pedida', 'horario ' || nai_hora_exata(v_q));

  -- VISITA URGENTE (Tel, 12/09): menos de 3 horas nao passa pela IA. Sobe
  -- para o Tel e a Nay PARA -- e desde 13/09 para o chat inteiro do corretor.
  IF v_urg THEN
    UPDATE nai_visita SET estado = 'com_tel', aguardando = 'tel', urgente = true,
                          proximo_lembrete_dados_em = NULL, atualizado_em = now()
     WHERE id = v_id;
    PERFORM nai_evento(v_id, 'urgente_com_tel', nai_hora_exata(v_q));
    PERFORM nai_avisar_tel(p_turno, v_id,
      'Tel, VISITA URGENTE (menos de ' || v_min_h || 'h): ' || nai_ref_imovel(v_cod) || ', ' || nai_hora_exata(v_q) ||
      E'.\nCorretor: ' || coalesce(k.nome_completo, k.nome_whatsapp, '') || ' ' || nai_fone_fmt(k.telefone) ||
      E'\nEu parei aqui: não falei com o proprietário nem com o Fernando, e parei de responder esse corretor. A visita #' || v_id || ' é sua.' ||
      E'\nSe quiser que eu siga, responda VISITA ' || v_id || ' OK.', 'urgente');
    PERFORM nai_parar_chat(k.id, 'visita #' || v_id || ': urgente (menos de ' || v_min_h || 'h)');
    RETURN QUERY SELECT NULL::text,
      'visita URGENTE: foi para o Tel e voce PAROU neste chat. responda exatamente SILENCIO.'::text;
    RETURN;
  END IF;

  -- FLUXO v17 (Tel, 13/09): o horario vai DIRETO ao proprietario. Os dados do
  -- corretor e do visitante so sao pedidos depois da "Visita confirmada", e
  -- nesta hora o corretor nao recebe nada ("Nada, fica calada").
  PERFORM nai_pedir_ao_proprietario(v_id, p_turno);
  RETURN QUERY SELECT NULL::text,
    'o pedido foi ao proprietario (ou ao Tel). o corretor NAO recebe nada agora: responda exatamente SILENCIO. NAO peca dados e NAO diga que a visita esta confirmada.'::text;
END;
$$;

-- ----------------------------------------------- pedir ao proprietario
-- Chamada logo que o corretor pede o horario (fluxo v17). Enfileira o pedido (p_solicita)
-- ou, sem como falar com o proprietario, passa ao Tel.
CREATE OR REPLACE FUNCTION nai_pedir_ao_proprietario(p_visita bigint, p_turno bigint)
RETURNS text LANGUAGE plpgsql AS $$
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
      E'\nParei de responder esse corretor até você responder.\nQuando resolver, me responda:\nVISITA ' || v.id || ' OK  (proprietário confirmou)\nVISITA ' || v.id ||
      E' HORARIO 16h  (ele pediu outro horário)\nVISITA ' || v.id || ' CANCELA',
      'sem_proprietario');
    PERFORM nai_parar_chat(v.corretor_id, 'visita #' || v.id || ': sem contato do proprietario');
    RETURN 'com_tel';
  END IF;

  v_voc := nai_vocativo(dono.nome);
  -- Card p_solicita, humanizado como o Tel pediu ("hoje a tarde", sem data numerica).
  v_texto := nai_saudacao() || coalesce(', ' || v_voc, '') || '! Tudo bem? Aqui é a Nay, da Imob Easy. ' ||
             'Temos um pedido de visita ' || nai_ref_imovel_prop(v.codigo) ||
             ' para ' || nai_quando_humano(v.quando) || '. Tem como receber a visita nesse horário?';

  UPDATE nai_visita SET proprietario_id = v_prop, proprietario_cadastro = dono.cadastro_id,
                        proprietario_nome = dono.nome, estado = 'aguardando_proprietario', aguardando = 'proprietario',
                        ult_msg_prop_em = now(), reenvios_prop = 0, atualizado_em = now()
   WHERE id = v.id;
  PERFORM nai_enfileirar_texto(p_turno, v.id, v_prop, 'proprietario', v_texto, 'p_solicita', 500);
  RETURN 'pedido';
END;
$$;

-- --------------------------------------------------- dados da visita
CREATE OR REPLACE FUNCTION nai_guardar_dados_visita(
  p_turno bigint, p_codigo text, p_visitante_nome text, p_visitante_cpf text,
  p_corretor_nome text, p_corretor_cpf text, p_corretor_creci text)
RETURNS TABLE(texto_pronto text, instrucao_para_voce text)
LANGUAGE plpgsql AS $$
DECLARE
  t       nai_turno;
  k       nai_contato;
  sel     record;
  v       nai_visita;
  d       record;
  v_vcpf  text := nai_cpf_valido(p_visitante_cpf);
  v_ccpf  text := nai_cpf_valido(p_corretor_cpf);
  v_vnome text := nai_nome_completo(p_visitante_nome);
  v_cnome text := nai_nome_completo(p_corretor_nome);
  v_creci text := NULLIF(btrim(coalesce(p_corretor_creci, '')), '');
  v_falta text[] := '{}';
  v_erro  text[] := '{}';
  v_res   text;
BEGIN
  PERFORM nai_usou_ferramenta(p_turno, 'visita');
  SELECT * INTO t FROM nai_turno WHERE id = p_turno;
  IF t.id IS NULL OR t.papel <> 'corretor' THEN
    RETURN QUERY SELECT NULL::text, 'so o corretor passa os dados da visita.'::text; RETURN;
  END IF;
  SELECT * INTO k FROM nai_contato WHERE id = t.contato_id;
  SELECT * INTO sel FROM nai_visita_do_corretor(k.id, p_codigo, ARRAY['confirmada']);
  IF sel.visita_id IS NULL THEN
    RETURN QUERY SELECT NULL::text, 'nao ha visita confirmada esperando dados. se ele quer marcar uma visita, chame pedir_visita.'::text; RETURN;
  END IF;
  IF sel.qtd > 1 THEN
    RETURN QUERY SELECT ('Esses dados são pra qual visita?' || E'\n' || nai_lista_visitas_corretor(k.id))::text,
      'pergunte de qual imovel sao os dados e chame de novo com o codigo.'::text; RETURN;
  END IF;
  SELECT * INTO v FROM nai_visita WHERE id = sel.visita_id FOR UPDATE;

  -- Os do CORRETOR (se veio). Grava no cadastro antigo quando ele existe,
  -- como a ferramenta antiga fazia, e sempre no contato da NAI.
  IF p_corretor_cpf IS NOT NULL AND btrim(p_corretor_cpf) <> '' AND v_ccpf IS NULL THEN
    v_erro := v_erro || 'o seu CPF não confere (confere os 11 números?)'::text;
  END IF;
  IF v_ccpf IS NOT NULL OR v_cnome IS NOT NULL OR (v_creci IS NOT NULL AND length(v_creci) BETWEEN 3 AND 30) THEN
    UPDATE nai_contato SET cpf = coalesce(v_ccpf, cpf), nome_completo = coalesce(v_cnome, nome_completo),
                           creci = coalesce(CASE WHEN length(v_creci) BETWEEN 3 AND 30 THEN v_creci END, creci),
                           atualizado_em = now()
     WHERE id = k.id;
    IF k.chave !~ '^lid:' THEN
      UPDATE corretores c SET nome = coalesce(v_cnome, c.nome),
                              nome_origem = CASE WHEN v_cnome IS NOT NULL THEN 'manual' ELSE c.nome_origem END,
                              creci = coalesce(NULLIF(btrim(c.creci), ''), CASE WHEN length(v_creci) BETWEEN 3 AND 30 THEN v_creci END),
                              ultima_interacao = now()
       WHERE nai_chave(c.telefone) = k.chave;
    END IF;
  END IF;

  -- Os do VISITANTE.
  IF p_visitante_cpf IS NOT NULL AND btrim(p_visitante_cpf) <> '' AND v_vcpf IS NULL THEN
    v_erro := v_erro || 'o CPF do visitante não confere (confere os 11 números?)'::text;
  END IF;
  IF p_visitante_nome IS NOT NULL AND btrim(p_visitante_nome) <> '' AND v_vnome IS NULL THEN
    v_erro := v_erro || 'preciso do nome COMPLETO do visitante (nome e sobrenome)'::text;
  END IF;
  UPDATE nai_visita SET visitante_nome = coalesce(v_vnome, visitante_nome),
                        visitante_cpf = coalesce(v_vcpf, visitante_cpf), atualizado_em = now()
   WHERE id = v.id RETURNING * INTO v;

  SELECT * INTO d FROM nai_dados_corretor(k.id);
  IF d.nome_completo IS NULL THEN v_falta := v_falta || 'seu nome completo'::text; END IF;
  IF d.cpf IS NULL THEN v_falta := v_falta || 'seu CPF'::text; END IF;
  IF d.creci IS NULL THEN v_falta := v_falta || 'seu CRECI'::text; END IF;
  IF v.visitante_nome IS NULL THEN v_falta := v_falta || 'o nome completo do visitante'::text; END IF;
  IF v.visitante_cpf IS NULL THEN v_falta := v_falta || 'o CPF do visitante'::text; END IF;

  IF array_length(v_falta, 1) >= 1 OR array_length(v_erro, 1) >= 1 THEN
    UPDATE nai_visita SET proximo_lembrete_dados_em =
             now() + make_interval(mins => nai_cfg_int('dados_primeiro_lembrete_min', 3))
     WHERE id = v.id;
    RETURN QUERY SELECT
      (CASE WHEN array_length(v_erro, 1) >= 1 THEN initcap(left(array_to_string(v_erro, '. '), 1)) || substr(array_to_string(v_erro, '. '), 2) || '. ' ELSE '' END ||
       CASE WHEN coalesce(array_length(v_erro, 1), 0) = 0 AND d.completo AND v.visitante_nome IS NULL AND v.visitante_cpf IS NULL
            THEN 'Anotado! Agora pode passar o nome completo e o CPF do visitante?'
            WHEN array_length(v_falta, 1) >= 1
            THEN 'Só falta ' || nai_lista_pt(v_falta) || ' pra eu fechar a visita' ELSE '' END)::text,
      'quando ele mandar, chame guardar_dados_da_visita de novo.'::text;
    RETURN;
  END IF;

  -- Tudo certo (fluxo v17, Tel 13/09): a visita JA esta confirmada. Os dados
  -- do visitante vao ao proprietario agora ("coloca para mandar depois") e o
  -- corretor nao recebe nada ("Nada, fica calada").
  UPDATE nai_visita SET proximo_lembrete_dados_em = NULL WHERE id = v.id;
  IF NOT EXISTS (SELECT 1 FROM nai_visita_evento e WHERE e.visita_id = v.id AND e.tipo = 'dados_ao_proprietario') THEN
    PERFORM nai_evento(v.id, 'dados_completos', NULL);
    IF v.proprietario_id IS NOT NULL THEN
      PERFORM nai_enfileirar_texto(p_turno, v.id, v.proprietario_id, 'proprietario', nai_texto_dados_visitante(v), 'dados_visitante', 500);
    ELSE
      PERFORM nai_avisar_tel(p_turno, v.id, 'Tel, dados do visitante da visita #' || v.id || ' (' || nai_ref_imovel(v.codigo) || ', ' ||
        nai_hora_exata(v.quando) || '): ' || nai_texto_dados_visitante(v), 'dados_visitante');
    END IF;
    PERFORM nai_evento(v.id, 'dados_ao_proprietario', NULL);
  END IF;
  RETURN QUERY SELECT NULL::text,
    'dados completos e repassados. o corretor NAO recebe nada: responda exatamente SILENCIO.'::text;
END;
$$;

-- -------------------- o proprietario sugeriu outro horario: o corretor responde
CREATE OR REPLACE FUNCTION nai_responder_horario(p_turno bigint, p_codigo text, p_aceita text, p_outro_quando text)
RETURNS TABLE(texto_pronto text, instrucao_para_voce text)
LANGUAGE plpgsql AS $$
DECLARE
  t   nai_turno;
  sel record;
  v   nai_visita;
  q   timestamptz := nai_ler_quando(p_outro_quando);
  ok  boolean := lower(coalesce(p_aceita, '')) IN ('sim', 's', 'true', 'yes', 'aceita');
  v_txt text;
BEGIN
  PERFORM nai_usou_ferramenta(p_turno, 'visita');
  SELECT * INTO t FROM nai_turno WHERE id = p_turno;
  IF t.id IS NULL OR t.papel <> 'corretor' THEN RETURN QUERY SELECT NULL::text, 'so o corretor responde isso.'::text; RETURN; END IF;
  SELECT * INTO sel FROM nai_visita_do_corretor(t.contato_id, p_codigo, ARRAY['negociando']);
  IF sel.visita_id IS NULL OR sel.qtd > 1 THEN
    RETURN QUERY SELECT NULL::text, 'nao achei UMA visita esperando a resposta dele sobre horario. chame minhas_visitas e pergunte qual.'::text; RETURN;
  END IF;
  SELECT * INTO v FROM nai_visita WHERE id = sel.visita_id FOR UPDATE;
  IF v.aguardando <> 'corretor' OR v.quando_sugerido IS NULL THEN
    RETURN QUERY SELECT NULL::text, 'essa visita nao esta esperando resposta dele: o proprietario ainda nao sugeriu horario.'::text; RETURN;
  END IF;

  IF ok THEN
    -- O horario foi o proprietario que deu: vale como aceite dele.
    UPDATE nai_visita SET quando = quando_sugerido, quando_sugerido = NULL, prop_ok_em = now(),
                          atualizado_em = now()
     WHERE id = v.id;
    PERFORM nai_evento(v.id, 'corretor_aceitou_horario_do_proprietario', NULL);
    -- Card "Fecha o novo horario": "Fechado! O corretor confirmou ... Obrigada 😊"
    v_txt := nai_prosseguir_acesso(v.id, p_turno, true);
    SELECT * INTO v FROM nai_visita WHERE id = v.id;
    -- Card p_ok, literal (sem dados do visitante: eles so vem depois da confirmacao).
    v_txt := 'Fechado! O corretor confirmou ' || nai_quando_humano(v.quando) || '. ' ||
             CASE WHEN v.estado = 'aguardando_acesso' THEN regexp_replace(coalesce(v_txt, ''), '^Obrigada!\s*', '')
                  ELSE 'Obrigada 😊' END;
    PERFORM nai_enfileirar_texto(p_turno, v.id, v.proprietario_id, 'proprietario', v_txt, 'fecha_novo_horario', 500);
    -- Nao ha card para o corretor aqui (fluxo v17): ele so ouve de novo na confirmacao.
    RETURN QUERY SELECT NULL::text,
      'o horario foi fechado com o proprietario. responda exatamente SILENCIO: a confirmacao chega sozinha.'::text;
    RETURN;
  END IF;

  IF q IS NULL THEN
    RETURN QUERY SELECT 'Sem problemas! Qual horário fica bom pro seu cliente?'::text,
      'quando ele disser, chame responder_horario_do_proprietario de novo com outro_quando.'::text; RETURN;
  END IF;
  IF q <= now() + interval '10 minutes' THEN
    RETURN QUERY SELECT 'Esse horário já passou. Qual outro horário fica bom pro seu cliente?'::text, NULL::text; RETURN;
  END IF;

  -- Loop: leva a contraproposta ao proprietario.
  UPDATE nai_visita SET quando = q, quando_sugerido = NULL, prop_ok_em = NULL, estado = 'negociando',
                        aguardando = 'proprietario', reenvios_prop = 0, aviso_demora_em = NULL, atualizado_em = now()
   WHERE id = v.id;
  -- Card "Leva a contraproposta": "O cliente nao consegue as X. Pode ser as Y?"
  PERFORM nai_enfileirar_texto(p_turno, v.id, v.proprietario_id, 'proprietario',
    'O cliente não consegue ' || nai_quando_humano(v.quando_sugerido) || '. Pode ser ' || nai_quando_humano(q) || '?',
    'contraproposta_corretor', 500);
  RETURN QUERY SELECT 'Certo, vou ver esse horário com o proprietário e já te retorno'::text, NULL::text;
END;
$$;

-- -------------------------------------------------- mudar horario
CREATE OR REPLACE FUNCTION nai_mudar_horario(p_turno bigint, p_codigo text, p_quando text)
RETURNS TABLE(texto_pronto text, instrucao_para_voce text)
LANGUAGE plpgsql AS $$
DECLARE
  t   nai_turno;
  k   nai_contato;
  sel record;
  v   nai_visita;
  q   timestamptz := nai_ler_quando(p_quando);
  v_antes text;
BEGIN
  PERFORM nai_usou_ferramenta(p_turno, 'visita');
  SELECT * INTO t FROM nai_turno WHERE id = p_turno;
  IF t.id IS NULL OR t.papel <> 'corretor' THEN RETURN QUERY SELECT NULL::text, 'so o corretor muda o horario da visita dele.'::text; RETURN; END IF;
  SELECT * INTO k FROM nai_contato WHERE id = t.contato_id;
  SELECT * INTO sel FROM nai_visita_do_corretor(k.id, p_codigo, NULL);
  IF sel.visita_id IS NULL THEN
    RETURN QUERY SELECT NULL::text, 'ele nao tem visita em andamento. se quer marcar, chame pedir_visita.'::text; RETURN;
  END IF;
  IF sel.qtd > 1 THEN
    RETURN QUERY SELECT ('De qual visita?' || E'\n' || nai_lista_visitas_corretor(k.id))::text, 'pergunte qual e chame de novo com o codigo.'::text; RETURN;
  END IF;
  IF q IS NULL THEN
    RETURN QUERY SELECT 'Pra qual dia e horário?'::text, 'chame de novo com o horario no formato AAAA-MM-DD HH:MM.'::text; RETURN;
  END IF;
  IF q <= now() + interval '10 minutes' THEN
    RETURN QUERY SELECT 'Esse horário já passou. Qual outro fica bom?'::text, NULL::text; RETURN;
  END IF;

  SELECT * INTO v FROM nai_visita WHERE id = sel.visita_id FOR UPDATE;
  v_antes := nai_quando_humano(v.quando);

  -- Horario novo em cima da hora (menos de 3h): mesma regra da visita urgente.
  IF q < now() + make_interval(hours => nai_cfg_int('antecedencia_minima_horas', 3)) THEN
    UPDATE nai_visita SET quando = q, estado = 'com_tel', aguardando = 'tel', urgente = true, atualizado_em = now() WHERE id = v.id;
    PERFORM nai_evento(v.id, 'urgente_com_tel', nai_hora_exata(q));
    PERFORM nai_avisar_tel(p_turno, v.id, 'Tel, VISITA URGENTE (menos de ' || nai_cfg_int('antecedencia_minima_horas', 3) || 'h): o corretor ' ||
      coalesce(k.nome_completo, k.nome_whatsapp, '') || ' ' || nai_fone_fmt(k.telefone) || ' mudou a visita #' || v.id || ' (' ||
      nai_ref_imovel(v.codigo) || ') para ' || nai_hora_exata(q) ||
      E'.\nEu parei aqui e parei de responder esse corretor. A visita é sua. Se quiser que eu siga, responda VISITA ' || v.id || ' OK.', 'urgente');
    PERFORM nai_parar_chat(k.id, 'visita #' || v.id || ': urgente (mudou o horario)');
    RETURN QUERY SELECT NULL::text, 'foi para o Tel (menos de 3h). responda exatamente SILENCIO.'::text;
    RETURN;
  END IF;

  -- O proprietario ja foi envolvido: pergunta de novo a ele, e o Fernando
  -- (se ja tinha confirmado) fica sabendo que mudou.
  IF v.moto_ok_em IS NOT NULL OR v.estado = 'aguardando_motoboy' THEN
    PERFORM nai_enfileirar_texto(p_turno, v.id, v.motoboy_id, 'motoboy',
      'Fernando, a visita do ' || nai_ref_imovel(v.codigo) || ' que era ' || nai_hora_exata(v.quando) ||
      ' vai mudar de horário. Te confirmo o novo assim que o proprietário responder.', 'motoboy_mudou', 600);
  END IF;
  UPDATE nai_visita SET quando = q, quando_sugerido = NULL, prop_ok_em = NULL, moto_ok_em = NULL, confirmada_em = NULL,
                        estado = CASE WHEN proprietario_id IS NULL THEN 'com_tel' ELSE 'aguardando_proprietario' END,
                        aguardando = CASE WHEN proprietario_id IS NULL THEN 'tel' ELSE 'proprietario' END,
                        reenvios_prop = 0, aviso_demora_em = NULL, aviso_tel_em = NULL,
                        lembrete_periodo_em = NULL, lembrete_1h_em = NULL, aviso_motoboy_em = NULL,
                        urgente = q < now() + make_interval(hours => nai_cfg_int('antecedencia_minima_horas', 2)),
                        atualizado_em = now()
   WHERE id = v.id;
  PERFORM nai_evento(v.id, 'corretor_mudou_horario', v_antes || ' -> ' || nai_hora_exata(q));
  IF v.proprietario_id IS NULL THEN
    PERFORM nai_avisar_tel(p_turno, v.id, 'Tel, o corretor pediu para mudar a visita #' || v.id || ' (' ||
      nai_ref_imovel(v.codigo) || ') para ' || nai_hora_exata(q) || E'.\nResponda VISITA ' || v.id || ' OK quando o proprietário confirmar.', 'mudou_horario');
  ELSE
    PERFORM nai_enfileirar_texto(p_turno, v.id, v.proprietario_id, 'proprietario',
      'O corretor pediu para mudar a visita de ' || v_antes || ' para ' || nai_quando_humano(q) || '. Tem como receber nesse horário?',
      'mudou_horario', 500);
  END IF;
  RETURN QUERY SELECT 'Certo, vou ver o novo horário com o proprietário e já te retorno'::text,
    'NAO diga que o novo horario esta confirmado.'::text;
END;
$$;

-- -------------------------------------------------- cancelar
CREATE OR REPLACE FUNCTION nai_cancelar_visita(p_turno bigint, p_codigo text, p_motivo text)
RETURNS TABLE(texto_pronto text, instrucao_para_voce text)
LANGUAGE plpgsql AS $$
DECLARE t nai_turno; k nai_contato; sel record; v nai_visita;
BEGIN
  PERFORM nai_usou_ferramenta(p_turno, 'visita');
  SELECT * INTO t FROM nai_turno WHERE id = p_turno;
  IF t.id IS NULL OR t.papel <> 'corretor' THEN RETURN QUERY SELECT NULL::text, 'so o corretor cancela a visita dele.'::text; RETURN; END IF;
  SELECT * INTO k FROM nai_contato WHERE id = t.contato_id;
  SELECT * INTO sel FROM nai_visita_do_corretor(k.id, p_codigo, NULL);
  IF sel.visita_id IS NULL THEN RETURN QUERY SELECT 'Não achei visita sua em andamento pra cancelar.'::text, NULL::text; RETURN; END IF;
  IF sel.qtd > 1 THEN
    RETURN QUERY SELECT ('Qual delas?' || E'\n' || nai_lista_visitas_corretor(k.id))::text, 'pergunte qual e chame de novo com o codigo.'::text; RETURN;
  END IF;
  SELECT * INTO v FROM nai_visita WHERE id = sel.visita_id FOR UPDATE;
  UPDATE nai_visita SET estado = 'cancelada', aguardando = NULL, motivo = left(p_motivo, 300), senha = NULL,
                        encerrada_em = now(), atualizado_em = now() WHERE id = v.id;
  PERFORM nai_evento(v.id, 'cancelada_pelo_corretor', p_motivo);
  IF v.proprietario_id IS NOT NULL AND v.ult_msg_prop_em IS NOT NULL THEN
    PERFORM nai_enfileirar_texto(p_turno, v.id, v.proprietario_id, 'proprietario',
      'Passando para avisar que a visita de ' || nai_quando_humano(v.quando) || ' foi cancelada pelo corretor. Obrigada, e desculpa o transtorno.',
      'cancelada', 500);
  END IF;
  IF v.motoboy_id IS NOT NULL AND (v.ult_msg_moto_em IS NOT NULL OR v.moto_ok_em IS NOT NULL) THEN
    PERFORM nai_enfileirar_texto(p_turno, v.id, v.motoboy_id, 'motoboy',
      'Fernando, a visita do ' || nai_ref_imovel(v.codigo) || ' de ' || nai_hora_exata(v.quando) || ' foi cancelada.', 'cancelada', 600);
  END IF;
  RETURN QUERY SELECT 'Tudo bem, cancelei a visita. Se quiser remarcar, é só me falar.'::text, NULL::text;
END;
$$;

-- -------------------------------------------------- depois da visita
CREATE OR REPLACE FUNCTION nai_resultado_visita(p_turno bigint, p_codigo text, p_resultado text, p_obs text)
RETURNS TABLE(texto_pronto text, instrucao_para_voce text)
LANGUAGE plpgsql AS $$
DECLARE t nai_turno; k nai_contato; v nai_visita; r text := lower(coalesce(p_resultado, ''));
BEGIN
  PERFORM nai_usou_ferramenta(p_turno, 'visita');
  SELECT * INTO t FROM nai_turno WHERE id = p_turno;
  IF t.id IS NULL OR t.papel <> 'corretor' THEN RETURN QUERY SELECT NULL::text, 'so o corretor.'::text; RETURN; END IF;
  SELECT * INTO k FROM nai_contato WHERE id = t.contato_id;
  SELECT * INTO v FROM nai_visita x
   WHERE x.corretor_id = k.id AND x.estado IN ('realizada', 'confirmada')
     AND (NULLIF(regexp_replace(coalesce(p_codigo, ''), '\D', '', 'g'), '') IS NULL
          OR x.codigo = NULLIF(regexp_replace(coalesce(p_codigo, ''), '\D', '', 'g'), '')::int)
   ORDER BY x.quando DESC LIMIT 1;
  IF v.id IS NULL THEN RETURN QUERY SELECT NULL::text, 'nao achei visita que ja tenha acontecido com ele.'::text; RETURN; END IF;

  UPDATE nai_visita SET resultado = r || coalesce(': ' || left(p_obs, 300), ''),
                        estado = 'encerrada', encerrada_em = now(), senha = NULL, atualizado_em = now()
   WHERE id = v.id;
  PERFORM nai_evento(v.id, 'resultado', r || coalesce(': ' || p_obs, ''));

  -- Fluxo v17 (Tel, 13/09): "Tel para fechar contratos ou sugerir outros
  -- imoveis" e FIM. O Tel recebe o que o corretor contou e a Nay para neste
  -- chat; o corretor nao recebe nada ("Que noticia boa" saiu, a pedido do Tel).
  PERFORM nai_avisar_tel(p_turno, v.id,
    CASE WHEN r ~ 'alug|fechar|quer|proposta'
         THEN 'Tel, o corretor ' || coalesce(k.nome_completo, k.nome_whatsapp, '') || ' (' || nai_fone_fmt(k.telefone) ||
              ') disse que o cliente QUER ALUGAR o ' || nai_ref_imovel(v.codigo) || '. É com você para fechar o contrato.'
         ELSE 'Tel, o corretor ' || coalesce(k.nome_completo, k.nome_whatsapp, '') || ' (' || nai_fone_fmt(k.telefone) ||
              ') contou como foi a visita no ' || nai_ref_imovel(v.codigo) || ': ' || replace(r, '_', ' ') || '.' END ||
    coalesce(E'\n"' || left(p_obs, 300) || '"', '') ||
    E'\nVisita #' || v.id || '. Parei de responder esse corretor: é com você. Para eu voltar: DEVOLVER ' || nai_fone_fmt(k.telefone) || '.',
    CASE WHEN r ~ 'alug|fechar|quer|proposta' THEN 'quer_alugar' ELSE 'resultado_visita' END);
  IF r ~ 'nao_foi|faltou|nao compareceu' THEN
    UPDATE corretores SET no_shows = coalesce(no_shows, 0) + 1 WHERE nai_chave(telefone) = k.chave;
  END IF;
  PERFORM nai_parar_chat(k.id, 'visita #' || v.id || ': resultado da visita (' || r || ')');
  RETURN QUERY SELECT NULL::text, 'foi para o Tel, que segue com ele. responda exatamente SILENCIO.'::text;
END;
$$;

-- ------------------------------------------------ escalar ao Tel (duvida)
-- Fluxo v17 (Tel, 13/09): "qualquer duvida ou ele responde a resposta que
-- achar ou pede ao Tel, nao existe isso de vou ver e te aviso". O Tel recebe o
-- card d_equipe, o corretor nao recebe nada e a Nay para NESTE CHAT ("se o tel
-- vai responder a ia nao responde mais"). nay_escalar continua na frente:
-- ele reusa o que o Tel ja respondeu antes daquele imovel e recusa numero de
-- unidade -- e isso sim e resposta, e sai normal.
CREATE OR REPLACE FUNCTION nai_escalar(p_turno bigint, p_codigo text, p_assunto text, p_disse text)
RETURNS TABLE(texto_pronto text)
LANGUAGE plpgsql AS $$
DECLARE t nai_turno; k nai_contato; e record; v_nome text; v_cod text; v_base text;
BEGIN
  SELECT * INTO t FROM nai_turno WHERE id = p_turno;
  SELECT * INTO k FROM nai_contato WHERE id = t.contato_id;
  -- ANTES DE ESCALAR, A BASE (Tel, 13/09): "olá o imovel é mobiliado?" subiu ao
  -- Tel com a resposta na ficha. O codigo precisa ser dele (escrito, card que
  -- mandamos, ou o card que ele MARCOU neste turno) -- nunca da cabeca do modelo.
  v_cod := NULLIF(regexp_replace(coalesce(p_codigo, ''), '\D', '', 'g'), '');
  IF length(v_cod) BETWEEN 3 AND 5
     AND (coalesce(nay_codigo_confirmado(k.telefone, v_cod, 72), 'nao') <> 'nao'
          OR EXISTS (SELECT 1 FROM mensagens m WHERE m.id = ANY (coalesce(t.msg_ids, '{}'))
                      AND nay_imovel_da_citacao(m.citado_id) = v_cod)) THEN
    v_base := coalesce(nai_resposta_da_base(v_cod::int, p_disse), nai_resposta_da_base(v_cod::int, p_assunto));
    IF v_base IS NOT NULL THEN
      RETURN QUERY SELECT v_base;
      RETURN;
    END IF;
  END IF;
  PERFORM nai_usou_ferramenta(p_turno, 'escalar');
  v_nome := coalesce(k.nome_completo, k.nome_whatsapp, k.telefone);
  SELECT * INTO e FROM nay_escalar(k.telefone, v_nome, p_codigo, p_assunto, p_disse);
  IF e.acao IN ('escalar', 'esperar') THEN
    v_cod := NULLIF(regexp_replace(coalesce(p_codigo, ''), '\D', '', 'g'), '');
    PERFORM nai_avisar_tel(p_turno, NULL,
      'Tel, o corretor ' || v_nome || ' (' || nai_fone_fmt(k.telefone) || ') perguntou sobre o ' ||
      coalesce(CASE WHEN length(v_cod) BETWEEN 3 AND 5 THEN nai_ref_imovel(v_cod::int) END, 'imóvel') || ': "' ||
      left(coalesce(nullif(p_disse, ''), p_assunto, ''), 300) || '". Não achei na base, você sabe?' ||
      E'\nNão falei nada com ele e parei de responder esse chat: quem responde é você. Para eu voltar: DEVOLVER ' || nai_fone_fmt(k.telefone) || '.',
      'duvida_fora_da_base');
    PERFORM nai_parar_chat(k.id, 'duvida fora da base: ' || coalesce(p_assunto, ''));
    RETURN QUERY SELECT 'SILENCIO'::text;
    RETURN;
  END IF;
  RETURN QUERY SELECT e.texto_pronto;
END;
$$;

-- ------------------------------------------------ dados do corretor (tool)
CREATE OR REPLACE FUNCTION nai_dados_do_corretor_tool(p_turno bigint)
RETURNS TABLE(instrucao_para_voce text)
LANGUAGE sql STABLE AS $$
  SELECT CASE WHEN d.completo
    THEN 'voce ja tem nome completo, CPF e CRECI deste corretor (' || coalesce(d.nome_completo, '') || '). NAO peca de novo.'
    ELSE 'falta do corretor: ' || array_to_string(ARRAY_REMOVE(ARRAY[
           CASE WHEN d.nome_completo IS NULL THEN 'nome completo' END,
           CASE WHEN d.cpf IS NULL THEN 'CPF' END,
           CASE WHEN d.creci IS NULL THEN 'CRECI' END], NULL), ', ') || '. so peca quando for marcar visita.'
  END
  FROM nai_turno t, nai_dados_corretor(t.contato_id) d WHERE t.id = p_turno;
$$;

-- --------------------------------------------- buscar por perfil (fluxo v10)
-- Card "Nay envia os bairros conforme os filtros": o que tem no BAIRRO e,
-- junto, o que casa nos bairros VIZINHOS ("Esses sao os que eu encontrei dos
-- bairros ao redor..."). A busca do bairro e a da Nay antiga, sem mudar
-- nada nela; aqui so se acrescenta o vizinho quando o bairro teve resultado
-- (quando nao teve, a antiga ja oferece o vizinho). Imovel que ele JA
-- recebeu sai da lista de vizinhos, para nao reoferecer.
CREATE OR REPLACE FUNCTION nai_buscar_por_perfil(p_turno bigint, p_bairro text, p_teto text, p_quartos text, p_mobilia text)
RETURNS TABLE(texto_pronto text, instrucao_para_voce text)
LANGUAGE plpgsql STABLE AS $$
DECLARE
  t        nai_turno;
  k        nai_contato;
  b        record;
  v_teto   numeric := nay_valor_em_reais(p_teto);
  v_q      int := NULLIF(regexp_replace(coalesce(p_quartos, ''), '[^0-9]', '', 'g'), '')::int;
  v_mob    text := lower(unaccent(btrim(coalesce(p_mobilia, ''))));
  v_sem    boolean;
  v_com    boolean;
  v_viz    text[];
  v_alt    text;
  v_aqui   text;
  v_txt    text;
  v_nome_b text;
BEGIN
  SELECT * INTO t FROM nai_turno WHERE id = p_turno;
  SELECT * INTO k FROM nai_contato WHERE id = t.contato_id;

  -- A SEQUENCIA DO FLUXO (cards do Tel): bairro -> faixa de preco -> mobilia,
  -- UMA PERGUNTA POR MENSAGEM. Quem manda a pergunta e esta funcao, nao o
  -- modelo: em 12/09 ele juntou duas perguntas numa mensagem so, duas vezes.
  -- Enquanto faltar resposta, ela devolve a PROXIMA pergunta e nada mais.
  IF nullif(btrim(coalesce(p_bairro, '')), '') IS NULL THEN
    RETURN QUERY SELECT 'Eu também tenho outras opções de locação, você está procurando imóveis em qual bairro?'::text,
      ('etapa 1 de 3 da sequencia. Diga SO essa pergunta, sem listar imovel nenhum e sem juntar outra '
       || 'pergunta. Quando ele responder, chame buscar_por_perfil de novo com o bairro.')::text;
    RETURN;
  END IF;
  IF nullif(btrim(coalesce(p_teto, '')), '') IS NULL THEN
    RETURN QUERY SELECT 'E qual a faixa de preço que seus clientes estão buscando?'::text,
      ('etapa 2 de 3 da sequencia. Diga SO essa pergunta, sem listar imovel nenhum e sem juntar outra '
       || 'pergunta. Quando ele responder, chame buscar_por_perfil de novo com bairro e teto.')::text;
    RETURN;
  END IF;
  IF nullif(btrim(coalesce(p_mobilia, '')), '') IS NULL THEN
    RETURN QUERY SELECT 'E eles têm preferência por semimobiliado ou mobiliado?'::text,
      ('etapa 3 de 3 da sequencia. Diga SO essa pergunta, sem listar imovel nenhum, e quando ele '
       || 'responder chame buscar_por_perfil de novo com bairro, teto e mobilia.')::text;
    RETURN;
  END IF;

  v_sem := v_mob ~ '\m(sem|nao|vazio)\M';
  v_com := NOT v_sem AND v_mob ~ '\m(com|mobiliad|semi|modulad|planejad)';

  -- O FORMATO E DO TEL (13/09, depois do teste: "me mandou 2 imoveis de forma
  -- desformatada, quero algo assim bem formatado"). Um bloco por imovel, com o
  -- icone, o nome em negrito do WhatsApp e o codigo com #.
  SELECT string_agg(nai_bloco_oferta(z.c), E'\n\n' ORDER BY z.v) INTO v_aqui FROM (
    SELECT i.codigo AS c, i.valor_aluguel AS v FROM imoveis i
     WHERE nay_normalizar_lugar(i.bairro, true) LIKE '%' || nay_normalizar_lugar(p_bairro, true) || '%'
       AND nai_oferta_serve(i, k.telefone, v_teto, v_q, v_sem, v_com)
     ORDER BY i.valor_aluguel LIMIT 5) z;

  v_viz := nay_bairros_proximos(btrim(coalesce(p_bairro, '')));
  IF coalesce(array_length(v_viz, 1), 0) > 1 THEN
    SELECT string_agg(nai_bloco_oferta(z.c), E'\n\n' ORDER BY z.v) INTO v_alt FROM (
      SELECT i.codigo AS c, i.valor_aluguel AS v FROM imoveis i
       WHERE i.bairro = ANY (v_viz)
         AND nay_normalizar_lugar(i.bairro, true) NOT LIKE '%' || nay_normalizar_lugar(p_bairro, true) || '%'
         AND nai_oferta_serve(i, k.telefone, v_teto, v_q, v_sem, v_com)
       ORDER BY i.valor_aluguel LIMIT 5) z;
  END IF;

  -- Nada aqui nem perto: quem responde e a funcao antiga, que sabe dizer "voce
  -- quis dizer Ponta Negra?" e "esse bairro nao e da nossa area".
  IF v_aqui IS NULL AND v_alt IS NULL THEN
    SELECT * INTO b FROM nay_buscar_por_perfil(p_bairro, 'locacao', p_teto, p_quartos, p_mobilia);
    RETURN QUERY SELECT upper(left(b.texto_pronto, 1)) || substr(b.texto_pronto, 2), b.instrucao_para_voce;
    RETURN;
  END IF;

  SELECT coalesce((SELECT i.bairro FROM imoveis i
                    WHERE nay_normalizar_lugar(i.bairro, true) LIKE '%' || nay_normalizar_lugar(p_bairro, true) || '%'
                    LIMIT 1), initcap(btrim(p_bairro))) INTO v_nome_b;

  IF v_aqui IS NOT NULL THEN
    v_txt := 'No ' || v_nome_b || ' eu tenho estas opções:' || E'\n\n' || v_aqui;
    IF v_alt IS NOT NULL THEN
      v_txt := v_txt || E'\n\n' || 'E tenho estas aqui perto:' || E'\n\n' || v_alt;
    END IF;
  ELSE
    v_txt := 'No ' || v_nome_b || ', não tenho nenhum imóvel nesse perfil disponível no momento.' || E'\n\n' ||
             'Mas tenho estas opções aqui perto:' || E'\n\n' || v_alt;
  END IF;

  RETURN QUERY SELECT v_txt,
    ('mande o texto_pronto EXATAMENTE como veio: cada imovel no seu bloco, com o icone, o negrito e as linhas com •. '
     || 'NAO resuma, NAO junte tudo numa linha, NAO reescreva e NAO invente imovel que nao esta na lista. '
     || 'Se ele quiser detalhe de um, chame imovel_por_codigo. NAO sugira visita aqui.')::text;
END;
$$;

-- Os filtros de toda oferta, num lugar so: no mercado, nosso, com aluguel, e o
-- que ele pediu (teto, quartos, mobilia). Nao repete imovel que ele ja recebeu.
CREATE OR REPLACE FUNCTION nai_oferta_serve(i imoveis, p_telefone text, p_teto numeric, p_quartos int,
                                            p_sem boolean, p_com boolean)
RETURNS boolean LANGUAGE sql STABLE AS $$
  SELECT nay_esta_no_mercado(i.disponivel, i.bloqueado, i.publicado_no_site)
     AND NOT coalesce(i.e_parceiro, false)
     AND coalesce(i.valor_aluguel, 0) > 0
     AND (p_teto IS NULL OR i.valor_aluguel <= p_teto)
     AND (p_quartos IS NULL OR p_quartos = 0 OR i.quartos = p_quartos)
     AND (NOT p_sem OR (coalesce(i.mobilia, '') !~* 'mobiliad' AND coalesce(i.descricao, '') !~* '\mmobiliad'))
     AND (NOT p_com OR (coalesce(i.mobilia, '') ~* '(mobiliad|modulad|planejad|ar-condicionado)'
                        OR coalesce(i.descricao, '') ~* '(mobiliad|modulad|planejad)'))
     AND NOT EXISTS (SELECT 1 FROM envios e
                      WHERE e.codigo = i.codigo::text AND e.enviado_em > now() - interval '30 days'
                        AND right(regexp_replace(coalesce(e.telefone, ''), '\D', '', 'g'), 8)
                            = right(regexp_replace(coalesce(p_telefone, ''), '\D', '', 'g'), 8));
$$;
