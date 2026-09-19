-- =====================================================================
-- NAI atendimento locacao -- 04: quem atende (NAI ou Nay antiga) e o
-- CABECALHO de cada turno (quem escreveu, em que papel, sobre qual visita)
-- =====================================================================

-- Chamada pelo PRIMEIRO no do fluxo antigo "Nay- recebe mensagem". Devolve
-- 'nai' ou 'nay'. Falha para o lado da Nay antiga: qualquer duvida, erro ou
-- configuracao ausente = 'nay', que e o que ja funcionava.
CREATE OR REPLACE FUNCTION nai_quem_atende(p_phone text, p_grupo boolean)
RETURNS text LANGUAGE plpgsql STABLE AS $$
DECLARE
  v_modo  text := nai_cfg('modo', 'desligado');
  v_chave text := nai_chave(p_phone);
BEGIN
  IF coalesce(p_grupo, true) OR v_chave IS NULL THEN RETURN 'nay'; END IF;
  IF v_modo = 'todos' THEN RETURN 'nai'; END IF;
  IF v_modo = 'teste' AND v_chave = ANY (nai_chaves_teste()) THEN RETURN 'nai'; END IF;
  RETURN 'nay';
EXCEPTION WHEN others THEN
  RETURN 'nay';
END;
$$;

-- Status da visita em palavras, para o contexto do agente.
CREATE OR REPLACE FUNCTION nai_status_humano(v nai_visita)
RETURNS text LANGUAGE sql STABLE AS $$
  SELECT CASE v.estado
    WHEN 'coletando' THEN 'esperando os dados (nome completo e CPF) para pedir ao proprietário'
    WHEN 'aguardando_proprietario' THEN 'pedido feito ao proprietário, esperando ele confirmar'
    WHEN 'negociando' THEN CASE WHEN v.aguardando = 'corretor'
                             THEN 'o proprietário sugeriu ' || coalesce(nai_quando_humano(v.quando_sugerido), 'outro horário') || ' e estamos esperando o corretor responder'
                             ELSE 'esperando o proprietário dizer outro horário' END
    WHEN 'aguardando_acesso' THEN 'proprietário aceitou, acertando o acesso ao imóvel'
    WHEN 'aguardando_motoboy' THEN 'proprietário confirmou, confirmando com o Fernando'
    WHEN 'confirmada' THEN CASE WHEN v.visitante_nome IS NULL OR v.visitante_cpf IS NULL
                              THEN 'CONFIRMADA, mas os dados que o sistema pediu ainda nao chegaram'
                              ELSE 'CONFIRMADA' END
    WHEN 'com_tel' THEN 'o Tel está resolvendo'
    WHEN 'realizada' THEN 'a visita já aconteceu, esperando o retorno do corretor'
    ELSE v.estado END;
$$;

CREATE OR REPLACE FUNCTION nai_visita_aberta(p_estado text)
RETURNS boolean LANGUAGE sql IMMUTABLE AS $$
  SELECT p_estado NOT IN ('encerrada', 'cancelada', 'expirada');
$$;

-- Contexto do CORRETOR: o que ja conversaram (inclusive com a Nay antiga),
-- o que ele ja recebeu e se ja foi sugerida visita. Pedido do Tel (11/09):
-- ela nao pode atender como se fosse a primeira mensagem, nem reoferecer o
-- que ja mandou, nem insistir em visita.
CREATE OR REPLACE FUNCTION nai_contexto_corretor(p_contato bigint)
RETURNS text LANGUAGE plpgsql STABLE AS $$
DECLARE
  k         nai_contato;
  v_ids     bigint[];
  v_fim8    text;
  linhas    text;
  enviados  text;
  historico text;
  v_ult     timestamptz;
  v_mem     int;
  saida     text;
  v_dados   text;
BEGIN
  SELECT * INTO k FROM nai_contato WHERE id = p_contato;
  v_fim8 := right(regexp_replace(k.telefone, '\D', '', 'g'), 8);
  -- as mensagens DESTE turno (o turno ja foi aberto quando o contexto e montado)
  SELECT coalesce(t.msg_ids, '{}') INTO v_ids FROM nai_turno t WHERE t.contato_id = p_contato ORDER BY t.id DESC LIMIT 1;

  SELECT string_agg('visita #' || x.id || ' · ' || nai_ref_imovel(x.codigo) || ' · ' ||
                    coalesce(nai_quando_humano(x.quando), 'sem horário') || ' · ' || nai_status_humano(x), E'\n' ORDER BY x.id)
    INTO linhas
    FROM nai_visita x WHERE x.corretor_id = p_contato AND nai_visita_aberta(x.estado);
  saida := CASE WHEN linhas IS NULL THEN 'este corretor nao tem visita em andamento. '
                ELSE E'visitas em andamento deste corretor (so ele ve isto; use para saber em que pe esta):\n' || linhas || E'\n' END;

  -- DADOS PEDIDOS PELO SISTEMA (fluxo v17, 13/09): depois da "Visita confirmada"
  -- o sistema pede os dados numa mensagem que NAO passa pela memoria dela. Sem
  -- esta linha, "Pedro Victor Araujo, CPF ..., CRECI 1234" virou "qual e a duvida?".
  SELECT string_agg('visita #' || x.id || ' (' || nai_ref_imovel(x.codigo) || '): falta ' ||
                    nai_lista_pt(ARRAY_REMOVE(ARRAY[
                      CASE WHEN d.nome_completo IS NULL THEN 'o nome completo dele' END,
                      CASE WHEN d.cpf IS NULL THEN 'o CPF dele' END,
                      CASE WHEN d.creci IS NULL THEN 'o CRECI dele' END,
                      CASE WHEN x.visitante_nome IS NULL THEN 'o nome completo do visitante' END,
                      CASE WHEN x.visitante_cpf IS NULL THEN 'o CPF do visitante' END], NULL)), '; ')
    INTO v_dados
    FROM nai_visita x, nai_dados_corretor(p_contato) d
   WHERE x.corretor_id = p_contato AND x.estado = 'confirmada'
     AND (x.visitante_nome IS NULL OR x.visitante_cpf IS NULL OR NOT coalesce(d.completo, false));
  IF v_dados IS NOT NULL THEN
    saida := saida || 'O SISTEMA JA PEDIU A ELE OS DADOS DA VISITA CONFIRMADA -- ' || v_dados ||
             '. Se a mensagem dele trouxer nome, CPF ou CRECI (dele ou do visitante), chame guardar_dados_da_visita NESTA resposta com tudo o que veio e diga o texto_pronto como veio (vazio = SILENCIO). NAO pergunte qual e a duvida. ';
  END IF;

  -- Imoveis que ele JA recebeu (30 dias).
  SELECT string_agg(x.codigo || ' (' || x.quando || ')', ', ' ORDER BY x.ult DESC) INTO enviados
    FROM (SELECT e.codigo, max(e.enviado_em) AS ult,
                 to_char(max(e.enviado_em) AT TIME ZONE 'America/Manaus', 'DD/MM') AS quando
            FROM envios e
           WHERE right(regexp_replace(coalesce(e.telefone, ''), '\D', '', 'g'), 8) = v_fim8
             AND e.enviado_em > now() - interval '30 days' AND e.codigo IS NOT NULL
           GROUP BY e.codigo ORDER BY max(e.enviado_em) DESC LIMIT 15) x;
  IF enviados IS NOT NULL THEN
    saida := saida || 'imoveis que ele JA RECEBEU de voce: ' || enviados ||
             '. NAO mande de novo nenhum desses sem ele pedir; ao oferecer opcoes, mande outros. ';
  END IF;

  -- O IMOVEL DESTA CONVERSA (13/09): sem isto o modelo perdia o fio -- "quero
  -- saber se e mobiliado" virava pergunta sem imovel e subia ao Tel.
  DECLARE v_imv int; BEGIN
    v_imv := nai_imovel_da_conversa(p_contato, NULL);
    IF v_imv IS NOT NULL THEN
      saida := saida || 'IMOVEL DESTA CONVERSA: ' || nai_ref_imovel(v_imv) || ' (codigo ' || v_imv ||
               '). Quando ele perguntar algo sem dizer o codigo ("e mobiliado?", "tem garagem?", "me manda as fotos"), '
               || 'e DESTE imovel que ele fala: use este codigo nas ferramentas, sem perguntar de novo. ';
    END IF;
  END;

  -- Ja estao conversando? (mensagem dele ou nossa antes deste turno)
  -- 14/09: nada anterior ao marco de "conversa zerada" conta como contexto --
  -- no teste ela tem que atender como se fosse a primeira mensagem do cliente.
  SELECT max(q) INTO v_ult FROM (
    SELECT max(m.criada_em) AS q FROM mensagens m
     WHERE right(regexp_replace(m.telefone, '\D', '', 'g'), 8) = v_fim8
       AND NOT (m.id = ANY (v_ids))
       AND m.criada_em > coalesce(k.zerado_em, '-infinity'::timestamptz)
    UNION ALL
    SELECT max(s.enviado_em) FROM nai_saida s
     WHERE s.contato_id = p_contato AND s.estado IN ('enviado', 'simulado')
       AND s.enviado_em > coalesce(k.zerado_em, '-infinity'::timestamptz)) u;
  IF v_ult > now() - interval '12 hours' THEN
    saida := saida || 'voces JA ESTAO CONVERSANDO (ultima troca as ' || to_char(v_ult AT TIME ZONE 'America/Manaus', 'HH24:MI') ||
             '): NAO cumprimente como se fosse a primeira vez, NAO se apresente e NAO recomece o atendimento -- siga de onde parou. ';
  ELSIF v_ult IS NOT NULL THEN
    saida := saida || 'ele ja conversou com voce antes (ultima vez em ' || to_char(v_ult AT TIME ZONE 'America/Manaus', 'DD/MM') ||
             '): cumprimente, mas trate como quem ja conhece, sem se apresentar. ';
  END IF;

  -- Visita: no maximo UMA sugestao por DIA, por corretor (Tel, 12/09).
  IF (k.visita_sugerida_em AT TIME ZONE 'America/Manaus')::date = (now() AT TIME ZONE 'America/Manaus')::date THEN
    saida := saida || 'voce JA SUGERIU visita a ele (' || to_char(k.visita_sugerida_em AT TIME ZONE 'America/Manaus', 'DD/MM HH24:MI') ||
             '): NAO sugira de novo HOJE nem pergunte se quer agendar; so fale de visita se ELE pedir. ';
  END IF;

  -- Enquanto a memoria da NAI for curta, a conversa dele com a Nay antiga.
  SELECT count(*) INTO v_mem FROM nai_memoria WHERE session_id = 'nai:corretor:' || p_contato;
  IF v_mem < 6 AND k.chave !~ '^lid:' THEN
    SELECT string_agg(l, E'\n' ORDER BY id) INTO historico FROM (
      SELECT id, CASE WHEN message->>'type' = 'human'
                      THEN 'corretor: ' || left(regexp_replace(coalesce(substring(message->>'content' FROM 'mensagem do corretor:(.*)$'),
                                                                      message->>'content'), '\s+', ' ', 'g'), 200)
                      ELSE 'nay: ' || left(regexp_replace(message->>'content', '\s+', ' ', 'g'), 200) END AS l
        FROM nay_memoria
       WHERE session_id IN ('=' || k.telefone, '=' || nai_fone_br(k.telefone), k.telefone)
         AND message->>'type' IN ('human', 'ai') AND jsonb_typeof(message->'content') = 'string'
         AND btrim(message->>'content') <> ''
       ORDER BY id DESC LIMIT 10) h;
    IF historico IS NOT NULL THEN
      saida := saida || E'\nconversa anterior dele com voce (da mais antiga para a mais nova; use para NAO repetir pergunta nem oferta):\n'
               || historico || E'\n';
    END IF;
  END IF;
  RETURN saida;
END;
$$;

-- O contexto que vai no texto do agente, por papel.
CREATE OR REPLACE FUNCTION nai_contexto(p_papel text, p_contato bigint, p_visita bigint, p_teste boolean)
RETURNS text LANGUAGE plpgsql STABLE AS $$
DECLARE v nai_visita; r text; linhas text;
BEGIN
  IF p_papel = 'corretor' THEN
    RETURN nai_contexto_corretor(p_contato);
  END IF;

  IF p_papel = 'proprietario' THEN
    IF p_visita IS NULL THEN
      SELECT string_agg('visita #' || x.id || ' · ' || nai_ref_imovel_prop(x.codigo) || ' · ' ||
                        coalesce(nai_quando_humano(x.quando), 'sem horário'), E'\n' ORDER BY x.id)
        INTO linhas FROM nai_visita x
       WHERE nai_visita_aberta(x.estado)
         AND (x.proprietario_id = p_contato OR (p_teste AND x.proprietario_id IS NOT NULL));
      RETURN CASE WHEN linhas IS NULL
        THEN 'NAO HA VISITA EM ANDAMENTO com este proprietario. Agradeca e diga que vai passar ao Tel, chamando resposta_do_proprietario com decisao duvida.'
        ELSE E'NAO DA PARA SABER DE QUAL VISITA ele fala. Pergunte, com educacao, qual destas:\n' || linhas END;
    END IF;
    SELECT * INTO v FROM nai_visita WHERE id = p_visita;
    RETURN 'visita #' || v.id || ' ' || nai_ref_imovel_prop(v.codigo) ||
      '. proprietario: ' || coalesce(nai_vocativo(v.proprietario_nome), 'nome nao informado') ||
      '. horario em discussao: ' || coalesce(nai_quando_humano(v.quando), 'nenhum') ||
      CASE WHEN v.quando_sugerido IS NOT NULL THEN '. horario que ELE sugeriu: ' || nai_quando_humano(v.quando_sugerido) ELSE '' END ||
      '. situacao: ' || nai_status_humano(v) ||
      CASE v.estado
        WHEN 'aguardando_proprietario' THEN '. ESPERANDO DELE: se tem como receber a visita nesse horario.'
        WHEN 'negociando' THEN CASE WHEN v.aguardando = 'proprietario' THEN '. ESPERANDO DELE: outro horario.' ELSE '. ele ja sugeriu outro horario; estamos vendo com o corretor.' END
        WHEN 'aguardando_acesso' THEN '. ESPERANDO DELE: como fica o acesso' ||
             CASE WHEN v.acesso = 'fechadura' THEN ' (a senha da fechadura)'
                  WHEN v.acesso = 'buscar_chave' THEN ' (onde e a partir de que horas pegar a chave)' ELSE '' END || '.'
        ELSE '' END;
  END IF;

  IF p_papel = 'motoboy' THEN
    SELECT string_agg('visita #' || x.id || ' · ' || nai_ref_imovel(x.codigo) || ' · ' || nai_hora_exata(x.quando) ||
                      ' · ' || CASE WHEN x.moto_ok_em IS NULL THEN 'ESPERANDO ELE CONFIRMAR' ELSE 'ele ja confirmou' END,
                      E'\n' ORDER BY x.quando)
      INTO linhas FROM nai_visita x
     WHERE nai_visita_aberta(x.estado) AND x.estado IN ('aguardando_motoboy', 'confirmada')
       AND (x.motoboy_id = p_contato OR p_teste);
    RETURN coalesce(E'visitas do Fernando:\n' || linhas, 'o Fernando nao tem visita pendente.') ||
           CASE WHEN p_visita IS NOT NULL THEN E'\nele esta respondendo sobre a visita #' || p_visita || '.' ELSE '' END;
  END IF;
  RETURN NULL;
END;
$$;

-- ------------------------------------------------------------ abrir turno
-- O CABECALHO. Chamado uma vez por lote de mensagens. Tudo que o fluxo faz
-- depois le daqui: quem e, que papel, qual visita, qual memoria.
CREATE OR REPLACE FUNCTION nai_abrir_turno(p_tel text, p_nome text, p_texto text, p_citado_id text, p_ids bigint[])
RETURNS jsonb LANGUAGE plpgsql AS $$
DECLARE
  v_chave   text := nai_chave(p_tel);
  v_modo    text := nai_cfg('modo', 'desligado');
  v_teste   boolean;
  v_contato bigint;
  v_papel   text := 'corretor';
  v_visita  bigint;
  v_texto   text := coalesce(p_texto, '');
  v_m       text[];
  v_cit     record;
  v_n       int;
  v_turno   bigint;
  v_aprov   boolean;
  v_prim    boolean;
  v_pausado boolean;
  v_tel_lid text;
BEGIN
  IF v_chave IS NULL THEN
    RETURN jsonb_build_object('ok', false, 'motivo', 'sem_identificador');
  END IF;
  IF v_modo NOT IN ('teste', 'todos') THEN
    RETURN jsonb_build_object('ok', false, 'motivo', 'nai_desligada');
  END IF;
  v_teste := v_chave = ANY (nai_chaves_teste());
  IF v_modo = 'teste' AND NOT v_teste THEN
    -- Defesa em profundidade: o roteador nao devia ter mandado.
    RETURN jsonb_build_object('ok', false, 'motivo', 'fora_do_teste');
  END IF;

  v_contato := nai_contato_de(p_tel, p_nome);

  -- O TEL ASSUMIU este chat: a mensagem fica gravada (status 'Com o Tel') e
  -- a NAI nao responde. No teste, "T: ..." continua sendo o Tel mandando
  -- comando (e o DEVOLVER precisa passar).
  IF (SELECT humano_assumiu_em FROM nai_contato WHERE id = v_contato) IS NOT NULL
     AND NOT (v_teste AND v_texto ~* '^\s*(t|tel)\s*[:\-–]') THEN
    UPDATE mensagens SET status = 'Com o Tel' WHERE id = ANY (coalesce(p_ids, '{}')) AND status IN ('Recebido', 'Processando');
    RETURN jsonb_build_object('ok', false, 'motivo', 'tel_assumiu', 'contato_id', v_contato);
  END IF;

  IF v_teste THEN
    -- No teste, o mesmo numero faz todos os papeis. O papel vem da MARCACAO
    -- (ele respondeu marcando a mensagem que iria para o proprietario) ou
    -- do prefixo P: / M: / T:. Sem nada disso, e corretor.
    IF nullif(p_citado_id, '') IS NOT NULL THEN
      SELECT s.papel_destino, s.visita_id INTO v_cit
        FROM nai_saida s WHERE s.message_id = p_citado_id AND s.redirecionado LIMIT 1;
      IF v_cit.papel_destino IN ('proprietario', 'motoboy', 'tel') THEN
        v_papel := v_cit.papel_destino; v_visita := v_cit.visita_id;
      END IF;
    END IF;
    v_m := regexp_match(v_texto, '^\s*(p|prop|propriet[aá]ri[oa]|m|moto|motoboy|fernando|t|tel)\s*[:\-–]\s*(.*)$', 'is');
    IF v_m IS NOT NULL THEN
      v_texto := v_m[2];
      IF v_papel = 'corretor' THEN
        v_papel := CASE WHEN lower(v_m[1]) ~ '^p' THEN 'proprietario'
                        WHEN lower(v_m[1]) ~ '^(m|f)' THEN 'motoboy'
                        ELSE 'tel' END;
      END IF;
    END IF;
    -- O NUMERO DO TEL no teste (13/09): comando da NAI (VISITAS, VISITA N, ACESSO,
    -- ASSUMIR, DEVOLVER) sem o prefixo T: tambem e o Tel. Conversa normal dele
    -- continua sendo corretor -- e assim que ele testa.
    IF v_papel = 'corretor' AND v_chave = nai_chave(nai_cfg('tel_telefone')) AND nai_e_comando_tel(v_texto) THEN
      v_papel := 'tel';
    END IF;
    IF v_papel IN ('proprietario', 'motoboy') AND v_visita IS NULL THEN
      -- A unica visita esperando esse papel. Mais de uma = pergunta.
      SELECT count(*), min(x.id) INTO v_n, v_visita FROM nai_visita x
       WHERE nai_visita_aberta(x.estado) AND x.aguardando = v_papel;
      IF v_n <> 1 THEN
        SELECT count(*), min(x.id) INTO v_n, v_visita FROM nai_visita x
         WHERE nai_visita_aberta(x.estado)
           AND (v_papel = 'proprietario' AND x.proprietario_id IS NOT NULL
             OR v_papel = 'motoboy' AND x.estado IN ('aguardando_motoboy', 'confirmada'));
        IF v_n <> 1 THEN v_visita := NULL; END IF;
      END IF;
    END IF;
  ELSE
    IF v_chave = nai_chave(nai_cfg('tel_telefone')) THEN
      v_papel := 'tel';
    ELSIF nai_e_motoboy(v_chave) THEN
      v_papel := 'motoboy';
    ELSIF EXISTS (SELECT 1 FROM nai_visita x WHERE x.proprietario_id = v_contato AND nai_visita_aberta(x.estado)) THEN
      v_papel := 'proprietario';
    END IF;
    IF v_papel IN ('proprietario', 'motoboy') THEN
      -- Qual visita: pela mensagem marcada; senao, a unica aberta dele.
      IF nullif(p_citado_id, '') IS NOT NULL THEN
        SELECT s.visita_id INTO v_visita FROM nai_saida s
         WHERE s.message_id = p_citado_id AND s.contato_id = v_contato AND s.visita_id IS NOT NULL LIMIT 1;
      END IF;
      IF v_visita IS NULL THEN
        SELECT count(*), min(x.id) INTO v_n, v_visita FROM nai_visita x
         WHERE nai_visita_aberta(x.estado)
           AND ((v_papel = 'proprietario' AND x.proprietario_id = v_contato)
             OR (v_papel = 'motoboy' AND x.motoboy_id = v_contato AND x.estado IN ('aguardando_motoboy', 'confirmada')));
        IF v_n <> 1 THEN v_visita := NULL; END IF;
      END IF;
    END IF;
  END IF;

  -- Corretor aprovado? Teste = sim. @lid: so pelo mapeamento ja gravado,
  -- e SO para aprovar -- a conversa continua sendo a do @lid.
  IF v_teste THEN
    v_aprov := true;
  ELSE
    IF v_chave ~ '^lid:' THEN
      SELECT telefone INTO v_tel_lid FROM identidade_lid WHERE lid = p_tel;
    END IF;
    v_aprov := EXISTS (SELECT 1 FROM corretores c
                        WHERE c.aprovado AND c.ativo
                          AND nai_chave(c.telefone) = coalesce(nai_chave(v_tel_lid), v_chave));
  END IF;
  v_prim := NOT EXISTS (SELECT 1 FROM mensagens m
                         WHERE m.telefone = p_tel AND m.direcao = 'recebida'
                           AND NOT (m.id = ANY (coalesce(p_ids, '{}'))));
  -- A pausa geral da Nay (config.atendimento_pausado) vale para a NAI tambem --
  -- menos para o numero de teste, do mesmo jeito que a Nay antiga isenta o Tel.
  v_pausado := (NOT v_teste AND coalesce((SELECT valor = 'sim' FROM config WHERE chave = 'atendimento_pausado'), false))
               OR nai_cfg('pausada', 'sim') <> 'nao';

  INSERT INTO nai_turno (contato_id, papel, visita_id, teste, texto, msg_ids)
       VALUES (v_contato, v_papel, v_visita, v_teste, v_texto, p_ids)
  RETURNING id INTO v_turno;

  -- Registra que o proprietario / Fernando respondeu (para as cobrancas).
  IF v_papel = 'proprietario' THEN
    UPDATE nai_visita SET ult_resp_prop_em = now(), atualizado_em = now()
     WHERE (id = v_visita) OR (v_visita IS NULL AND proprietario_id = v_contato AND nai_visita_aberta(estado));
  ELSIF v_papel = 'motoboy' AND v_visita IS NOT NULL THEN
    UPDATE nai_visita SET ult_resp_moto_em = now(), atualizado_em = now() WHERE id = v_visita;
  END IF;

  RETURN jsonb_build_object(
    'ok', true,
    'turno_id', v_turno,
    'contato_id', v_contato,
    'chave', v_chave,
    'telefone', (SELECT telefone FROM nai_contato WHERE id = v_contato),
    'papel', v_papel,
    'visita_id', v_visita,
    'teste', v_teste,
    'modo', v_modo,
    'texto', v_texto,
    'aprovado', v_aprov,
    'primeira_vez', v_prim,
    'pausado', v_pausado,
    -- "3500" depois de "qual a faixa de preco?" e VALOR, nao codigo (13/09).
    'esperando_valor', nai_esperando_valor(v_contato),
    'memoria', 'nai:' || v_papel || ':' || v_contato || coalesce(':v' || v_visita, ''),
    -- O PROMPT VEM DO BANCO (Tel, 15/09): editar no painel vale na mensagem
    -- seguinte, sem import nem reinicio. Vazio aqui = o fluxo usa o texto que
    -- ja esta dentro dele, entao nada quebra.
    'prompt', nai_prompt_de(CASE WHEN v_papel = 'tel' THEN 'corretor' ELSE v_papel END),
    'contexto', nai_contexto(v_papel, v_contato, v_visita, v_teste),
    -- Como chamar a pessoa: Sr./Sra. + primeiro nome (Tel, 12/09 -- o mesmo
    -- tom da captacao). Quando o nome nao diz o genero, vem so o primeiro
    -- nome: melhor sem tratamento do que chamar uma corretora de "Sr.".
    'vocativo', CASE WHEN v_papel = 'proprietario'
                     THEN nai_vocativo((SELECT proprietario_nome FROM nai_visita WHERE id = v_visita))
                     WHEN v_papel = 'corretor'
                     THEN nai_vocativo(coalesce((SELECT nome_completo FROM nai_contato WHERE id = v_contato),
                                                nay_nome_de_pessoa((SELECT nome_whatsapp FROM nai_contato WHERE id = v_contato)))) END
  );
END;
$$;

CREATE OR REPLACE FUNCTION nai_fechar_turno(p_turno bigint)
RETURNS bigint LANGUAGE plpgsql AS $$
DECLARE v_ids bigint[];
BEGIN
  UPDATE nai_turno SET fechado_em = coalesce(fechado_em, now()) WHERE id = p_turno RETURNING msg_ids INTO v_ids;
  UPDATE mensagens SET status = 'Respondido' WHERE id = ANY (coalesce(v_ids, '{}')) AND status = 'Processando';
  RETURN p_turno;
END;
$$;
