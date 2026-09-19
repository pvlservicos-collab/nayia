-- =====================================================================
-- NAI -- 48: mais de uma solicitacao por conversa (Tel, 16/09/2026)
--
-- Tres pedidos dele que sao o mesmo mecanismo, e a conversa da Martinha mostra
-- os tres de uma vez:
--
--   04:05  ela: "Pode me encaminhar esse por gentileza"
--          Nay: manda o card do 5717 e pergunta "A Sra. quer as fotos?"
--   04:12  ela: "Por favor" / "Esse e casa ?"
--          Nay: "qual desses? / 5717 / nenhum desses"
--
-- (3) "na mesma conversa da Martinha ela perguntou de outro imovel -- e
--     importante que a Nay consiga entender mais de uma solicitacao"
-- (4) "a moca disse por favor e ela nao mandou as fotos"
-- (5) "ela marcou o imovel perguntando se e casa e a Nai nao respondeu, ela
--     listou imoveis e perguntou 'qual desses?'. Pode criar filas diferentes,
--     uma para cada mencao a imovel diferente, como se a cada imovel que o
--     corretor perguntar, vindo do grupo, ela abrisse uma sessao de
--     apresentacao nova."
--
-- O QUE MUDA
--
-- 1. `nai_assuntos_da_mensagem` (nova): quebra a mensagem nos assuntos que ela
--    traz -- por linha, e por pergunta dentro da linha. Card colado devolve
--    vazio, senao as dez linhas do card virariam dez pedidos.
--
-- 2. `nai_contexto_corretor` passa a LER A MENSAGEM ao perguntar qual e o
--    imovel da conversa. Ali ia NULL no lugar do texto, e por isso os dois
--    primeiros criterios de nai_imovel_da_conversa -- o codigo que ELE escreveu
--    agora, e o condominio que ELE chamou pelo nome -- nunca rodavam.
--
-- 3. Imovel citado diferente do que estava em pauta => APRESENTACAO NOVA
--    daquele imovel, em vez de "qual desses?". O anterior continua valendo.
--
-- 4. Mensagem com mais de um assunto => os assuntos vao numerados no cabecalho,
--    com a ordem de responder todos.
--
-- 5. Resposta curta de aceite ("por favor", "sim", "pode mandar") => o
--    cabecalho diz QUAL foi a ultima pergunta dela, e manda cumprir agora.
--
-- Gerado por `scratchpad/patch48.py` a partir do que estava NO BANCO.
-- =====================================================================

CREATE OR REPLACE FUNCTION public.nai_assuntos_da_mensagem(p_texto text)
 RETURNS text[]
 LANGUAGE plpgsql
 IMMUTABLE
AS $function$
DECLARE
  t     text := btrim(coalesce(p_texto, ''));
  linha text;
  parte text;
  saida text[] := '{}';
BEGIN
  IF t = '' THEN RETURN '{}'; END IF;

  -- CARD COLADO NAO E LISTA DE PEDIDOS. O card tem uma dezena de linhas
  -- ("Bairro:", "Codigo: 2014", "Locacao: R$ ...") e contar cada uma como um
  -- assunto faria a Nay achar que ele pediu dez coisas de uma vez.
  IF t ~* 'C[oó]digo:\s*[0-9]{3,5}' AND t ~* '(Bairro:|Loca[cç][aã]o:|Venda:|quartos)' THEN
    RETURN '{}';
  END IF;

  -- Cada linha e um assunto; dentro da linha, cada pergunta tambem e.
  -- "Por favor / Esse e casa ?" sao dois: o sim para a pergunta anterior e uma
  -- pergunta nova sobre outro imovel (Tel, 16/09, conversa da Martinha).
  FOREACH linha IN ARRAY regexp_split_to_array(t, '[\r\n]+') LOOP
    linha := btrim(linha);
    CONTINUE WHEN linha = '';
    IF linha ~ '[?]' THEN
      FOREACH parte IN ARRAY regexp_split_to_array(linha, '(?<=[?])') LOOP
        parte := btrim(parte);
        CONTINUE WHEN length(parte) < 2;
        -- "(Se sim, qual e o valor?" e a continuacao da pergunta de cima, nao
        -- um pedido novo: volta para a parte anterior.
        IF parte ~ '^[(]' AND coalesce(array_length(saida, 1), 0) > 0 THEN
          saida[array_length(saida, 1)] := saida[array_length(saida, 1)] || ' ' || parte;
        ELSE
          saida := saida || parte;
        END IF;
      END LOOP;
    ELSIF length(linha) >= 2 THEN
      saida := saida || linha;
    END IF;
  END LOOP;

  -- CUMPRIMENTO NAO E ASSUNTO. "Bom dia" numa linha so somava um pedido que
  -- nao existe -- e cordialidade, e a Nay ja sabe devolver.
  SELECT coalesce(array_agg(x ORDER BY o), '{}') INTO saida
    FROM unnest(saida) WITH ORDINALITY AS u(x, o)
   WHERE NOT nai_so_cumprimentou(x);

  RETURN saida;
END;
$function$;

CREATE OR REPLACE FUNCTION public.nai_contexto_corretor(p_contato bigint)
 RETURNS text
 LANGUAGE plpgsql
 STABLE
AS $function$
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
  -- A MENSAGEM DELE, lida uma vez so (Tel, 16/09). Ela era buscada de novo em
  -- cada bloco que precisava; agora tres blocos novos tambem precisam.
  v_msg     text;
BEGIN
  SELECT * INTO k FROM nai_contato WHERE id = p_contato;
  SELECT t.texto INTO v_msg FROM nai_turno t
   WHERE t.contato_id = p_contato ORDER BY t.id DESC LIMIT 1;
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
  DECLARE
    v_imv  int;
    v_novo int;
    v_ant  int;
  BEGIN
    -- LER A MENSAGEM (Tel, 16/09). Aqui ia NULL no lugar do texto, entao os
    -- dois primeiros criterios de nai_imovel_da_conversa -- o codigo que ELE
    -- escreveu agora e o condominio que ELE chamou pelo nome -- nunca rodavam.
    -- Foi o que derrubou o Carlus: ele disse "casa no Aleixo" e ela respondeu
    -- "de qual imovel voce fala?".
    v_imv := nai_imovel_da_conversa(p_contato, v_msg);
    IF v_imv IS NOT NULL THEN
      saida := saida || 'IMOVEL DESTA CONVERSA: ' || nai_ref_imovel(v_imv) || ' (codigo ' || v_imv ||
               '). Quando ele perguntar algo sem dizer o codigo ("e mobiliado?", "tem garagem?", "me manda as fotos"), '
               || 'e DESTE imovel que ele fala: use este codigo nas ferramentas, sem perguntar de novo. ';
    END IF;

    -- IMOVEL NOVO = APRESENTACAO NOVA (Tel, 16/09): "pode criar filas
    -- diferentes, uma para cada mencao a imovel diferente, como se a cada
    -- imovel que o corretor perguntar, vindo do grupo, ela abrisse uma sessao
    -- de apresentacao nova".
    --
    -- v_novo e o imovel que ELE acabou de citar. v_ant e o que estava em pauta
    -- antes desta mensagem. Quando os dois existem e sao diferentes, ela nao
    -- pergunta "qual desses?": ela apresenta o novo.
    SELECT x::int INTO v_novo
      FROM unnest(coalesce(nay_codigos_citados(coalesce(v_msg, '')), '{}'::text[])) x
     WHERE x ~ '^[0-9]{3,5}$' AND EXISTS (SELECT 1 FROM imoveis i WHERE i.codigo = x::int)
     LIMIT 1;

    SELECT t.codigo INTO v_ant FROM nai_turno t
     WHERE t.contato_id = p_contato AND t.codigo IS NOT NULL
       AND t.criado_em > coalesce(k.zerado_em, now() - interval '48 hours')
       AND t.id < (SELECT max(t2.id) FROM nai_turno t2 WHERE t2.contato_id = p_contato)
     ORDER BY t.id DESC LIMIT 1;

    IF v_novo IS NOT NULL AND v_ant IS NOT NULL AND v_novo <> v_ant THEN
      saida := saida || 'ELE MUDOU DE IMOVEL: antes voces falavam do ' || nai_ref_imovel(v_ant)
               || ' e agora ele fala do ' || nai_ref_imovel(v_novo)
               || '. Comece a apresentacao DESTE imovel do zero: chame '
               || 'imovel_por_codigo com ' || v_novo || ' e responda a pergunta dele sobre ele. '
               || 'NAO pergunte de qual imovel ele fala -- ele acabou de dizer. O imovel de antes '
               || 'continua valendo: se ficou alguma coisa pendente dele, entregue tambem. ';
    END IF;
  END;

  -- PEDIDO DE IMOVEL SEM REFERENCIA (Tel, 15/09). "Voce tem apartamento no
  -- valor de R$ 350.000 de 2 quartos?" chegou numa conversa que ja tinha um
  -- imovel em andamento, e o modelo leu como pergunta DAQUELE imovel: nao
  -- achou resposta e escalou ao Tel. Aqui o cabecalho diz, em palavras, que a
  -- mensagem e uma BUSCA -- e ja entrega os filtros que vieram nela.
  DECLARE v_ped jsonb; v_txt text; v_tem text;
  BEGIN
    SELECT t.texto INTO v_txt FROM nai_turno t WHERE t.contato_id = p_contato ORDER BY t.id DESC LIMIT 1;
    v_ped := nai_pedido_de_perfil(v_txt);
    IF (v_ped->>'e_pedido')::boolean THEN
      v_tem := nai_lista_pt(ARRAY_REMOVE(ARRAY[
                 CASE WHEN v_ped->>'bairro'  IS NOT NULL THEN 'bairro=' || (v_ped->>'bairro') END,
                 CASE WHEN v_ped->>'teto'    IS NOT NULL THEN 'teto=' || (v_ped->>'teto') END,
                 CASE WHEN v_ped->>'quartos' IS NOT NULL THEN 'quartos=' || (v_ped->>'quartos') END], NULL));
      saida := saida || 'ELE ESTA PROCURANDO IMOVEL (esta mensagem e uma BUSCA, nao e pergunta sobre o imovel '
               || 'da conversa). Chame buscar_por_perfil AGORA'
               || coalesce(' com ' || v_tem, ' sem nenhum filtro')
               || ' e diga o texto_pronto que ela devolver, exatamente como veio. Ela conduz a sequencia de '
               || 'perguntas sozinha e ja pula o que ele acabou de dizer. ';
    END IF;
  END;

  -- MAIS DE UMA SOLICITACAO NA MESMA MENSAGEM (Tel, 16/09): "na mesma conversa
  -- da Martinha ela perguntou de outro imovel; e importante que a Nay consiga
  -- entender mais de uma solicitacao".
  --
  -- As 04:12 ela mandou "Por favor / Esse e casa ?" -- duas coisas: o sim para
  -- as fotos que a Nay tinha oferecido, e uma pergunta sobre outro imovel. A
  -- Nay respondeu "qual desses?" e nao entregou nenhuma das duas.
  DECLARE
    v_ass  text[];
    v_lst  text;
    i      int;
  BEGIN
    v_ass := nai_assuntos_da_mensagem(v_msg);
    IF coalesce(array_length(v_ass, 1), 0) > 1 THEN
      v_lst := '';
      FOR i IN 1 .. array_length(v_ass, 1) LOOP
        v_lst := v_lst || ' (' || i || ') "' || left(v_ass[i], 120) || '"';
      END LOOP;
      saida := saida || 'ESTA MENSAGEM TRAZ ' || array_length(v_ass, 1) || ' ASSUNTOS:' || v_lst
               || '. Responda TODOS na mesma resposta, na ordem em que ele escreveu, e chame '
               || 'quantas ferramentas forem precisas para isso. Quando um assunto for de um '
               || 'imovel e outro for de outro, atenda os dois. ';
    END IF;
  END;

  -- O "POR FAVOR" E UM SIM (Tel, 16/09): "a moca disse por favor e ela nao
  -- mandou as fotos". Resposta curta de aceite responde a ULTIMA pergunta que a
  -- Nay fez -- e sem saber qual foi, o modelo nao tem como cumprir.
  DECLARE v_perg text;
  BEGIN
    IF lower(unaccent(btrim(coalesce(v_msg, '')))) ~
       ('^(por favor|porfavor|pfv|sim|isso|claro|pode ser|pode sim|quero|'
        || 'queria sim|manda|pode mandar|me manda|por gentileza|eh isso|aham|'
        || 'obrigad[ao]|blz|beleza|ok|okay|uhum|s)[\s,!.?]*$') THEN
      SELECT s.texto INTO v_perg FROM nai_saida s
       WHERE s.contato_id = p_contato AND s.tipo = 'texto' AND s.texto ~ '[?]'
         AND s.criado_em > now() - interval '12 hours'
       ORDER BY s.id DESC LIMIT 1;
      IF v_perg IS NOT NULL THEN
        saida := saida || 'ELE DISSE SIM. A resposta curta dele ("' || left(btrim(v_msg), 40)
                 || '") esta respondendo a ULTIMA coisa que voce perguntou: "'
                 || left(regexp_replace(v_perg, '[\r\n]+', ' ', 'g'), 160)
                 || '". Cumpra o que voce ofereceu AGORA, nesta resposta, sem perguntar de novo. ';
      END IF;
    END IF;
  END;

  -- SO CUMPRIMENTOU (Tel, 15/09): "ela tem que responder o cumprimento e
  -- aguardar nesse caso". Quem chega dizendo so "boa noite" ainda nao disse a
  -- que veio; despejar o roteiro em cima dele e responder outra pergunta.
  DECLARE v_cumpr text;
  BEGIN
    SELECT t.texto INTO v_cumpr FROM nai_turno t
     WHERE t.contato_id = p_contato ORDER BY t.id DESC LIMIT 1;
    IF nai_so_cumprimentou(v_cumpr) THEN
      saida := saida || 'ELE SO CUMPRIMENTOU, nada mais. Devolva o cumprimento em UMA linha '
               || 'curta, diga que e a Nay da Imob Easy e pergunte como pode ajudar. '
               || 'ESPERE ele dizer o que precisa: nao ofereca imovel, nao pergunte bairro '
               || 'nem faixa de preco, nao chame ferramenta nenhuma nesta resposta. ';
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
$function$;
