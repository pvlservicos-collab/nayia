-- =====================================================================
-- NAI -- 50: identificar o imovel pela descricao (Tel, 16/09/2026)
--
-- Ele: "o Carlos perguntou de um imovel de uma lista que mandei no grupo e ela
-- respondeu de forma muito rispida, nem deu o bom dia dele -- ela so perguntou
-- 'de qual imovel voce fala?', sendo que ele ja tinha dito que era casa do
-- Aleixo. Quando a mensagem vier de lista de um grupo, ela vai ler a mensagem e
-- identificar o imovel."
--
-- A EDUCACAO desse mesmo pedido foi nos arquivos 46 e 47. Falta a outra metade:
-- ler a descricao.
--
-- POR QUE NAO DAVA PARA CASAR COM O GRUPO: a lista que o Tel manda no grupo e
-- escrita a mao e nao passa por `envios` -- conferido, nas 48 horas em volta
-- daquela conversa nenhuma casa no Aleixo foi disparada. O registro do imovel
-- simplesmente nao existe. O que existe e o catalogo, e ele basta: casa
-- disponivel no Aleixo e uma so, o 5709. Foi o que ela mesma respondeu na
-- mensagem seguinte, depois de ele repetir a descricao.
--
-- `nai_imovel_pela_descricao` le o bairro e o tipo na frase dele e devolve o
-- que esta de pe, pelo mesmo crivo da busca (`nai_oferta_serve`). Sem bairro
-- nao ha resposta: "tem casa?" traria o catalogo inteiro.
--
-- No cabecalho, e so quando NAO ha imovel na conversa:
--   um bate     -> e esse, siga com ele
--   varios      -> mostre com nome e descricao, deixe ele escolher
--   nenhum      -> diga que nao ha, e ofereca bairro vizinho
--
-- Gerado por `scratchpad/patch50.py` a partir do que estava NO BANCO.
-- =====================================================================

CREATE OR REPLACE FUNCTION public.nai_imovel_pela_descricao(p_texto text, p_telefone text)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE
AS $function$
DECLARE
  s        text := lower(unaccent(coalesce(p_texto, '')));
  s_lugar  text := nay_normalizar_lugar(coalesce(p_texto, ''), true);
  v_bairro text;
  v_tipo   text;   -- o padrao do LIKE contra imoveis.tipo
  v_rotulo text;   -- como ELE chamou, para a Nay repetir a palavra dele
  v_cods   int[];
BEGIN
  -- O BAIRRO. Mesmo criterio de nai_pedido_de_perfil: casa o nome inteiro e,
  -- para nome de tres palavras ou mais, as duas primeiras -- ninguem escreve
  -- "Parque 10 de Novembro" no WhatsApp.
  SELECT b.bairro INTO v_bairro FROM (
    SELECT DISTINCT i.bairro FROM imoveis i WHERE nullif(btrim(i.bairro), '') IS NOT NULL) b
   WHERE s_lugar LIKE '%' || nay_normalizar_lugar(b.bairro, true) || '%'
      OR (array_length(string_to_array(nay_normalizar_lugar(b.bairro, true), ' '), 1) >= 3
          AND s_lugar LIKE '%' ||
              array_to_string((string_to_array(nay_normalizar_lugar(b.bairro, true), ' '))[1:2], ' ') || '%')
   ORDER BY length(b.bairro) DESC LIMIT 1;

  -- SEM BAIRRO NAO HA BUSCA. "Tem casa?" sozinho traria o catalogo inteiro, e
  -- o resultado seria pior do que perguntar.
  IF v_bairro IS NULL THEN
    RETURN jsonb_build_object('achou', false);
  END IF;

  -- O TIPO, na palavra dele. A ordem importa: "casa de condominio" tem que ser
  -- lido antes de "condominio".
  IF    s ~ '\m(casa|casas|sobrado)\M'                       THEN v_tipo := 'Casa%';        v_rotulo := 'casa';
  ELSIF s ~ '\m(apartamento|apartamentos|apto|aptos|ap)\M'   THEN v_tipo := 'Apartamento%'; v_rotulo := 'apartamento';
  ELSIF s ~ '\m(cobertura|coberturas)\M'                     THEN v_tipo := 'Cobertura%';   v_rotulo := 'cobertura';
  ELSIF s ~ '\m(flat|flats)\M'                               THEN v_tipo := 'Flat%';        v_rotulo := 'flat';
  ELSIF s ~ '\m(sala|salas|andar)\M'                         THEN v_tipo := 'Sala%';        v_rotulo := 'sala';
  ELSIF s ~ '\m(loja|lojas|ponto)\M'                         THEN v_tipo := 'Loja%';        v_rotulo := 'loja';
  ELSIF s ~ '\m(galpao|galpoes|deposito)\M'                  THEN v_tipo := 'Galp%';        v_rotulo := 'galpão';
  ELSIF s ~ '\m(terreno|terrenos|lote|lotes)\M'              THEN v_tipo := 'Lote%';        v_rotulo := 'terreno';
  ELSIF s ~ '\m(chacara|chacaras|sitio)\M'                   THEN v_tipo := 'Ch%';          v_rotulo := 'chácara';
  ELSIF s ~ '\m(predio|predios)\M'                           THEN v_tipo := 'Pr%dio%';      v_rotulo := 'prédio';
  END IF;

  IF v_tipo IS NULL THEN
    RETURN jsonb_build_object('achou', false);
  END IF;

  -- O QUE ESTA DE PE. `nai_oferta_serve` e o mesmo crivo que a busca usa: o
  -- que ela nao ofereceria numa busca tambem nao serve para identificar aqui.
  SELECT coalesce(array_agg(z.c ORDER BY z.v), '{}') INTO v_cods FROM (
    SELECT i.codigo AS c, i.valor_aluguel AS v FROM imoveis i
     WHERE nay_normalizar_lugar(i.bairro, true) = nay_normalizar_lugar(v_bairro, true)
       AND i.tipo ILIKE v_tipo
       AND nai_oferta_serve(i, coalesce(p_telefone, ''), NULL, NULL, false, false)
     ORDER BY i.valor_aluguel LIMIT 9) z;

  IF coalesce(array_length(v_cods, 1), 0) = 0 THEN
    RETURN jsonb_build_object('achou', false, 'bairro', v_bairro, 'rotulo', v_rotulo, 'vazio', true);
  END IF;

  RETURN jsonb_build_object(
    'achou',   true,
    'bairro',  v_bairro,
    'rotulo',  v_rotulo,
    'quantos', array_length(v_cods, 1),
    'codigos', to_jsonb(v_cods));
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

  -- ELE DESCREVEU O IMOVEL EM VEZ DE DAR O CODIGO (Tel, 16/09): "o Carlos
  -- perguntou de um imovel de uma lista que mandei no grupo e ela respondeu de
  -- forma muito rispida... so perguntou 'de qual imovel voce fala?', sendo que
  -- ele ja tinha dito que era casa do Aleixo. Quando a mensagem vier de lista
  -- de um grupo, ela vai ler a mensagem e identificar o imovel."
  --
  -- A lista que o Tel manda no grupo e escrita a mao: nao passa por `envios`,
  -- entao nao ha registro de imovel para casar. O que existe e o catalogo --
  -- e "casa no Aleixo" o encontra, porque casa disponivel no Aleixo e uma so.
  --
  -- Isto so roda quando nao ha imovel na conversa: com imovel em pauta, quem
  -- manda e o bloco de cima.
  DECLARE v_desc jsonb; v_qtos int;
  BEGIN
    IF nai_imovel_da_conversa(p_contato, v_msg) IS NULL THEN
      v_desc := nai_imovel_pela_descricao(v_msg, k.telefone);
      IF (v_desc->>'achou')::boolean THEN
        v_qtos := (v_desc->>'quantos')::int;
        IF v_qtos = 1 THEN
          saida := saida || 'ELE DESCREVEU O IMOVEL em vez de dar o codigo: ' || (v_desc->>'rotulo')
                   || ' em ' || (v_desc->>'bairro') || '. So um bate com essa descricao: '
                   || nai_ref_imovel(((v_desc->'codigos')->>0)::int)
                   || '. E DESTE que ele fala: use este codigo nas ferramentas e responda a pergunta '
                   || 'dele. NAO pergunte de qual imovel ele fala -- ele acabou de descrever. ';
        ELSE
          saida := saida || 'ELE DESCREVEU O IMOVEL em vez de dar o codigo: ' || (v_desc->>'rotulo')
                   || ' em ' || (v_desc->>'bairro') || '. Batem ' || v_qtos
                   || ' imoveis (codigos ' || replace(replace((v_desc->>'codigos'), '[', ''), ']', '')
                   || '). Mostre esses imoveis a ele com nome e descricao de cada um, e deixe ele '
                   || 'escolher. NAO pergunte de qual imovel ele fala nem peca o codigo seco. ';
        END IF;
      ELSIF coalesce((v_desc->>'vazio')::boolean, false) THEN
        saida := saida || 'ELE PROCURA ' || upper(coalesce(v_desc->>'rotulo', 'imovel')) || ' EM '
                 || upper(coalesce(v_desc->>'bairro', '')) || ' e nao temos nenhuma disponivel ai '
                 || 'agora. Diga isso com jeito e pergunte se ele quer ver em bairro vizinho ou de '
                 || 'outro tipo. ';
      END IF;
    END IF;
  END;

  -- IMAGEM, AUDIO E ARQUIVO (Tel, 16/09): "ela NUNCA deve falar que nao le
  -- imagem; se nao conseguir, manda a imagem ao Tel".
  --
  -- As 05:32 o Sr. Ribamar mandou treze fotos de um imovel e ela respondeu "Nao
  -- consigo abrir a imagem, Sr. Ribamar". As 05:30 o proprio Tel mandou um
  -- arquivo e ouviu a mesma coisa. A midia chega em `mensagens` com origem
  -- 'imagem'/'audio'/'documento' e TEXTO VAZIO -- o modelo nao recebia nem o
  -- aviso de que algo tinha chegado, e inventava a desculpa.
  DECLARE
    v_mid  text;
    v_turn bigint;
  BEGIN
    SELECT t.id INTO v_turn FROM nai_turno t
     WHERE t.contato_id = p_contato ORDER BY t.id DESC LIMIT 1;
    v_mid := nai_midia_do_turno(v_turn);
    IF v_mid IS NOT NULL THEN
      saida := saida || 'ELE MANDOU ' || upper(v_mid) || ' nesta mensagem'
               || CASE WHEN btrim(coalesce(v_msg, '')) = '' THEN ', sem escrever nada junto'
                       ELSE '' END
               || '. Voce NAO abre imagem, audio nem arquivo, e NUNCA diz isso a ele: '
               || 'a frase "nao consigo abrir" esta proibida, em qualquer forma. '
               || 'Chame escalar_ao_tel NESTA resposta e responda exatamente SILENCIO -- '
               || 'o Tel ve a midia e segue com ele. ';
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
