-- =====================================================================
-- NAI -- 60: imovel de parceria nao sai daqui (Tel, 16/09/2026)
--
-- Ele: "a Nay enviou um imovel de parceiro; esses imoveis de parceiros nao e
-- pra enviar, quero eles em blacklist, so listados no site mas nunca enviados.
-- E ainda falou que esta disponivel."
--
-- O CASO: as 13:46, no chat do Sr. Fiuza, ela mandou 13 fotos do 3649 (Vitali
-- Residencial, Alvorada, e_parceiro = true) e respondeu "Esta disponivel sim, e
-- esse imovel e de parceria. Quer que eu te mande as fotos?".
--
-- POR QUE VAZOU: onze funcoes ja respeitavam `e_parceiro` -- a busca, a lista,
-- o pedido de visita, a resposta da base e ate o card, que devolve aviso de
-- parceria e ZERO fotos. Mas as fotos sao enfileiradas por outro caminho, e
-- ali ninguem perguntava de quem era o imovel. A parede da caixa de saida
-- conferia se a foto era DAQUELE imovel, nunca se o imovel podia sair.
--
-- DUAS COISAS
--
-- 1. A parede, no gatilho por onde toda saida passa: saida com codigo de
--    imovel de parceria e gravada como 'bloqueado', com o motivo escrito.
--    Cobre card, foto, lista e o que vier depois. Nao levanta excecao -- isso
--    derrubaria a resposta inteira --, e o que vai para o TEL continua
--    passando, porque e por ele que a parceria anda.
--
-- 2. O cabecalho avisa antes: sem isso ela promete fotos que a parede vai
--    barrar, e prometer sem entregar e pior do que nao prometer.
--
-- TAMANHO DISSO: 908 dos 1.246 imoveis do catalogo sao de parceria, 566 deles
-- no mercado. E a maior parte da base -- por isso a regra vale por baixo, e nao
-- so na instrucao ao modelo.
--
-- Gerado por `scratchpad/patch60.py` a partir do que estava NO BANCO.
-- =====================================================================

CREATE OR REPLACE FUNCTION public.nai_saida_validar()
 RETURNS trigger
 LANGUAGE plpgsql
AS $function$
DECLARE
  v_chave text;
  v record;
  t record;
BEGIN
  SELECT chave INTO v_chave FROM nai_contato WHERE id = NEW.contato_id;
  IF v_chave IS NULL THEN
    RAISE EXCEPTION 'NAI saida: contato % nao existe', NEW.contato_id;
  END IF;
  -- O destino e SEMPRE a chave do contato. Quem enfileira nao escolhe.
  NEW.chave_destino := v_chave;

  IF NEW.visita_id IS NOT NULL THEN
    SELECT * INTO v FROM nai_visita WHERE id = NEW.visita_id;
  END IF;
  IF NEW.turno_id IS NOT NULL THEN
    SELECT * INTO t FROM nai_turno WHERE id = NEW.turno_id;
  END IF;

  IF NEW.papel_destino = 'turno' THEN
    -- Resposta: so para quem escreveu aquele turno.
    IF t.id IS NULL OR t.contato_id <> NEW.contato_id THEN
      RAISE EXCEPTION 'NAI saida: resposta do turno % para contato % que nao e o autor', NEW.turno_id, NEW.contato_id;
    END IF;
  ELSIF NEW.papel_destino = 'entrega' THEN
    -- O TEL FALANDO PELA NAY (Tel, 16/09): o `DEVOLVER <telefone> <resposta>`
    -- precisa mandar texto para quem NAO escreveu aquele turno -- quem escreveu
    -- foi o Tel. A trava do papel 'turno' barrava, e estava certa.
    --
    -- Entao este papel tem trava propria: so sai de um turno cujo papel e
    -- 'tel'. Sem essa exigencia, qualquer funcao poderia mandar mensagem para
    -- qualquer pessoa do cadastro, que e o tipo de porta que nao se abre.
    IF t.id IS NULL OR t.papel <> 'tel' THEN
      RAISE EXCEPTION 'NAI saida: entrega so sai de um comando do Tel (turno %)', NEW.turno_id;
    END IF;
  ELSIF NEW.papel_destino = 'corretor' THEN
    IF v.id IS NULL OR v.corretor_id <> NEW.contato_id THEN
      RAISE EXCEPTION 'NAI saida: contato % nao e o corretor da visita %', NEW.contato_id, NEW.visita_id;
    END IF;
  ELSIF NEW.papel_destino = 'proprietario' THEN
    IF v.id IS NULL OR v.proprietario_id IS DISTINCT FROM NEW.contato_id THEN
      RAISE EXCEPTION 'NAI saida: contato % nao e o proprietario da visita %', NEW.contato_id, NEW.visita_id;
    END IF;
  ELSIF NEW.papel_destino = 'motoboy' THEN
    IF v.id IS NULL OR v.motoboy_id IS DISTINCT FROM NEW.contato_id OR NOT nai_e_motoboy(v_chave) THEN
      RAISE EXCEPTION 'NAI saida: contato % nao e o acompanhante da visita %', NEW.contato_id, NEW.visita_id;
    END IF;
  ELSIF NEW.papel_destino = 'tel' THEN
    IF v_chave IS DISTINCT FROM nai_chave(nai_cfg('tel_telefone')) THEN
      RAISE EXCEPTION 'NAI saida: contato % nao e o Tel', NEW.contato_id;
    END IF;
  END IF;

  -- IMOVEL DE PARCERIA NAO SAI DAQUI (Tel, 16/09): "a Nay enviou um imovel de
  -- parceiro; esses imoveis de parceiros nao e pra enviar, quero eles em
  -- blacklist, so listados no site mas nunca enviados".
  --
  -- O QUE ACONTECEU: as 13:46 ela mandou 13 fotos do 3649 (Vitali Residencial,
  -- Alvorada) e ainda disse que estava disponivel. O card ja sabia da regra --
  -- `nai_card_do_imovel` devolve aviso de parceria e ZERO fotos --, mas as
  -- fotos saem por outro caminho, e ali ninguem perguntava de quem era o
  -- imovel.
  --
  -- ESTA E A ULTIMA PAREDE, no gatilho por onde toda saida passa: cobre o card,
  -- a foto, a lista e qualquer caminho que venha a existir. Sao 908 imoveis de
  -- parceria no catalogo, 566 deles no mercado -- a maior parte da base --,
  -- entao a regra precisa valer por baixo, nao so na boa vontade do modelo.
  --
  -- NAO LEVANTA EXCECAO: a saida e gravada como 'bloqueado', com o motivo. Fica
  -- o rastro no painel de envios, e o resto da resposta segue viva -- estourar
  -- aqui derrubaria a mensagem inteira, inclusive o que podia ser dito.
  --
  -- O TEL CONTINUA RECEBENDO: e por ele que a parceria anda.
  IF NEW.codigo IS NOT NULL
     AND NEW.papel_destino <> 'tel'
     AND EXISTS (SELECT 1 FROM imoveis i
                  WHERE i.codigo = NEW.codigo AND coalesce(i.e_parceiro, false)) THEN
    NEW.estado   := 'bloqueado';
    NEW.bloqueio := 'imovel de parceria: so no site, nunca enviado';
    RETURN NEW;
  END IF;

  IF NEW.tipo = 'imagem' THEN
    -- Foto so para corretor, e so a foto que o banco diz ser DAQUELE imovel.
    IF NEW.papel_destino NOT IN ('turno', 'corretor')
       OR (NEW.papel_destino = 'turno' AND t.papel NOT IN ('corretor', 'tel')) THEN
      RAISE EXCEPTION 'NAI saida: foto so vai para corretor';
    END IF;
    -- A COLAGEM conta como imagem daquele imovel (Tel, 12/09): ela e nossa,
    -- montada das 4 primeiras fotos, e mora em `imovel_colagem`, nao em
    -- `imovel_fotos`. O resto da parede continua igual: url que nao esteja
    -- num dos dois lugares nao sai.
    IF NOT EXISTS (SELECT 1 FROM imovel_fotos f WHERE f.codigo = NEW.codigo AND f.url = NEW.imagem_url)
       AND NOT EXISTS (SELECT 1 FROM imovel_colagem c WHERE c.codigo = NEW.codigo AND c.url = NEW.imagem_url) THEN
      RAISE EXCEPTION 'NAI saida: a foto % nao e do imovel %', NEW.imagem_url, NEW.codigo;
    END IF;
  END IF;

  RETURN NEW;
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
                 CASE WHEN v_ped->>'quartos' IS NOT NULL THEN 'quartos=' || (v_ped->>'quartos') END,
                 -- 16/09: "com modulados e ar" tem que chegar na busca.
                 CASE WHEN v_ped->>'mobilia'  IS NOT NULL THEN 'mobilia=' || (v_ped->>'mobilia') END], NULL));
      saida := saida || 'ELE ESTA PROCURANDO IMOVEL (esta mensagem e uma BUSCA, nao e pergunta sobre o imovel '
               || 'da conversa). Chame buscar_por_perfil AGORA'
               || coalesce(' com ' || v_tem, ' sem nenhum filtro')
               || ' e diga o texto_pronto que ela devolver, exatamente como veio. Ela conduz a sequencia de '
               || 'perguntas sozinha e ja pula o que ele acabou de dizer. ';
    END IF;
  END;

  -- IMOVEL DE PARCERIA (Tel, 16/09). A parede da caixa de saida ja impede o
  -- envio, mas sem este aviso ela promete o que nao vai sair -- foi o que
  -- aconteceu com o 3649: "Esta disponivel sim... Quer que eu te mande as
  -- fotos?". Prometer e nao entregar e pior do que nao prometer.
  DECLARE v_imv_p int;
  BEGIN
    v_imv_p := nai_imovel_da_conversa(p_contato, v_msg);
    IF v_imv_p IS NOT NULL
       AND EXISTS (SELECT 1 FROM imoveis i WHERE i.codigo = v_imv_p AND coalesce(i.e_parceiro, false)) THEN
      saida := saida || 'ESTE IMOVEL E DE PARCERIA, nao e da Imob Easy: ' || nai_ref_imovel(v_imv_p)
               || '. Voce NAO manda card, NAO manda foto e NAO diz se esta disponivel -- quem trata '
               || 'de parceria e o Tel. Chame escalar_ao_tel NESTA resposta com o que ele perguntou e '
               || 'diga o texto_pronto que vier. ';
    END IF;
  END;

  -- ELE COLOU A FICHA DE UM IMOVEL NOSSO, SEM O CODIGO (Tel, 16/09). O card de
  -- outro sistema nao traz a linha "Codigo:", mas traz o nome do condominio --
  -- e o nome basta para achar o imovel aqui.
  DECLARE v_cnd int[];
  BEGIN
    IF nai_imovel_da_conversa(p_contato, v_msg) IS NULL THEN
      v_cnd := nai_imovel_pelo_condominio(v_msg, k.telefone);
      IF coalesce(array_length(v_cnd, 1), 0) = 1 THEN
        saida := saida || 'ELE FALOU DE UM IMOVEL NOSSO PELO NOME: ' || nai_ref_imovel(v_cnd[1])
                 || '. E deste que ele fala: use este codigo nas ferramentas e responda a '
                 || 'pergunta dele. NAO peca o codigo -- ele acabou de mandar a ficha. ';
      ELSIF coalesce(array_length(v_cnd, 1), 0) > 1 THEN
        saida := saida || 'ELE FALOU DE UM CONDOMINIO NOSSO e temos ' || array_length(v_cnd, 1)
                 || ' imoveis nele (codigos ' || array_to_string(v_cnd, ', ')
                 || '). Mostre os dois com nome e descricao e deixe ele escolher. ';
      END IF;
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
               || '. A frase "nao consigo abrir" esta proibida, em qualquer forma. '
               || 'Quando a informacao de sistema trouxer o que estava na midia, responda a '
               || 'partir dela, sem dizer que leu. Quando NAO trouxer, chame escalar_ao_tel '
               || 'NESTA resposta e diga o texto_pronto que ela devolver, exatamente como '
               || 'veio -- e uma linha curta avisando que recebeu; o Tel ve a midia e segue '
               || 'com ele. ';
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
