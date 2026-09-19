-- =====================================================================
-- NAI -- 59: a faixa em volta do teto, e a mobilia na frase dele (Tel, 16/09/2026)
--
-- Ele, sobre a conversa do Sr. Luciano: "aqui ele deu o teto de 4.200 e ela
-- tinha que seguir aquela regra de enviar 15% a menos e 10% a mais em cima do
-- teto que ele passou. E ela pode filtrar por semi-mobiliado que esta no site,
-- que no caso seria com modulados e ar".
--
-- O QUE ELA OFERECEU: para um cliente de ate 4.200, com modulados e ar --
-- 2.500, 2.500 e 2.600, nenhum filtro de mobilia.
--
-- TRES COISAS EXPLICAM ISSO
--
-- 1. O teto era so um limite para cima, e a lista sai ordenada pelo mais
--    barato. Agora e uma faixa: de 15% abaixo a 10% acima do que ele disse.
--    Com 4.200, de 3.570 a 4.620. Medido: 21 candidatos viram 8, e entram os
--    acima do teto, que antes nao apareciam. Os percentuais ficam em
--    `nai_config` (faixa_abaixo_pct, faixa_acima_pct) para ele mudar sem
--    deploy.
--
-- 2. A frase dele nem era reconhecida como pedido: "Estou com uma cliente
--    querendo algo..." nao batia com nenhum dos verbos de busca. A busca so
--    aconteceu porque o modelo chamou a ferramenta por conta propria.
--
-- 3. A mobilia nao era lida em lugar nenhum -- `nai_pedido_de_perfil` so
--    extraia bairro, teto e quartos. Agora "modulados", "planejados", "ar" e
--    "mobiliado" viram o filtro de mobilia, e "vazio"/"sem moveis" o contrario.
--
-- Gerado por `scratchpad/patch59.py` a partir do que estava NO BANCO.
-- =====================================================================

INSERT INTO nai_config (chave, valor) VALUES ('faixa_abaixo_pct', '15')
ON CONFLICT (chave) DO NOTHING;
INSERT INTO nai_config (chave, valor) VALUES ('faixa_acima_pct', '10')
ON CONFLICT (chave) DO NOTHING;

CREATE OR REPLACE FUNCTION public.nai_oferta_serve(i imoveis, p_telefone text, p_teto numeric, p_quartos integer, p_sem boolean, p_com boolean)
 RETURNS boolean
 LANGUAGE sql
 STABLE
AS $function$
  SELECT nay_esta_no_mercado(i.disponivel, i.bloqueado, i.publicado_no_site)
     AND NOT coalesce(i.e_parceiro, false)
     AND coalesce(i.valor_aluguel, 0) > 0
     -- A FAIXA EM VOLTA DO TETO (Tel, 16/09): "ele deu o teto de 4.200 e ela
     -- tinha que seguir aquela regra de enviar 15% a menos e 10% a mais em
     -- cima do teto que ele passou".
     --
     -- Ate aqui o teto era so um limite para cima, e a lista sai ordenada pelo
     -- mais barato: para um cliente de 4.200 ela ofereceu 2.500, 2.500 e
     -- 2.600. Nao era erro de codigo -- era o que estava escrito --, mas
     -- mostra imovel de outro padrao.
     --
     -- Medido no catalogo: com teto 4.200 havia 21 candidatos ate o teto e
     -- ficam 8 na faixa; e entram os de ate 4.620, que antes nao apareciam.
     -- Os percentuais estao em `nai_config`: faixa_abaixo_pct e faixa_acima_pct.
     AND (p_teto IS NULL
          OR i.valor_aluguel BETWEEN p_teto * (1 - nai_cfg_int('faixa_abaixo_pct', 15) / 100.0)
                                 AND p_teto * (1 + nai_cfg_int('faixa_acima_pct', 10) / 100.0))
     AND (p_quartos IS NULL OR p_quartos = 0 OR i.quartos = p_quartos)
     AND (NOT p_sem OR (coalesce(i.mobilia, '') !~* 'mobiliad' AND coalesce(i.descricao, '') !~* '\mmobiliad'))
     AND (NOT p_com OR (coalesce(i.mobilia, '') ~* '(mobiliad|modulad|planejad|ar-condicionado)'
                        OR coalesce(i.descricao, '') ~* '(mobiliad|modulad|planejad)'))
     AND NOT EXISTS (SELECT 1 FROM envios e
                      WHERE e.codigo = i.codigo::text AND e.enviado_em > now() - interval '30 days'
                        AND right(regexp_replace(coalesce(e.telefone, ''), '\D', '', 'g'), 8)
                            = right(regexp_replace(coalesce(p_telefone, ''), '\D', '', 'g'), 8));
$function$;

CREATE OR REPLACE FUNCTION public.nai_pedido_de_perfil(p_texto text)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE
AS $function$
DECLARE
  s        text := lower(unaccent(coalesce(p_texto, '')));
  s_lugar  text := nay_normalizar_lugar(coalesce(p_texto, ''), true);
  v_busca  boolean;
  v_teto   numeric;
  v_q      int;
  v_bairro text;
  m        text[];
BEGIN
  -- ------------------------------------------------------ o BAIRRO primeiro
  -- Vem antes porque um bairro conhecido no texto ja e, sozinho, sinal de
  -- busca: "tem algo em Ponta Negra?" nao fala a palavra "apartamento".
  -- Casa o nome inteiro; e, para nome de tres palavras ou mais, as duas
  -- primeiras -- ninguem escreve "Parque 10 de Novembro" no WhatsApp.
  SELECT b.bairro INTO v_bairro FROM (
    SELECT DISTINCT i.bairro FROM imoveis i WHERE nullif(btrim(i.bairro), '') IS NOT NULL) b
   WHERE s_lugar LIKE '%' || nay_normalizar_lugar(b.bairro, true) || '%'
      OR (array_length(string_to_array(nay_normalizar_lugar(b.bairro, true), ' '), 1) >= 3
          AND s_lugar LIKE '%' ||
              array_to_string((string_to_array(nay_normalizar_lugar(b.bairro, true), ' '))[1:2], ' ') || '%')
   ORDER BY length(b.bairro) DESC LIMIT 1;

  -- ------------------------------------------------------------ e uma BUSCA?
  -- Os parenteses em volta da concatenacao NAO sao enfeite: `~` e `||` tem a
  -- mesma precedencia no Postgres e a leitura e da esquerda para a direita,
  -- entao sem eles a regex vira so o primeiro pedaco -- e quebra.
  v_busca := s ~ ('\m(procuro|procurando|proucurando|busco|buscando|preciso de|precisa de|'
                 || 'teria|tem algum|tem alguma|tem algo|tem apartamento|tem apto|tem casa|tem kit|'
                 || 'voce tem|vc tem|vcs tem|voces tem|tens|quero um|quero uma|queria um|queria uma|'
                 || 'tenho cliente|meu cliente|cliente quer|cliente procura|cliente busca|'
                 -- 16/09: "Estou com uma cliente querendo algo, com modulados e
                 -- ar, ate 4.200" nao era reconhecido como busca. Quem diz
                 -- "estou com cliente" esta pedindo imovel.
                 || 'estou com cliente|estou com uma cliente|estou com um cliente|'
                 || 'cliente querendo|cliente interessad|to com cliente|tô com cliente|'
                 -- "quero com modulados e ar" -- so "quero um|quero uma" estava
                 -- aqui, e quem pede pela caracteristica ficava de fora.
                 || 'quero com|queria com|quero algo|queria algo|quero imovel|'
                 || 'to procurando|tô procurando|preciso achar|me ve|me ve algo|'
                 || 'esta procurando|estao procurando|to procurando|estou procurando)\M');

  -- ...e fala de imovel, de um filtro, ou de um bairro nosso. Sem isto, "voce
  -- tem o contato do proprietario?" entraria aqui.
  v_busca := v_busca AND (
       s ~ ('\m(apartamento|apartamentos|apto|aptos|ap|casa|casas|kitnet|kitinete|quitinete|'
           || 'studio|estudio|flat|cobertura|sala|salas|imovel|imoveis|terreno|galpao|predio)\M')
    OR s ~ '\m\d+\s*(quarto|quartos|dormitorio|dormitorios|qto|qtos)\M'
    OR s ~ 'r\$'
    OR v_bairro IS NOT NULL
  );

  -- MAS nao e busca quando ele aponta para O imovel da conversa: "esse
  -- apartamento tem garagem?" e pergunta de ficha, e continua indo para a base.
  IF s ~ '\m(desse|deste|nesse|neste|esse|este|essa|esta|dele|dela|do imovel|no imovel)\M'
     AND NOT (s ~ '\m(outro|outros|outra|outras|mais algum|mais alguma|parecido|similar)\M')
     -- 16/09: "preferencia DELA no Dom Pedro" derrubava a busca por causa do
     -- "dela" -- que ali era a cliente, nao um imovel. Quem diz um VALOR esta
     -- procurando: pergunta de ficha nao vem com preco dentro.
     AND NOT (s ~ 'r\$'
              OR s ~ '\m[0-9][0-9.,]*\s*(mil|k)\M'
              OR s ~ ('\m(ate|no maximo|maximo de|em torno de|faixa de)'
                   || '\s+[0-9][0-9.,]{2,}')) THEN
    v_busca := false;
  END IF;

  IF NOT v_busca THEN
    RETURN jsonb_build_object('e_pedido', false);
  END IF;

  -- --------------------------------------------------------------- QUARTOS
  m := regexp_match(s, '\m(\d+)\s*(quarto|quartos|dormitorio|dormitorios|qto|qtos)\M');
  IF m IS NOT NULL THEN v_q := m[1]::int; END IF;
  IF v_q IS NULL THEN
    m := regexp_match(s, '\m(um|uma|dois|duas|tres|quatro|cinco)\s+(quarto|quartos|dormitorio|dormitorios)\M');
    IF m IS NOT NULL THEN
      v_q := CASE m[1] WHEN 'um' THEN 1 WHEN 'uma' THEN 1 WHEN 'dois' THEN 2 WHEN 'duas' THEN 2
                       WHEN 'tres' THEN 3 WHEN 'quatro' THEN 4 ELSE 5 END;
    END IF;
  END IF;

  -- ------------------------------------------------------------------ TETO
  -- Em tres tentativas, da mais certa para a menos certa. O "de" solto ficou
  -- DE FORA de proposito: em "apartamento de 3 quartos" ele lia 3 como o
  -- orcamento do cliente, e foi exatamente o que aconteceu na primeira
  -- medicao. Numero colado a quarto, vaga, suite ou metro nunca e dinheiro.
  m := regexp_match(s, 'r\$\s*([\d\.,]+)\s*(mil|k)?');
  IF m IS NOT NULL THEN v_teto := nay_valor_em_reais(m[1] || coalesce(' ' || m[2], '')); END IF;
  IF v_teto IS NULL THEN
    m := regexp_match(s, '\m([\d\.,]+)\s*(mil|k)\M');
    IF m IS NOT NULL THEN v_teto := nay_valor_em_reais(m[1] || ' mil'); END IF;
  END IF;
  IF v_teto IS NULL THEN
    m := regexp_match(s, '\m(ate|por|faixa de|em torno de|no maximo|maximo de)\s+([\d\.,]{3,})\s*(reais)?'
                         '(?!\s*(quarto|quartos|dormitorio|dormitorios|vaga|vagas|suite|suites|m2|metros))');
    IF m IS NOT NULL THEN v_teto := nay_valor_em_reais(m[2]); END IF;
  END IF;

  -- ------------------------------------------------------------- MOBILIA
  -- "com modulados e ar" (Tel, 16/09): "ela pode filtrar por semi-mobiliado
  -- que esta no site, que no caso seria com modulados e ar".
  --
  -- No cadastro esses imoveis aparecem como "semi-mobiliado" e
  -- "semi-mobiliado (moveis planejados + ar)". Quem pede modulado, planejado
  -- ou ar-condicionado quer isso -- e tambem serve o mobiliado completo, que
  -- tem tudo o que o semi tem. Por isso o filtro devolvido e "com mobilia",
  -- que `nai_oferta_serve` ja entende dos dois jeitos.
  --
  -- E quem pede o contrario -- "vazio", "sem moveis" -- continua indo para o
  -- lado de la.
  DECLARE v_mob text;
  BEGIN
    -- Sem `\M` no fim de proposito: a marca de fim de palavra exigia que o
    -- texto acabasse em "mobiliad", e "mobiliado" tem um "o" depois -- entao
    -- "cliente que quer apartamento mobiliado" nao era reconhecido. O `\m` da
    -- frente basta: ele garante o comeco da palavra, e "desmobiliado" nao casa
    -- com "\mmobiliad" porque comeca em "des".
    IF s ~ '\m(vazio|sem mobilia|sem moveis|desmobiliad|nao mobiliad)' THEN
      v_mob := 'sem';
    -- Os parenteses em volta da concatenacao NAO sao enfeite: `~` e `||` tem a
    -- mesma precedencia no Postgres, entao sem eles a regex vira so o primeiro
    -- pedaco e o resto sobra solto -- foi o que estourou no primeiro teste.
    ELSIF s ~ ('\m(modulad|planejad|mobiliad|semi.?mobiliad|climatizad|'
            || 'ar.?condicionado|com ar)') THEN
      v_mob := 'com';
    END IF;

    RETURN jsonb_build_object(
      'e_pedido', true,
      'teto',    v_teto,
      'quartos', v_q,
      'mobilia', v_mob,
      'bairro',  v_bairro);
  END;
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
