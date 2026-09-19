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
    RETURN QUERY SELECT 'Esse horário já passou 😅 Qual outro horário fica bom pro seu cliente?'::text,
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
  IF v_v.id IS NOT NULL AND v_v.estado NOT IN ('coletando') THEN
    RETURN QUERY SELECT NULL::text,
      ('ja existe visita em andamento desse imovel com ele (' || nai_status_humano(v_v) || ', ' ||
       coalesce(nai_quando_humano(v_v.quando), 'sem horario') || '). se ele quer OUTRO horario, chame mudar_horario_da_visita; nao chame pedir_visita.')::text;
    RETURN;
  END IF;

  v_urg := v_q < now() + make_interval(hours => v_min_h);
  SELECT * INTO v_dono FROM nai_proprietario_do_imovel(v_cod);
  SELECT * INTO v_moto FROM nai_motoboy();

  IF v_v.id IS NULL THEN
    INSERT INTO nai_visita (codigo, corretor_id, quando, estado, aguardando, urgente, qualificado,
                            proprietario_cadastro, proprietario_nome, motoboy_id, proximo_lembrete_dados_em)
         VALUES (v_cod, k.id, v_q, 'coletando', 'corretor', v_urg, NULL,
                 v_dono.cadastro_id, v_dono.nome, v_moto.contato_id,
                 now() + make_interval(mins => nai_cfg_int('dados_primeiro_lembrete_min', 3)))
    RETURNING id INTO v_id;
    PERFORM nai_evento(v_id, 'pedida', 'horario ' || nai_hora_exata(v_q));
  ELSE
    v_id := v_v.id;
    UPDATE nai_visita SET quando = v_q, urgente = v_urg, atualizado_em = now()
     WHERE id = v_id;
    PERFORM nai_evento(v_id, 'horario_mudado_na_coleta', nai_hora_exata(v_q));
  END IF;

  -- VISITA URGENTE (decisao do Tel, 12/09): pedida para daqui a menos de
  -- 3 horas nao passa pela IA. Ela sobe para o Tel e PARA ali -- nao pede
  -- dados, nao fala com o proprietario nem com o Fernando.
  IF v_urg THEN
    UPDATE nai_visita SET estado = 'com_tel', aguardando = 'tel', urgente = true,
                          proximo_lembrete_dados_em = NULL, atualizado_em = now()
     WHERE id = v_id;
    PERFORM nai_evento(v_id, 'urgente_com_tel', nai_hora_exata(v_q));
    PERFORM nai_avisar_tel(p_turno, v_id,
      'Tel, VISITA URGENTE (menos de ' || v_min_h || 'h): ' || nai_ref_imovel(v_cod) || ', ' || nai_hora_exata(v_q) ||
      E'.
Corretor: ' || coalesce(k.nome_completo, k.nome_whatsapp, '') || ' ' || nai_fone_fmt(k.telefone) ||
      E'
Eu parei aqui: não falei com o proprietário nem com o Fernando. A visita #' || v_id || ' é sua.' ||
      E'
Se quiser que eu siga, responda VISITA ' || v_id || ' OK.', 'urgente');
    -- CALADA (Tel, 12/09): passou para o Tel, ninguem mais e avisado.
    RETURN QUERY SELECT NULL::text,
      ('visita URGENTE (menos de ' || v_min_h || 'h): ja esta com o TEL e voce PAROU. O corretor NAO fica sabendo: '
       || 'responda exatamente SILENCIO, sem prometer retorno, sem citar o Tel. NAO peca dados e NAO chame pedir_visita '
       || 'de novo para este horario. Se ele perguntar de outro imovel, siga normal.')::text;
    RETURN;
  END IF;

  -- Dados do corretor: conhecido (nome completo, CPF e CRECI) ou novo.
  SELECT * INTO d FROM nai_dados_corretor(k.id);
  IF d.completo THEN
    RETURN QUERY SELECT
      'Vou confirmar aqui a visita e já te retorno! 🙌 Enquanto isso, me passa o nome completo e o CPF do visitante?'::text,
      'quando ele mandar, chame guardar_dados_da_visita com o que veio. NAO diga que a visita esta confirmada: quem confirma e o sistema, depois do proprietario e do Fernando.'::text;
  ELSE
    RETURN QUERY SELECT
      ('Vou confirmar aqui a visita e já te retorno! 🙌 Enquanto isso, me passa o ' ||
       nai_lista_pt(ARRAY_REMOVE(ARRAY[
         CASE WHEN d.nome_completo IS NULL THEN 'seu nome completo' END,
         CASE WHEN d.cpf IS NULL THEN 'CPF' END,
         CASE WHEN d.creci IS NULL THEN 'CRECI' END], NULL)) || '?')::text,
      'e um corretor que ainda nao tem cadastro completo: primeiro os dados DELE, depois o sistema pede os do visitante. quando ele mandar, chame guardar_dados_da_visita com tudo o que veio. NAO diga que a visita esta confirmada.'::text;
  END IF;
END;
$$;

-- ----------------------------------------------- pedir ao proprietario
-- Chamada quando os dados ficam completos. Enfileira o pedido (p_solicita)
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
      E'\nVisitante: ' || coalesce(v.visitante_nome, '?') || ', CPF ' || coalesce(nai_cpf_fmt(v.visitante_cpf), '?') ||
      E'\nNão consigo falar com o proprietário (' ||
      CASE dono.motivo WHEN 'sem_telefone' THEN 'sem telefone no cadastro'
                       WHEN 'tratar_com_outra_pessoa' THEN 'o cadastro diz: ' || coalesce(dono.nome, '')
                       WHEN 'dois_donos' THEN 'o imóvel tem dois proprietários no cadastro'
                       WHEN 'sem_cadastro' THEN 'imóvel sem proprietário cadastrado'
                       ELSE 'o telefone do proprietário é o do próprio corretor' END || ').' ||
      E'\nQuando resolver, me responda:\nVISITA ' || v.id || ' OK  (proprietário confirmou)\nVISITA ' || v.id ||
      E' HORARIO 16h  (ele pediu outro horário)\nVISITA ' || v.id || ' CANCELA',
      'sem_proprietario');
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
  SELECT * INTO sel FROM nai_visita_do_corretor(k.id, p_codigo, ARRAY['coletando']);
  IF sel.visita_id IS NULL THEN
    RETURN QUERY SELECT NULL::text, 'nao ha visita esperando dados. se ele quer marcar uma visita, chame pedir_visita primeiro.'::text; RETURN;
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
            THEN 'Só falta ' || nai_lista_pt(v_falta) || ' pra eu fechar a visita 😉' ELSE '' END)::text,
      'quando ele mandar, chame guardar_dados_da_visita de novo.'::text;
    RETURN;
  END IF;

  -- Tudo certo: pede ao proprietario.
  PERFORM nai_evento(v.id, 'dados_completos', NULL);
  UPDATE nai_visita SET proximo_lembrete_dados_em = NULL WHERE id = v.id;
  v_res := nai_pedir_ao_proprietario(v.id, p_turno);
  IF v_res = 'com_tel' THEN
    -- Foi para o Tel (sem contato do proprietario): ele resolve e ele responde.
    -- O corretor NAO ouve falar disso (Tel, 12/09).
    RETURN QUERY SELECT 'Anotado! Assim que eu tiver a confirmação do horário eu te aviso 😉'::text,
      'esta visita esta com o TEL: NAO cite o Tel, NAO prometa prazo e NAO peca mais nada sobre ela.'::text;
    RETURN;
  END IF;
  RETURN QUERY SELECT 'Anotado! Já pedi a confirmação do horário ao proprietário, assim que ele responder eu te aviso 😉'::text,
    'NAO diga que a visita esta confirmada. o sistema confirma sozinho quando proprietario e Fernando confirmarem.'::text;
END;
$$;

-- -------------------------------------------------- minhas visitas
CREATE OR REPLACE FUNCTION nai_minhas_visitas(p_turno bigint)
RETURNS TABLE(texto_pronto text, instrucao_para_voce text)
LANGUAGE plpgsql STABLE AS $$
DECLARE t nai_turno; linhas text;
BEGIN
  SELECT * INTO t FROM nai_turno WHERE id = p_turno;
  SELECT string_agg('• ' || nai_ref_imovel(x.codigo) || ' — ' || coalesce(nai_quando_humano(x.quando), 'sem horário') ||
                    ' — ' || CASE x.estado
                      WHEN 'coletando' THEN 'falta me passar os dados'
                      WHEN 'aguardando_proprietario' THEN 'esperando o proprietário confirmar'
                      WHEN 'negociando' THEN CASE WHEN x.aguardando = 'corretor' THEN 'o proprietário sugeriu ' || coalesce(nai_quando_humano(x.quando_sugerido), 'outro horário') ELSE 'vendo outro horário com o proprietário' END
                      WHEN 'aguardando_acesso' THEN 'acertando a chave com o proprietário'
                      WHEN 'aguardando_motoboy' THEN 'confirmando com o Fernando'
                      WHEN 'confirmada' THEN 'confirmada ✅'
                      WHEN 'com_tel' THEN 'o Tel está vendo'
                      WHEN 'realizada' THEN 'já aconteceu'
                      ELSE x.estado END, E'\n' ORDER BY x.quando)
    INTO linhas
    FROM nai_visita x WHERE x.corretor_id = t.contato_id AND nai_visita_aberta(x.estado);
  RETURN QUERY SELECT coalesce(linhas, 'Não tem nenhuma visita em andamento com você agora.'),
                      'repita a lista como veio.'::text;
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
    v_txt := 'Fechado! O corretor confirmou ' || nai_quando_humano(v.quando) || '. ' ||
             CASE WHEN v.estado = 'aguardando_acesso' THEN regexp_replace(coalesce(v_txt, ''), '^Obrigada!\s*', '')
                  ELSE nai_frase_visitante(v) || ' Obrigada 😊' END;
    PERFORM nai_enfileirar_texto(p_turno, v.id, v.proprietario_id, 'proprietario', v_txt, 'fecha_novo_horario', 500);
    RETURN QUERY SELECT 'Fechado! Vou acertar os detalhes com o proprietário e com o Fernando e já te confirmo 😉'::text,
      'NAO diga que esta confirmada ainda.'::text;
    RETURN;
  END IF;

  IF q IS NULL THEN
    RETURN QUERY SELECT 'Sem problemas! Qual horário fica bom pro seu cliente?'::text,
      'quando ele disser, chame responder_horario_do_proprietario de novo com outro_quando.'::text; RETURN;
  END IF;
  IF q <= now() + interval '10 minutes' THEN
    RETURN QUERY SELECT 'Esse horário já passou 😅 Qual outro horário fica bom pro seu cliente?'::text, NULL::text; RETURN;
  END IF;

  -- Loop: leva a contraproposta ao proprietario.
  UPDATE nai_visita SET quando = q, quando_sugerido = NULL, prop_ok_em = NULL, estado = 'negociando',
                        aguardando = 'proprietario', reenvios_prop = 0, aviso_demora_em = NULL, atualizado_em = now()
   WHERE id = v.id;
  -- Card "Leva a contraproposta": "O cliente nao consegue as X. Pode ser as Y?"
  PERFORM nai_enfileirar_texto(p_turno, v.id, v.proprietario_id, 'proprietario',
    'O cliente não consegue ' || nai_quando_humano(v.quando_sugerido) || '. Pode ser ' || nai_quando_humano(q) || '?',
    'contraproposta_corretor', 500);
  RETURN QUERY SELECT 'Certo, vou ver esse horário com o proprietário e já te retorno 😉'::text, NULL::text;
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
    RETURN QUERY SELECT 'Esse horário já passou 😅 Qual outro fica bom?'::text, NULL::text; RETURN;
  END IF;

  SELECT * INTO v FROM nai_visita WHERE id = sel.visita_id FOR UPDATE;
  v_antes := nai_quando_humano(v.quando);

  IF v.estado = 'coletando' THEN
    UPDATE nai_visita SET quando = q, urgente = q < now() + make_interval(hours => nai_cfg_int('antecedencia_minima_horas', 2)),
                          atualizado_em = now() WHERE id = v.id;
    RETURN QUERY SELECT ('Certo, fica ' || nai_quando_humano(q) || '. Só falta me passar os dados pra eu pedir ao proprietário.')::text, NULL::text;
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
  RETURN QUERY SELECT 'Certo, vou ver o novo horário com o proprietário e já te retorno 😉'::text,
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

  IF r ~ 'alug|fechar|quer|proposta' THEN
    PERFORM nai_avisar_tel(p_turno, v.id,
      'Tel, o corretor ' || coalesce(k.nome_completo, k.nome_whatsapp, '') || ' (' || nai_fone_fmt(k.telefone) ||
      ') disse que o cliente QUER ALUGAR o ' || nai_ref_imovel(v.codigo) || '.' ||
      coalesce(E'\n"' || left(p_obs, 300) || '"', '') || E'\nVisita #' || v.id || '. É com você para fechar o contrato.',
      'quer_alugar');
    RETURN QUERY SELECT 'Que notícia boa! 🙌'::text,
      'o Tel ja recebeu o recado e fala com ele. NAO cite o Tel nem prometa contato.'::text;
  ELSIF r ~ 'nao_foi|faltou|nao compareceu' THEN
    UPDATE corretores SET no_shows = coalesce(no_shows, 0) + 1 WHERE nai_chave(telefone) = k.chave;
    RETURN QUERY SELECT 'Entendi. Se quiser remarcar, é só me falar.'::text, NULL::text;
  ELSIF r ~ 'nao_gostou|nao gostou|nao' THEN
    RETURN QUERY SELECT 'Poxa, entendi. Quer que eu veja outras opções parecidas pro seu cliente?'::text,
      'se ele quiser, pergunte o que nao agradou e use buscar_por_perfil.'::text;
  ELSE
    RETURN QUERY SELECT 'Beleza, fico no aguardo então. Qualquer coisa me chama.'::text, NULL::text;
  END IF;
END;
$$;

-- ------------------------------------------------ escalar ao Tel (duvida)
-- A MESMA pendencia da Nay antiga (`nay_escalar`), para o RESPOSTA <id> do
-- Tel e o reuso da resposta continuarem funcionando. O aviso ao Tel sai
-- pela caixa de saida (e no teste vai para o numero de teste).
CREATE OR REPLACE FUNCTION nai_escalar(p_turno bigint, p_codigo text, p_assunto text, p_disse text)
RETURNS TABLE(texto_pronto text)
LANGUAGE plpgsql AS $$
DECLARE t nai_turno; k nai_contato; e record; v_nome text;
BEGIN
  SELECT * INTO t FROM nai_turno WHERE id = p_turno;
  SELECT * INTO k FROM nai_contato WHERE id = t.contato_id;
  v_nome := coalesce(k.nome_completo, k.nome_whatsapp, k.telefone);
  SELECT * INTO e FROM nay_escalar(k.telefone, v_nome, p_codigo, p_assunto, p_disse);
  IF e.acao = 'escalar' THEN
    PERFORM nai_avisar_tel(p_turno, NULL,
      '🔔 Pendencia ' || e.id_pendencia || E'\nCorretor: ' || v_nome || E'\nAssunto: ' || coalesce(p_assunto, '') ||
      E'\nDisse: ' || coalesce(p_disse, '') || E'\n\nResponda com: RESPOSTA ' || e.id_pendencia || ' <sua resposta>',
      'pendencia');
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

  SELECT * INTO b FROM nay_buscar_por_perfil(p_bairro, 'locacao', p_teto, p_quartos, p_mobilia);
  IF b.texto_pronto IS NULL OR b.texto_pronto !~ '^encontrei ' THEN
    RETURN QUERY SELECT upper(left(b.texto_pronto, 1)) || substr(b.texto_pronto, 2), b.instrucao_para_voce; RETURN;
  END IF;

  v_sem := v_mob ~ '\m(sem|nao|vazio)\M';
  v_com := NOT v_sem AND v_mob ~ '\m(com|mobiliad|semi|modulad|planejad)';
  v_viz := nay_bairros_proximos(btrim(coalesce(p_bairro, '')));
  IF coalesce(array_length(v_viz, 1), 0) > 1 THEN
    SELECT string_agg(x, chr(10) ORDER BY x) INTO v_alt FROM (
      SELECT '• ' || coalesce(NULLIF(i.condominio_nome, ''), i.tipo) || ' (' || i.bairro || ')'
             || coalesce(' — ' || i.quartos || ' quartos', '')
             || ' — ' || replace(to_char(i.valor_aluguel, 'FM999,999,990'), ',', '.')
             || ' — Código: ' || i.codigo AS x
        FROM imoveis i
       WHERE i.bairro = ANY (v_viz)
         AND nay_normalizar_lugar(i.bairro, true) NOT LIKE '%' || nay_normalizar_lugar(p_bairro, true) || '%'
         AND nay_esta_no_mercado(i.disponivel, i.bloqueado, i.publicado_no_site)
         AND NOT coalesce(i.e_parceiro, false)
         AND coalesce(i.valor_aluguel, 0) > 0
         AND (v_teto IS NULL OR i.valor_aluguel <= v_teto)
         AND (v_q IS NULL OR v_q = 0 OR i.quartos = v_q)
         AND (NOT v_sem OR (coalesce(i.mobilia, '') !~* 'mobiliad' AND coalesce(i.descricao, '') !~* '\mmobiliad'))
         AND (NOT v_com OR (coalesce(i.mobilia, '') ~* '(mobiliad|modulad|planejad|ar-condicionado)'
                            OR coalesce(i.descricao, '') ~* '(mobiliad|modulad|planejad)'))
         AND NOT EXISTS (SELECT 1 FROM envios e
                          WHERE e.codigo = i.codigo::text AND e.enviado_em > now() - interval '30 days'
                            AND right(regexp_replace(coalesce(e.telefone, ''), '\D', '', 'g'), 8) = right(regexp_replace(k.telefone, '\D', '', 'g'), 8))
       ORDER BY i.valor_aluguel LIMIT 5) y;
  END IF;

  IF v_alt IS NULL THEN
    RETURN QUERY SELECT upper(left(b.texto_pronto, 1)) || substr(b.texto_pronto, 2), b.instrucao_para_voce; RETURN;
  END IF;
  RETURN QUERY SELECT
    (upper(left(b.texto_pronto, 1)) || substr(b.texto_pronto, 2) || chr(10) || chr(10) ||
     'Esses são os que eu encontrei dos bairros ao redor que têm o que seu cliente está buscando:' || chr(10) || v_alt)::text,
    ('repita o texto_pronto como veio: primeiro os do bairro pedido, depois os dos bairros ao redor (o bairro de cada um ja vem na lista). '
     || 'Se ele quiser detalhe de um, chame imovel_por_codigo. Nao invente imovel que nao esta na lista. NAO sugira visita aqui.')::text;
END;
$$;
