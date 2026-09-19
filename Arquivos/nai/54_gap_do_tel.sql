-- =====================================================================
-- NAI -- 54: o gap de meia hora depois da mensagem do Tel (Tel, 16/09/2026)
--
-- Ele: "poe um gap de uma hora para quando o Tel mandar mensagem; toda
-- mensagem que chegar no corretor dentro de uma hora e ignorada, e essa hora e
-- a cada mensagem que o Tel envia manualmente" -- e, logo depois: "pode ser
-- meia hora".
--
-- ATE AQUI a mensagem digitada por ele parava a conversa PARA SEMPRE: so o
-- comando DEVOLVER trazia a Nay de volta. Agora para por meia hora, contada da
-- ULTIMA mensagem dele.
--
-- TRES COISAS MUDAM
--
-- 1. `nai_tel_com_a_conversa` (nova) e a unica leitura da pausa. A porta, a
--    abertura do turno e a caixa de saida tinham cada uma o seu
--    `humano_assumiu_em IS NOT NULL`; com uma janela de tempo no meio, tres
--    copias viravam tres jeitos de discordar -- a porta liberando a conversa e
--    a saida bloqueando a resposta.
--
-- 2. `nai_tel_assumiu` passa a gravar `now()` a cada mensagem, em vez de
--    guardar so a primeira. E o que faz o gap recomecar a cada mensagem dele.
--
-- 3. Escalada NAO expira. "Duvida fora da base", midia e visita continuam com
--    o Tel ate o DEVOLVER, como ele decidiu em 15/09. So o motivo 'o Tel
--    escreveu pelo celular' tem prazo.
--
-- O QUE ISSO FAZ HOJE, medido antes de aplicar: 65 conversas estao paradas por
-- mensagem dele e 9 por escalada. Das 65, 64 tem carimbo de mais de meia hora e
-- voltam a ser julgadas pela porta. Nenhuma delas tem `liberado_em`, entao
-- nenhuma volta a ser atendida de graca: sao conversas antigas, e conversa
-- antiga continua sendo do Tel a nao ser que a pessoa peca fotos de um imovel
-- ou peca imoveis -- o desenho dele de 15/09, intacto.
--
-- O GAP E CONFIGURAVEL: `nai_config.gap_tel_min`, em minutos. Hoje: 30.
--
-- Gerado por `scratchpad/patch54.py` a partir do que estava NO BANCO.
-- =====================================================================

INSERT INTO nai_config (chave, valor)
VALUES ('gap_tel_min', '30')
ON CONFLICT (chave) DO NOTHING;

CREATE OR REPLACE FUNCTION public.nai_tel_com_a_conversa(p_contato bigint)
 RETURNS boolean
 LANGUAGE plpgsql
 STABLE
AS $function$
DECLARE
  v_em     timestamptz;
  v_motivo text;
  v_gap    int;
BEGIN
  IF p_contato IS NULL THEN RETURN false; END IF;
  SELECT humano_assumiu_em, humano_motivo INTO v_em, v_motivo
    FROM nai_contato WHERE id = p_contato;
  IF v_em IS NULL THEN RETURN false; END IF;

  -- O GAP (Tel, 16/09). Ele: "poe um gap de uma hora para quando o Tel mandar
  -- mensagem; toda mensagem que chegar no corretor dentro de uma hora e
  -- ignorada, e essa hora e a cada mensagem que o Tel envia manualmente" -- e
  -- logo depois: "pode ser meia hora". Meia hora, entao.
  --
  -- So a mensagem digitada por ele expira. A comparacao e pela frase exata que
  -- `nai_tel_assumiu` grava -- e de proposito: motivo que eu nao conheca cai no
  -- ELSE e continua parado, que e como era antes. Errar para o lado de ficar
  -- calada e barato; errar para o outro e a Nay falando por cima do Tel.
  IF v_motivo = 'o Tel escreveu pelo celular' THEN
    v_gap := greatest(nai_cfg_int('gap_tel_min', 30), 0);
    RETURN v_em > now() - make_interval(mins => v_gap);
  END IF;

  -- Escalada (duvida fora da base, midia, visita): segue com o Tel ate ele
  -- mandar DEVOLVER. Isso ele decidiu em 15/09 e nao muda aqui.
  RETURN true;
END;
$function$;

CREATE OR REPLACE FUNCTION public.nai_tel_assumiu(p_tel text, p_message_id text, p_texto text)
 RETURNS jsonb
 LANGUAGE plpgsql
AS $function$
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
  -- O RELOGIO REINICIA A CADA MENSAGEM (Tel, 16/09): "essa hora e a cada
  -- mensagem que o Tel envia manualmente". O `coalesce` guardava o primeiro
  -- carimbo e nunca mais mexia: com a janela de tempo, uma conversa em que ele
  -- digitou a manha toda voltaria para a Nay no meio dela.
  --
  -- O MOTIVO continua com coalesce. Se a conversa ja estava escalada, ela
  -- segue escalada -- o carimbo novo nao a faz expirar, porque quem expira e
  -- so o motivo 'o Tel escreveu pelo celular'.
  UPDATE nai_contato SET humano_assumiu_em = now(),
                         humano_motivo = coalesce(humano_motivo, 'o Tel escreveu pelo celular')
   WHERE chave = v_chave;
  RETURN jsonb_build_object('ok', true, 'tel_assumiu', true);
END;
$function$;

CREATE OR REPLACE FUNCTION public.nai_deve_atender(p_telefone text, p_texto text, p_codigo_citado integer DEFAULT NULL::integer)
 RETURNS TABLE(atende boolean, motivo text)
 LANGUAGE plpgsql
AS $function$
DECLARE
  v_chave  text := nai_chave(p_telefone);
  v_desde  timestamptz;
  v_antigo boolean;
  v_lib    timestamptz;
  v_humano timestamptz;
  v_id     bigint;
  v_cod    boolean;
BEGIN
  IF lower(coalesce(nai_cfg('regra_publico', 'nao'), 'nao')) <> 'sim' THEN
    RETURN QUERY SELECT true, 'regra desligada'::text; RETURN;
  END IF;
  v_desde := nullif(btrim(nai_cfg('regra_publico_desde', '')), '')::timestamptz;
  IF v_desde IS NULL THEN
    RETURN QUERY SELECT true, 'sem carimbo: regra nao vale'::text; RETURN;
  END IF;

  SELECT c.id, c.liberado_em, c.humano_assumiu_em INTO v_id, v_lib, v_humano
    FROM nai_contato c WHERE c.chave = v_chave;

  -- MENSAGEM POR HUMANO PAUSA (Tel, 15/09), AGORA POR MEIA HORA (Tel, 16/09).
  -- Vale antes de tudo. Passado o gap, a conversa nao volta para ela de
  -- presente: volta a ser julgada pelas regras abaixo, como qualquer outra.
  -- Conversa antiga continua sendo do Tel, a nao ser que a pessoa peca fotos
  -- de um imovel ou peca imoveis -- que e o desenho dele desde 15/09.
  IF nai_tel_com_a_conversa(v_id) THEN
    RETURN QUERY SELECT false,
      CASE WHEN (SELECT c2.humano_motivo FROM nai_contato c2 WHERE c2.id = v_id)
                = 'o Tel escreveu pelo celular'
           THEN 'o Tel escreveu ha menos de ' || greatest(nai_cfg_int('gap_tel_min', 30), 0) || ' min'
           ELSE 'o Tel assumiu essa conversa' END;
    RETURN;
  END IF;

  IF v_lib IS NOT NULL THEN
    RETURN QUERY SELECT true, 'conversa ja liberada'::text; RETURN;
  END IF;

  -- CONVERSA QUE ELA JA ATENDEU e dela ate o Tel digitar. Sem isto a porta
  -- julgava cada mensagem sozinha, e "pode mandar" -- resposta de quem esta
  -- negociando -- virava "assunto que nao e de corretor".
  IF v_id IS NOT NULL AND EXISTS (
       SELECT 1 FROM nai_saida s
        WHERE s.contato_id = v_id
          AND s.papel_destino IN ('turno', 'corretor')
          AND s.estado IN ('enviado', 'enviando', 'simulado')
          AND s.criado_em > v_desde) THEN
    RETURN QUERY SELECT true, 'conversa que ela ja estava atendendo'::text; RETURN;
  END IF;

  -- MARCOU UMA MENSAGEM (o card do grupo, o imovel que ela mandou): e imovel,
  -- seja o que for que ele tenha escrito junto. E o filtro que o Tel deu.
  IF p_codigo_citado IS NOT NULL THEN
    RETURN QUERY SELECT true, 'marcou uma mensagem de imovel'::text; RETURN;
  END IF;

  SELECT EXISTS (SELECT 1 FROM mensagens m
                  WHERE nai_chave(m.telefone) = v_chave AND m.criada_em < v_desde)
      OR EXISTS (SELECT 1 FROM nai_turno t JOIN nai_contato c ON c.id = t.contato_id
                  WHERE c.chave = v_chave AND t.criado_em < v_desde)
    INTO v_antigo;

  IF NOT v_antigo THEN
    IF nai_assunto_de_corretor(p_texto)
       OR (nai_pedido_de_perfil(p_texto)->>'e_pedido')::boolean THEN
      RETURN QUERY SELECT true, 'contato novo falando de imovel'::text; RETURN;
    END IF;
    RETURN QUERY SELECT false, 'contato novo, assunto que nao e de corretor'::text; RETURN;
  END IF;

  v_cod := EXISTS (SELECT 1 FROM unnest(coalesce(nay_codigos_citados(coalesce(p_texto, '')), '{}'::text[])) x
                    WHERE x ~ '^[0-9]{3,5}$');

  IF nai_pede_foto(p_texto) AND v_cod THEN
    UPDATE nai_contato SET liberado_em = now(),
                           liberado_motivo = left('pediu foto: ' || coalesce(p_texto, ''), 200)
     WHERE chave = v_chave;
    RETURN QUERY SELECT true, 'pediu foto de um imovel'::text; RETURN;
  END IF;

  IF (nai_pedido_de_perfil(p_texto)->>'e_pedido')::boolean THEN
    UPDATE nai_contato SET liberado_em = now(),
                           liberado_motivo = left('pediu imoveis: ' || coalesce(p_texto, ''), 200)
     WHERE chave = v_chave;
    RETURN QUERY SELECT true, 'pediu imoveis'::text; RETURN;
  END IF;

  IF nai_pede_foto(p_texto) THEN
    RETURN QUERY SELECT false, 'pediu foto mas nao da para saber o imovel'::text; RETURN;
  END IF;
  RETURN QUERY SELECT false, 'conversa que ja existia: quem responde e o Tel'::text;
END;
$function$;

CREATE OR REPLACE FUNCTION public.nai_abrir_turno(p_tel text, p_nome text, p_texto text, p_citado_id text, p_ids bigint[])
 RETURNS jsonb
 LANGUAGE plpgsql
AS $function$
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
  v_porta   record;   -- a porta: atende essa mensagem?
BEGIN
  IF v_chave IS NULL THEN
    RETURN jsonb_build_object('ok', false, 'motivo', 'sem_identificador');
  END IF;
  IF v_modo NOT IN ('teste', 'todos') THEN
    RETURN jsonb_build_object('ok', false, 'motivo', 'nai_desligada');
  END IF;
  v_teste := v_chave = ANY (nai_chaves_teste());
  -- O COMANDO DELES PASSA MESMO EM MODO TESTE (Tel, 15/09: "tel mandou agenda
  -- de visitas e ela n respondeu"). O numero do Tel nao esta em
  -- `numeros_teste` -- so o do Pedro esta --, entao o turno nem abria e o
  -- comando morria calado. A excecao e so para o COMANDO: conversa normal
  -- desses numeros continua caindo na mesma porta de antes.
  IF v_modo = 'teste' AND NOT v_teste
     AND nai_pode_comandar(v_chave)
     AND (nai_e_comando_tel(v_texto) OR nai_e_comando_extra(v_texto)) THEN
    NULL;   -- deixa passar
  ELSIF v_modo = 'teste' AND NOT v_teste THEN
    -- Defesa em profundidade: o roteador nao devia ter mandado.
    RETURN jsonb_build_object('ok', false, 'motivo', 'fora_do_teste');
  END IF;

  v_contato := nai_contato_de(p_tel, p_nome);

  -- O TEL ASSUMIU este chat: a mensagem fica gravada (status 'Com o Tel') e
  -- a NAI nao responde. No teste, "T: ..." continua sendo o Tel mandando
  -- comando (e o DEVOLVER precisa passar).
  -- 16/09: a leitura da pausa passou a ser uma so, em `nai_tel_com_a_conversa`
  -- -- que sabe do gap. Antes eram tres copias de
  -- `humano_assumiu_em IS NOT NULL`, e com a janela entrando elas iam divergir.
  IF nai_tel_com_a_conversa(v_contato)
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
    v_m := regexp_match(v_texto, ('^\s*(p|prop|propriet[aá]ri[oa]|m|moto|motoboy|fernando|'
                          -- as DUAS grafias do nome: quem digita "André:" e quem digita
                          -- "Andre:" tem que cair no mesmo lugar. O texto NAO passa por
                          -- unaccent -- ele e capturado aqui e vira a mensagem.
                          || lower(nai_acompanhante()) || '|' || lower(unaccent(nai_acompanhante()))
                          || '|t|tel)\s*[:\-–]\s*(.*)$'), 'is');
    IF v_m IS NOT NULL THEN
      v_texto := v_m[2];
      IF v_papel = 'corretor' THEN
        -- O NOME DO ACOMPANHANTE tambem manda para o motoboy (Tel, 16/09).
        -- Sem esta linha, "André: pode ser" caia como TEL: a decisao testava
        -- so as iniciais m e f (motoboy e Fernando), e "andre" nao comeca com
        -- nenhuma das duas. Medido antes de aplicar.
        v_papel := CASE WHEN lower(v_m[1]) ~ '^p' THEN 'proprietario'
                        WHEN lower(v_m[1]) ~ '^(m|f)' THEN 'motoboy'
                        WHEN lower(unaccent(v_m[1])) = lower(unaccent(nai_acompanhante()))
                          THEN 'motoboy'
                        ELSE 'tel' END;
      END IF;
    END IF;
    -- O NUMERO DO TEL no teste (13/09): comando da NAI (VISITAS, VISITA N, ACESSO,
    -- ASSUMIR, DEVOLVER) sem o prefixo T: tambem e o Tel. Conversa normal dele
    -- continua sendo corretor -- e assim que ele testa.
    IF v_papel = 'corretor' AND v_chave = nai_chave(nai_cfg('tel_telefone')) AND nai_e_comando_tel(v_texto) THEN
      v_papel := 'tel';
    END IF;
    -- AGENDA DE VISITAS (Tel, 15/09): "quero que o tel e eu quando digitar no
    -- pv dela Agenda de visitas". Vale para os telefones de
    -- `comando_telefones`, e SO para esse comando -- o resto da conversa deles
    -- continua caindo onde sempre caiu.
    IF v_papel = 'corretor' AND nai_e_comando_extra(v_texto) AND nai_pode_comandar(v_chave) THEN
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
    IF v_chave = nai_chave(nai_cfg('tel_telefone'))
       OR (nai_e_comando_extra(v_texto) AND nai_pode_comandar(v_chave)) THEN
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

  -- A PORTA (Tel, 15/09): quem ela atende quando a regra publica esta ligada.
  -- Com a regra desligada devolve atende=true e o roteador segue com o
  -- porteiro de sempre -- entao ligar este campo nao muda nada sozinho.
  -- O IMOVEL DA MENSAGEM MARCADA vai junto (Tel, 15/09): quem responde o card
  -- do grupo esta falando de imovel, escreva o que escrever -- ate "Boa
  -- noite!". `nay_imovel_da_citacao` ja resolve o card do grupo, o card que ela
  -- mandou e o envio do publicador.
  SELECT * INTO v_porta FROM nai_deve_atender(
    p_tel, v_texto,
    nullif(regexp_replace(coalesce(nay_imovel_da_citacao(p_citado_id), ''), '\D', '', 'g'), '')::int);
  -- A pausa geral da Nay (config.atendimento_pausado) vale para a NAI tambem --
  -- menos para o numero de teste, do mesmo jeito que a Nay antiga isenta o Tel.
  -- A PAUSA E SO A DELA (Tel, 15/09, na revisao depois de ativar).
  --
  -- Ate aqui a pausa da Nay ANTIGA (`config.atendimento_pausado`) tambem calava
  -- a NAI, menos para o numero de teste. Enquanto ela era so teste isso nunca
  -- aparecia -- o unico que falava com ela era o Pedro, e ele e "teste". Ao
  -- abrir para todos, as 14:12, TODO MUNDO caiu naquela pausa: 133 mensagens
  -- entraram e nenhuma foi respondida, e nao havia erro nenhum para ver.
  --
  -- A Nay antiga esta pausada desde agosto, de proposito e para sempre. Ela nao
  -- pode calar um atendimento que e outro produto, com a propria chave e o
  -- proprio botao no painel.
  v_pausado := nai_cfg('pausada', 'sim') <> 'nao';

  INSERT INTO nai_turno (contato_id, papel, visita_id, teste, texto, msg_ids, porta)
       VALUES (v_contato, v_papel, v_visita, v_teste, v_texto, p_ids, v_porta.motivo)
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
    -- ATENDE: NULL quando a regra publica esta desligada (o roteador decide
    -- como sempre decidiu); true/false quando ela manda. `porta` diz o motivo,
    -- e e ele que explica um silencio depois.
    'atende', CASE WHEN lower(coalesce(nai_cfg('regra_publico', 'nao'), 'nao')) = 'sim'
                   THEN v_porta.atende END,
    'porta', v_porta.motivo,
    -- SO CUMPRIMENTOU (Tel, 15/09): "ela tem que responder o cumprimento e
    -- aguardar nesse caso". Quem chega dizendo so "boa noite" ainda nao disse a
    -- que veio -- despejar o roteiro em cima dele e responder outra pergunta.
    'so_cumprimento', nai_so_cumprimentou(v_texto),
    'primeira_vez', v_prim,
    'pausado', v_pausado,
    -- "3500" depois de "qual a faixa de preco?" e VALOR, nao codigo (13/09).
    'esperando_valor', nai_esperando_valor(v_contato),
    'memoria', 'nai:' || v_papel || ':' || v_contato || coalesce(':v' || v_visita, ''),
    -- O PROMPT VEM DO BANCO (Tel, 15/09): editar no painel vale na mensagem
    -- seguinte, sem import nem reinicio. Vazio aqui = o fluxo usa o texto que
    -- ja esta dentro dele, entao nada quebra.
    'prompt', nai_prompt_de(CASE WHEN v_papel = 'tel' THEN 'corretor' ELSE v_papel END),
    -- COMANDO DA NAI: o roteador do fluxo lia uma COPIA da regex de
    -- `nai_e_comando_tel` dentro do JS, e as duas se afastariam na primeira
    -- mudanca. Agora quem responde e o banco, e o JS so le este campo.
    'comando_nai', (v_papel = 'tel' AND (nai_e_comando_tel(v_texto) OR nai_e_comando_extra(v_texto))),
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
$function$;

CREATE OR REPLACE FUNCTION public.nai_liberar_saida(p_turno bigint)
 RETURNS TABLE(id bigint, rota text, telefone text, chave_esperada text, corpo jsonb, codigo integer, papel text, redirecionado boolean)
 LANGUAGE plpgsql
AS $function$
#variable_conflict use_column
DECLARE
  r          record;
  v_modo     text := nai_cfg('modo', 'desligado');
  v_pausada  boolean := nai_cfg('pausada', 'sim') <> 'nao';
  v_simulado boolean := nai_cfg('envio_simulado', 'nao') = 'sim';
  v_testes   text[] := nai_chaves_teste();
  v_destino  text := nai_fone_envio(nai_cfg('telefone_teste_destino', ''));
  v_tel      text;
  v_texto    text;
  v_chave_c  text;
  v_bloq     text;
  v_redir    boolean;
  v_papel_t  text;
  v_etiqueta text;
  v_nome     text;
  v_cmd      boolean;   -- e a resposta a um comando de quem pode comandar?
BEGIN
  FOR r IN
    SELECT s.* FROM nai_saida s
     WHERE s.estado = 'pendente'
       AND s.enviar_apos <= now()
       AND ((p_turno IS NOT NULL AND s.turno_id = p_turno)
         OR (p_turno IS NULL AND (s.turno_id IS NULL OR s.criado_em < now() - interval '3 minutes')
             AND (nai_dentro_da_janela() OR s.papel_destino = 'tel')))
     ORDER BY s.id
     LIMIT 80
     FOR UPDATE SKIP LOCKED
  LOOP
    v_bloq := NULL; v_redir := false; v_texto := r.texto; v_etiqueta := NULL;
    SELECT k.chave, k.telefone, coalesce(k.nome_completo, k.nome_whatsapp)
      INTO v_chave_c, v_tel, v_nome FROM nai_contato k WHERE k.id = r.contato_id;

    -- RESPOSTA A COMANDO: volta para quem mandou, sempre. Nao e redirecionada
    -- no modo teste (senao a resposta do Tel cairia no chat do Pedro) e nao e
    -- barrada pela pausa (senao PARAR ATENDIMENTO ficaria sem confirmacao --
    -- medido em 15/09: saiu 'bloqueado' com motivo nai_pausada, e ele nao
    -- soube se tinha funcionado). Vale so para o texto que a propria funcao de
    -- comando escreveu, indo para um telefone de `comando_telefones`.
    v_cmd := r.motivo = 'comando_tel' AND r.papel_destino = 'turno'
             AND nai_pode_comandar(v_chave_c);

    IF v_modo NOT IN ('teste', 'todos') THEN
      v_bloq := 'nai_desligada';
    ELSIF v_pausada AND NOT v_cmd THEN
      v_bloq := 'nai_pausada';
    ELSIF v_chave_c IS DISTINCT FROM r.chave_destino THEN
      v_bloq := 'contato_mudou';
    ELSIF r.papel_destino <> 'tel'
          -- 16/09: mesma leitura da porta e da abertura do turno.
          AND nai_tel_com_a_conversa(r.contato_id)
          AND NOT (r.papel_destino = 'turno' AND (SELECT t2.papel FROM nai_turno t2 WHERE t2.id = r.turno_id) = 'tel') THEN
      -- O TEL ASSUMIU esse chat: a NAI nao manda mais nada para essa pessoa
      -- (so a resposta a um comando do proprio Tel passa).
      v_bloq := 'tel_assumiu';
    ELSIF r.tipo = 'imagem'
          AND NOT EXISTS (SELECT 1 FROM imovel_fotos f WHERE f.codigo = r.codigo AND f.url = r.imagem_url)
          -- A COLAGEM tambem e imagem legitima daquele imovel (Tel, 12/09): ela
          -- nao esta em `imovel_fotos` -- e montada por nos e mora em
          -- `imovel_colagem`. Sem esta linha, toda colagem sairia bloqueada
          -- como "foto_nao_confere", que e a trava contra mandar a foto de um
          -- imovel no card de outro.
          AND NOT EXISTS (SELECT 1 FROM imovel_colagem c WHERE c.codigo = r.codigo AND c.url = r.imagem_url) THEN
      v_bloq := 'foto_nao_confere';
    -- REPETIDA: o mesmo texto para a mesma pessoa em 10 minutos não sai de novo.
    -- EXCEÇÃO (Tel, 14/09): as frases do "depois das fotos" são passo do
    -- roteiro, não repetição do modelo. Ela mandou a sugestão de visita às
    -- 20:12 e as fotos às 20:17 -- e "Ou se tiver alguma dúvida ou quiser mais
    -- imóveis..." saiu BLOQUEADA como repetida, logo depois das fotos.
    -- ...e só conta o que saiu DEPOIS do marco de conversa zerada (14/09): o
    -- pré-voo mandou as frases da sugestão em modo simulado, a conversa foi
    -- zerada, e no teste seguinte a mesma sugestão saiu BARRADA como repetida.
    -- Conversa zerada é conversa nova, também para esta trava.
    -- ...e mensagem de VISITA só é repetida se for da MESMA visita (14/09): dois
    -- pedidos de visita seguidos ao mesmo proprietário, com o mesmo texto, são
    -- duas visitas -- o segundo saía barrado e o proprietário nunca sabia.
    -- ...e RESPOSTA A COMANDO nunca e repetida (Tel, 15/09): ele mandou
    -- "agenda de visitas" duas vezes, a agenda estava igual, e a segunda saiu
    -- BLOQUEADA como repetida -- que e exatamente o sintoma de "ela nao
    -- respondeu" que ele relatou. Comando pedido duas vezes e respondido duas
    -- vezes.
    ELSIF r.tipo = 'texto' AND NOT v_cmd AND coalesce(r.motivo, '') <> 'depois_das_fotos' AND EXISTS (
            SELECT 1 FROM nai_saida s2
             WHERE s2.contato_id = r.contato_id AND s2.estado IN ('enviado', 'simulado')
               AND s2.tipo = 'texto' AND s2.texto = r.texto
               AND s2.visita_id IS NOT DISTINCT FROM r.visita_id
               AND s2.enviado_em > greatest(now() - interval '10 minutes',
                     coalesce((SELECT k3.zerado_em FROM nai_contato k3 WHERE k3.id = r.contato_id), '-infinity'::timestamptz))) THEN
      v_bloq := 'repetida';
    ELSIF r.tipo = 'imagem' AND EXISTS (
            SELECT 1 FROM nai_saida s2
             WHERE s2.contato_id = r.contato_id AND s2.estado IN ('enviado', 'simulado')
               AND s2.tipo = 'imagem' AND s2.imagem_url = r.imagem_url
               AND s2.enviado_em > greatest(now() - interval '10 minutes',
                     coalesce((SELECT k3.zerado_em FROM nai_contato k3 WHERE k3.id = r.contato_id), '-infinity'::timestamptz))) THEN
      v_bloq := 'repetida';
    END IF;

    -- MODO TESTE: o que iria para proprietario, Fernando ou Tel vai para o
    -- numero de teste, com a etiqueta de para quem iria.
    IF v_bloq IS NULL AND v_modo = 'teste' AND NOT v_cmd THEN
      IF r.papel_destino IN ('proprietario', 'motoboy', 'tel') THEN
        v_redir := true;
        v_etiqueta := '🧪 TESTE · iria para o ' ||
          CASE r.papel_destino WHEN 'proprietario' THEN 'PROPRIETÁRIO' WHEN 'motoboy' THEN '' || nai_acompanhante_maiusculo() || ' (motoboy)' ELSE 'TEL' END ||
          coalesce(' ' || v_nome, '') ||
          coalesce(' · visita #' || r.visita_id, '') || E'\n' ||
          CASE r.papel_destino
            WHEN 'proprietario' THEN 'Para responder como proprietário: MARQUE esta mensagem, ou comece com P:'
            WHEN 'motoboy' THEN 'Para responder como ' || nai_acompanhante() || ': MARQUE esta mensagem, ou comece com M:'
            ELSE 'Para responder como Tel: comece com T:' END || E'\n\n';
        v_tel := v_destino;
      ELSIF r.papel_destino = 'turno' THEN
        SELECT t.papel INTO v_papel_t FROM nai_turno t WHERE t.id = r.turno_id;
        IF v_papel_t IN ('proprietario', 'motoboy', 'tel') THEN
          v_etiqueta := '🧪 (resposta ao ' ||
            CASE v_papel_t WHEN 'proprietario' THEN 'PROPRIETÁRIO' WHEN 'motoboy' THEN '' || nai_acompanhante_maiusculo() || '' ELSE 'TEL' END || E')\n';
        END IF;
        -- TODAS AS MENSAGENS NO CHAT DELE (Tel, 13/09: "quero que as mensagens
        -- vao todas para mim, corretores, proprietarios e tal nesse teste"). O
        -- que iria para outro numero -- um corretor simulado, por exemplo --
        -- chega no numero de teste com a etiqueta de para quem iria. Antes isso
        -- morria como 'teste_fora_da_lista' e ele nao via a mensagem.
        IF nai_chave(v_tel) IS DISTINCT FROM nai_chave(v_destino) THEN
          v_redir := true;
          v_etiqueta := coalesce(v_etiqueta, '') || '🧪 TESTE · iria para o ' ||
            CASE coalesce(v_papel_t, 'corretor')
              WHEN 'proprietario' THEN 'PROPRIETÁRIO'
              WHEN 'motoboy' THEN '' || nai_acompanhante_maiusculo() || ' (motoboy)'
              WHEN 'tel' THEN 'TEL'
              ELSE 'CORRETOR' END ||
            coalesce(' ' || v_nome, '') || ' ' || nai_fone_fmt(v_tel) || E'\n\n';
          v_tel := v_destino;
        END IF;
      END IF;
      -- PAREDE DO TESTE: nada sai para numero fora da lista de teste.
      IF NOT (nai_chave(v_tel) = ANY (v_testes)) THEN
        v_bloq := 'teste_fora_da_lista';
      END IF;
    END IF;

    IF v_bloq IS NOT NULL THEN
      UPDATE nai_saida s SET estado = 'bloqueado', bloqueio = v_bloq, telefone_final = v_tel, enviado_em = now()
       WHERE s.id = r.id;
      CONTINUE;
    END IF;

    IF r.tipo = 'texto' AND v_etiqueta IS NOT NULL THEN
      v_texto := v_etiqueta || v_texto;
    END IF;

    IF v_simulado THEN
      UPDATE nai_saida s SET estado = 'simulado', telefone_final = v_tel, redirecionado = v_redir,
                             enviado_em = now(), resposta = jsonb_build_object('texto_final', v_texto)
       WHERE s.id = r.id;
      IF r.visita_id IS NOT NULL AND r.papel_destino = 'proprietario' THEN
        UPDATE nai_visita SET ult_msg_prop_em = now() WHERE nai_visita.id = r.visita_id;
      ELSIF r.visita_id IS NOT NULL AND r.papel_destino = 'motoboy' THEN
        UPDATE nai_visita SET ult_msg_moto_em = now() WHERE nai_visita.id = r.visita_id;
      END IF;
      CONTINUE;
    END IF;

    UPDATE nai_saida s SET estado = 'enviando', telefone_final = v_tel, redirecionado = v_redir
     WHERE s.id = r.id;

    id := r.id;
    rota := CASE r.tipo WHEN 'imagem' THEN 'send-image' ELSE 'send-text' END;
    telefone := v_tel;
    chave_esperada := nai_chave(v_tel);
    corpo := CASE r.tipo
               WHEN 'imagem' THEN jsonb_build_object('phone', v_tel, 'image', r.imagem_url)
               ELSE jsonb_build_object('phone', v_tel, 'message', v_texto) END;
    codigo := r.codigo;
    papel := r.papel_destino;
    redirecionado := v_redir;
    RETURN NEXT;
  END LOOP;
END;
$function$;
