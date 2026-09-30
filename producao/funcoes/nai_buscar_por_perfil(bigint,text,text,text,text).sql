CREATE OR REPLACE FUNCTION public.nai_buscar_por_perfil(p_turno bigint, p_bairro text, p_teto text, p_quartos text, p_mobilia text)
 RETURNS TABLE(texto_pronto text, instrucao_para_voce text)
 LANGUAGE plpgsql
 STABLE
AS $function$
DECLARE
  t        nai_turno;
  k        nai_contato;
  b        record;
  v_teto   numeric := coalesce(nay_maior_valor(p_teto), nay_valor_em_reais(p_teto));
  v_q      int;            -- 218: um número só = exato (como antes); faixa fica em v_q_min/v_q_max
  v_q_min  int;
  v_q_max  int;
  v_multi  boolean := false;  -- 218: vários lugares na mesma resposta
  v_mais_barato boolean := false;  -- 218: a faixa vazia, e saíram os mais em conta
  v_mob    text := lower(unaccent(btrim(coalesce(p_mobilia, ''))));
  v_sem    boolean;
  v_com    boolean;
  v_viz    text[];
  v_alt    text;
  v_aqui   text;
  v_txt    text;
  v_nome_b text;
  v_direta boolean;   -- entrou PEDINDO imovel, sem vir de um card
  v_negocio text;     -- venda, locacao, ambos (98)
  v_tipo   text;      -- 'Casa%', 'Apartamento%' ... (98)
  v_rotulo text;
  v_nada   text;
  v_diz    text;
  v_mostra_logo boolean;   -- mostrar em vez de peneirar (100)
  v_livre  boolean;        -- procurar na cidade inteira (102)
  v_perto  text;           -- o bairro parecido, quando ele escreve outro (105)
  v_sem_valor  boolean;    -- 146: o cliente nao disse o valor
  v_tem_filtro boolean;    -- 146: ja da para listar
  v_tanto_faz  boolean;    -- 152: "tanto faz" casa ou apartamento
  v_falta      text[];     -- 146: os filtros que ainda da para oferecer
  v_falta_valor  boolean;  -- 190
  v_falta_regiao boolean;  -- 190
  v_abertura     boolean;  -- 190
  v_lug_bairros  text[];   -- 206: os bairros do conjunto/avenida citado
  v_lug_rx       text;     -- 206: o nome do conjunto (condominio de mesmo nome vem primeiro)
  v_lug_rotulo   text;     -- 206: "Parque 10 de Novembro (bairro do Conjunto Eldorado)"
  v_ultima       text;     -- 215: a última pergunta do filtro que ela fez (24 h)
  v_perfil       nai_perfil_cliente;  -- 223: o perfil do cliente deste pedido
  v_pedido_novo  boolean := false;    -- 223: bairro ou valor diferente do perfil
  v_elev         boolean := false;    -- 223: o cliente só aceita com elevador
BEGIN
  SELECT * INTO t FROM nai_turno WHERE id = p_turno;
  SELECT * INTO k FROM nai_contato WHERE id = t.contato_id;

  -- 223: O PERFIL DO CLIENTE. Bairro ou valor DIFERENTE do perfil em andamento é
  -- pedido novo (Pedro: "pediu locação em um bairro até 4k, depois locação em outro a
  -- partir de 3k"); senão, o que a chamada não trouxe vem do perfil.
  SELECT * INTO v_perfil FROM nai_perfil_ativo(k.id);
  IF v_perfil.id IS NOT NULL THEN
    v_pedido_novo :=
         (nullif(btrim(coalesce(p_bairro, '')), '') IS NOT NULL AND v_perfil.bairros IS NOT NULL
          AND NOT nai_sem_preferencia_de_bairro(p_bairro)
          AND nay_normalizar_lugar(p_bairro, true) <> nay_normalizar_lugar(v_perfil.bairros, true))
      OR (v_teto IS NOT NULL AND v_perfil.teto IS NOT NULL AND abs(v_teto - v_perfil.teto) > 0.1 * v_perfil.teto);
    IF NOT v_pedido_novo THEN
      p_bairro   := coalesce(nullif(btrim(coalesce(p_bairro, '')), ''), v_perfil.bairros);
      p_teto     := coalesce(nullif(btrim(coalesce(p_teto, '')), ''), v_perfil.teto::text);
      p_quartos  := coalesce(nullif(btrim(coalesce(p_quartos, '')), ''), v_perfil.quartos);
      p_mobilia  := coalesce(nullif(btrim(coalesce(p_mobilia, '')), ''), v_perfil.mobilia);
      v_teto     := coalesce(nay_maior_valor(p_teto), nay_valor_em_reais(p_teto));
      v_mob      := lower(unaccent(btrim(coalesce(p_mobilia, ''))));
      v_elev     := coalesce((v_perfil.exige->>'elevador')::boolean, false);
    END IF;
  END IF;

  -- 218: QUARTOS -- "1 ou 2" é de 1 a 2 (antes virava 12); "2 ou mais" é 2 para cima
  SELECT min(x[1]::int), max(x[1]::int) INTO v_q_min, v_q_max
    FROM regexp_matches(coalesce(p_quartos, ''), '([0-9]{1,2})', 'g') AS x
   WHERE x[1]::int BETWEEN 1 AND 10;
  IF v_q_min IS NOT NULL AND lower(unaccent(coalesce(p_quartos, ''))) ~ '(\+|ou mais|no minimo|pelo menos|a partir)' THEN
    v_q_max := 10;
  END IF;
  v_q := CASE WHEN v_q_min IS NOT NULL AND v_q_min = v_q_max THEN v_q_min END;

  -- 206: CONJUNTO E AVENIDA (Pedro, 30/09: "quando algum corretor perguntar de
  -- algum conjunto ... ela mande imoveis do bairro"; e a avenida, com os
  -- bairros dela). Só o bairro que a CHAMADA trouxe (215): o texto da mensagem
  -- pode ser um card colado ou um endereço, e isso não é resposta de região.
  v_lug_bairros := nai_bairros_do_lugar(p_bairro);
  -- 218: VÁRIOS LUGARES ("Adrianópolis, Vieiralves"): cada pedaço vira os bairros
  -- dele -- o do conjunto/avenida, ou o bairro do catálogo que bate com o nome
  IF p_bairro ~ '(,|;|/|\me\M|\mou\M)' THEN
    SELECT array_agg(DISTINCT z.b), nai_lista_pt(array_agg(DISTINCT z.nome))
      INTO v_lug_bairros, v_lug_rotulo
      FROM (SELECT initcap(btrim(p.x)) AS nome,
                   unnest(coalesce(nai_bairros_do_lugar(p.x),
                          ARRAY(SELECT DISTINCT i.bairro FROM imoveis i
                                 WHERE coalesce(btrim(i.bairro), '') <> ''
                                   AND nay_normalizar_lugar(i.bairro, true) LIKE '%' || nay_normalizar_lugar(p.x, true) || '%'))) AS b
              FROM unnest(regexp_split_to_array(p_bairro, '\s*(,|;|/|\me\M|\mou\M)\s*')) AS p(x)
             WHERE length(btrim(p.x)) >= 3) z;
    v_multi := v_lug_bairros IS NOT NULL;
  END IF;
  IF v_lug_bairros IS NOT NULL THEN
    v_lug_rx := (SELECT string_agg('(' || l.expressao || ')', '|') FROM nai_lugar_citado(p_bairro) l
                  WHERE l.tipo = 'conjunto');
    IF NOT v_multi THEN v_lug_rotulo := nai_lugar_rotulo(p_bairro); END IF;
    PERFORM nai_anotar(p_turno, 7, 'lugar_vira_bairro', 'mudou',
                       left(p_bairro || ' -> ' || array_to_string(v_lug_bairros, ', '), 200));
  END IF;

  -- 215: A QUE O "TANTO FAZ" RESPONDE -- a última pergunta do filtro, 24 h.
  SELECT CASE WHEN s.texto ~* 'alugar ou para comprar' THEN 'negocio'
              WHEN s.texto ~* 'casa ou apartamento\?' THEN 'tipo'
              WHEN s.texto ~* 'at[eé] que valor' THEN 'valor'
              ELSE 'regiao' END
    INTO v_ultima
    FROM nai_saida s
   WHERE s.contato_id = ANY (coalesce(nai_contato_irmaos(k.id), ARRAY[k.id])) AND s.tipo = 'texto'
     AND s.estado IN ('enviado', 'enviando', 'simulado') AND s.criado_em > now() - interval '24 hours'
     AND s.texto ~* '(alugar ou para comprar|casa ou apartamento\?|at[eé] que valor|regi[aã]o ou bairro|em qual bairro)'
   ORDER BY s.criado_em DESC LIMIT 1;

  -- POR ONDE ELE ENTROU (Tel, 15/09: "ou a pessoa vem pelo grupo ou a pessoa
  -- manda msg pedindo imoveis especificos"). Nao precisa de marca nova: quem
  -- veio do grupo tem um imovel na conversa -- o card que colou, o codigo que
  -- escreveu, a foto que pediu. Quem chegou perguntando "tem apartamento de 2
  -- quartos?" nao tem nenhum.
  -- O texto do turno vai junto de proposito: e por ele que a funcao
  -- reconhece o card que ele acabou de colar, na PRIMEIRA mensagem --
  -- sem isso, quem cola o card e pede outras opcoes na mesma mensagem
  -- cairia no caminho de quem chegou do zero.
  v_direta := nai_imovel_da_conversa(k.id, t.texto) IS NULL
              OR NOT (cardinality(nay_codigos_citados(coalesce(t.texto, ''))) > 0
                      OR coalesce(t.texto, '') ~* 'c[oó]digo:'
                      OR coalesce(array_length(nai_imovel_pelo_condominio(coalesce(t.texto, ''), ''), 1), 0) > 0);

  -- VENDA NAO E ALUGUEL, CASA NAO E APARTAMENTO (98, Tel 22/09). A sequencia
  -- de perguntas gasta tres mensagens: quando a busca roda, o texto do turno e
  -- so "700 mil". O que ele pediu no comeco esta nos turnos de tras -- por
  -- isso a leitura e da CONVERSA, e nao so desta mensagem.
  v_negocio := nai_negocio_da_conversa(k.id, concat_ws(' ', t.texto, p_teto));
  v_tipo    := nai_tipo_da_conversa(k.id, concat_ws(' ', t.texto, p_bairro));
  v_rotulo  := nai_rotulo_do_tipo(v_tipo);
  v_nada    := CASE WHEN v_rotulo IS NULL THEN 'nenhum imóvel'
                    WHEN v_rotulo IN ('casa', 'cobertura', 'sala', 'chácara') THEN 'nenhuma ' || v_rotulo
                    ELSE 'nenhum ' || v_rotulo END;
  v_diz     := CASE WHEN v_negocio = 'venda' THEN 'venda' ELSE 'locação' END;
  -- 223: o "não" educado diz o que falta ("nenhum apartamento com elevador")
  IF v_elev THEN v_nada := v_nada || ' com elevador'; END IF;
  -- 223: grava o perfil deste pedido (o que veio preenche; pedido novo começa outro)
  PERFORM nai_perfil_gravar(k.id, v_pedido_novo, p_bairro, v_teto, p_quartos, p_mobilia, v_negocio, v_tipo);
  IF v_pedido_novo THEN
    PERFORM nai_anotar(p_turno, 7, 'perfil_do_cliente', 'mudou', 'pedido novo: outro bairro ou outro valor');
  END IF;

  -- O TETO E DELE, MAS A LISTA E NOSSA (100, Tel 23/09). Ele pediu os
  -- valores, ou o que existe cabe numa mensagem: mostra, nao peneira.
  -- Com isso a sequencia de perguntas para de rodar em falso -- ela
  -- perguntou a faixa de preco TRES vezes ao Joao Luiz, que so queria ver a
  -- unica casa que temos no Nova Cidade.
  -- SEM PREFERENCIA DE BAIRRO (102, Tel 23/09). "Nao teria preferencia por
  -- bairro" nao era resposta aceita: a sequencia exigia um bairro, entao ela
  -- repetia a pergunta -- e repetiu, duas vezes, para a Deborah. Depois o
  -- modelo mandou "Manaus" como bairro e a busca antiga respondeu que NAO
  -- TRABALHAMOS COM IMOVEL EM MANAUS. A cidade nunca e bairro.
  v_livre := nai_e_a_cidade(p_bairro)
             OR nai_sem_preferencia_de_bairro(p_bairro)
             -- 215: "tanto faz" solto vale para a região só se a última pergunta
             -- foi a da região, ou se ele falou de bairro ("qualquer bairro")
             OR (nai_sem_preferencia_de_bairro(t.texto)
                 AND (v_ultima = 'regiao' OR lower(unaccent(coalesce(t.texto, ''))) ~ '(bairro|regiao|lugar|local|zona)'));
  v_mostra_logo := nai_pede_os_valores(concat_ws(' ', t.texto, p_bairro))
                   -- 222: "o bairro tem pouca coisa" só com bairro dado (sem bairro,
                   -- a conta era da cidade inteira e pulava a pergunta do valor)
                   OR (nullif(btrim(coalesce(p_bairro, '')), '') IS NOT NULL AND NOT nai_e_a_cidade(p_bairro)
                       AND nai_quantos_no_bairro(p_bairro, k.telefone, v_q, v_negocio, v_tipo)
                           BETWEEN 1 AND nai_cfg_int('limite_sem_teto', 5));
  IF v_mostra_logo THEN
    PERFORM nai_anotar(p_turno, 7, 'mostra_sem_peneirar', 'mudou',
                       'ele pediu os valores, ou o bairro tem pouca coisa');
  END IF;

  -- A SEQUENCIA DO FLUXO (cards do Tel): bairro -> faixa de preco -> mobilia,
  -- UMA PERGUNTA POR MENSAGEM. Quem manda a pergunta e esta funcao, nao o
  -- modelo: em 12/09 ele juntou duas perguntas numa mensagem so, duas vezes.
  -- Enquanto faltar resposta, ela devolve a PROXIMA pergunta e nada mais.
  -- O FILTRO DE IDENTIFICACAO (Tel, 28/09/2026): quem chegou pedindo imovel
  -- comeca pelo VALOR e depois os bairros, com a frase de abertura dele: "eu
  -- vou fazer um filtro com voce para poder te enviar as opcoes que mais podem
  -- atender a sua demanda. ate que valor o seu cliente quer? qual os bairros
  -- que atendem?". Uma pergunta por mensagem, como sempre. Quem veio do grupo
  -- segue o fluxo do site (bairro -> faixa -> mobilia), logo abaixo.
  -- 146: O FILTRO NAO TRAVA (Tel, 28/09: "a corretora disse que o cliente nao
  -- disse o valor que ele queria, entao ela deve ir para outro filtro e nao
  -- forcar a corretora a enviar o valor, ela deve perguntar regiao ou se e
  -- mobiliado ou semimobiliado... ela deveria listar os imoveis que temos e
  -- continuar perguntando depois se a corretora quer mais imoveis em outros
  -- filtros"). Com QUALQUER filtro na mao (valor, bairro, mobilia, tipo,
  -- quartos) ela LISTA -- na cidade toda se nao houver bairro -- e depois
  -- oferece os filtros que faltam. Sem filtro nenhum, pergunta um de cada vez.
  -- (Substitui a sequencia obrigatoria bairro -> faixa -> mobilia e a da 138.)
  -- 215: a frase que FALA de valor vale sempre; "tanto faz"/"não sabe" soltos só
  -- valem quando a última pergunta foi a do valor (ou vieram no teto da chamada)
  v_sem_valor := lower(unaccent(concat_ws(' ', p_teto, t.texto))) ~
      '(sem\s+valor|qualquer\s+valor|valor\s+(livre|aberto)|nao\s+tem\s+(um\s+)?valor|nao\s+(disse|sabe|informou|falou|definiu|passou)\s+(o\s+|um\s+)?(valor|preco|orcamento|quanto))'
    OR lower(unaccent(coalesce(p_teto, ''))) ~
      '(nao\s+(disse|sabe|informou|falou|definiu|passou|me\s+disse)|tanto\s+faz|indiferente|nao\s+importa|qualquer)'
    OR (v_ultima = 'valor' AND lower(unaccent(coalesce(t.texto, ''))) ~
      '(nao\s+(disse|sabe|informou|falou|definiu|passou|me\s+disse)|tanto\s+faz|indiferente|nao\s+importa|qualquer)');
  v_tem_filtro := v_teto IS NOT NULL
               OR (nullif(btrim(coalesce(p_bairro, '')), '') IS NOT NULL AND NOT v_livre)
               OR (nullif(v_mob, '') IS NOT NULL AND v_mob !~ '(tanto faz|indiferente|qualquer)')
               OR v_tipo IS NOT NULL OR v_q_min IS NOT NULL;

  -- LOCACAO OU VENDA antes de listar (144), quando a conversa nao disse e o
  -- valor tambem nao diz (ate R$ 30 mil e aluguel; de R$ 100 mil para cima e venda).
  IF v_negocio IS NULL AND nai_negocio_do_pedido(k.id, concat_ws(' ', t.texto, p_teto)) IS NULL THEN
    RETURN QUERY SELECT
      CASE WHEN v_tem_filtro OR v_sem_valor THEN 'Seu cliente procura imóvel para alugar ou para comprar?'
           ELSE 'Eu vou fazer um filtro com você para poder te enviar as opções que mais podem atender a sua demanda. Seu cliente procura imóvel para alugar ou para comprar?' END::text,
      ('filtro: primeiro se e locacao ou venda. Diga SO isso. Quando ele responder, chame buscar_por_perfil '
       || 'de novo com tudo o que ele ja disse (bairro, teto, mobilia).')::text;
    RETURN;
  END IF;
  IF v_negocio IS NULL THEN
    v_negocio := nai_negocio_do_pedido(k.id, concat_ws(' ', t.texto, p_teto));
    v_diz := CASE WHEN v_negocio = 'venda' THEN 'venda' ELSE 'locação' END;
  END IF;

  -- 152: CASA OU APARTAMENTO antes de listar, quando a conversa nao disse
  -- (Tel, 28/09: "é bom pôr no filtro de identificação da Nay também perguntar
  -- se não ficou claro se é casa ou apartamento"). A Ane Cavalcante pediu "um
  -- imóvel com no mínimo 4 quartos" e recebeu uma cobertura; ela queria casa.
  -- Sem laco: "tanto faz / qualquer um / os dois" libera a lista, e quem ja
  -- ouviu a pergunta nas ultimas 24h nao ouve de novo.
  IF v_tipo IS NULL THEN
    -- 215: o "tanto faz" é a RESPOSTA a "casa ou apartamento?" (o que ele escreveu
    -- depois dessa pergunta), ou uma frase que fala do tipo ("tanto faz casa ou apto")
    v_tanto_faz := lower(unaccent(concat_ws(' ',
        CASE WHEN v_ultima = 'tipo' THEN t.texto END,
        (SELECT string_agg(m.texto, ' ') FROM mensagens m
          WHERE nai_chave(m.telefone) IN (SELECT c.chave FROM nai_contato c WHERE c.id = ANY (nai_contato_irmaos(k.id)))
            AND m.direcao = 'recebida'
            AND m.criada_em > (SELECT max(s.criado_em) FROM nai_saida s
                                WHERE s.contato_id = ANY (nai_contato_irmaos(k.id)) AND s.tipo = 'texto'
                                  AND s.texto ILIKE '%casa ou apartamento?%' AND s.criado_em > now() - interval '24 hours')))))
      ~ '(tanto faz|qualquer (um|uma|tipo|coisa|imovel)|os dois|as duas|ambos|indiferente|nao importa|nao tem preferencia|sem preferencia)'
      OR lower(unaccent(coalesce(t.texto, ''))) ~
      '((casa|apartamento|apto).{0,25}(tanto faz|os dois|ambos|qualquer um)|(tanto faz|os dois|ambos|qualquer um).{0,25}(casa|apartamento|apto))';
    IF NOT v_tanto_faz AND NOT EXISTS (
         SELECT 1 FROM nai_saida s
          WHERE s.contato_id = ANY (nai_contato_irmaos(k.id)) AND s.tipo = 'texto'
            AND s.texto ILIKE '%casa ou apartamento?%' AND s.criado_em > now() - interval '24 hours') THEN
      RETURN QUERY SELECT 'Seu cliente procura casa ou apartamento?'::text,
        ('filtro: pergunte SO isso. Quando ele responder (casa, apartamento, ou que tanto faz), chame '
         || 'buscar_por_perfil de novo com tudo o que ele ja disse (bairro, teto, mobilia, quartos).')::text;
      RETURN;
    END IF;
  END IF;

  -- 190: O FILTRO VEM ANTES DE QUALQUER IMOVEL (Pedro, 29/09: "ela precisa
  -- fazer o filtro... sempre que tiver uma nova solicitacao de imoveis...
  -- primeiro fazer o filtro antes de enviar qualquer imovel"). O Sulivam pediu
  -- "casa, na media de 5mil" e a busca listou a cidade inteira sem perguntar a
  -- regiao, porque a 146 listava com QUALQUER filtro na mao. Agora a ordem e:
  -- locacao/venda (144) -> casa/apartamento (152) -> VALOR -> REGIAO, uma
  -- pergunta por mensagem. Quem veio do grupo comeca pela regiao (o fluxo do
  -- site: bairro -> faixa). A 146 continua valendo no que ela tinha de certo:
  -- "o cliente nao disse o valor" e "tanto faz o bairro" pulam a pergunta, e
  -- cada pergunta sai UMA vez por dia (`nai_filtro_ja_perguntado`) -- na
  -- segunda a busca lista com o que tiver.
  -- (Substitui o "sem filtro nenhum, pergunta um de cada vez" da 146.)
  v_falta_valor  := v_teto IS NULL AND NOT v_sem_valor AND NOT v_mostra_logo
                    AND NOT nai_filtro_ja_perguntado(k.id, 'valor');
  v_falta_regiao := nullif(btrim(coalesce(p_bairro, '')), '') IS NULL AND NOT v_livre
                    AND NOT nai_filtro_ja_perguntado(k.id, 'regiao');
  v_abertura     := NOT nai_filtro_ja_perguntado(k.id, 'abertura');
  IF v_falta_valor AND (v_direta OR NOT v_falta_regiao) THEN
    RETURN QUERY SELECT
      (CASE WHEN v_abertura
            THEN 'Eu vou fazer um filtro com você para poder te enviar as opções que mais podem atender a sua demanda. '
            ELSE '' END || 'Até que valor o seu cliente quer?')::text,
      ('filtro: diga SO essa pergunta. Se ele disser que o cliente nao disse o valor, chame buscar_por_perfil com '
       || 'teto "sem valor". Quando ele responder, chame buscar_por_perfil de novo com tudo o que ele ja disse '
       || '(bairro, teto, mobilia, quartos).')::text;
    RETURN;
  END IF;
  IF v_falta_regiao THEN
    RETURN QUERY SELECT
      (CASE WHEN v_sem_valor THEN 'Sem problema! Qual região ou bairro atende o seu cliente?'
            WHEN NOT v_direta THEN 'Eu também tenho outras opções de ' || v_diz || ', você está procurando imóveis em qual bairro?'
            ELSE 'Qual região ou bairro atende o seu cliente?' END)::text,
      ('filtro: diga SO essa pergunta. Se ele disser que tanto faz o bairro, chame buscar_por_perfil com bairro '
       || 'vazio: a lista sai da cidade toda. Quando ele responder, chame buscar_por_perfil de novo com tudo o que '
       || 'ele ja disse (bairro, teto, mobilia, quartos).')::text;
    RETURN;
  END IF;

  -- sem bairro, a lista e da cidade toda
  IF nullif(btrim(coalesce(p_bairro, '')), '') IS NULL THEN
    v_livre := true;
  END IF;

  v_sem := v_mob ~ '\m(sem|nao|vazio)\M';
  v_com := NOT v_sem AND v_mob ~ '\m(com|mobiliad|semi|modulad|planejad)';

  -- O FORMATO E DO TEL (13/09, depois do teste: "me mandou 2 imoveis de forma
  -- desformatada, quero algo assim bem formatado"). Um bloco por imovel, com o
  -- icone, o nome em negrito do WhatsApp e o codigo com #.
  SELECT string_agg(nai_bloco_oferta(z.c, v_negocio), E'\n\n' ORDER BY z.v) INTO v_aqui FROM (
    SELECT i.codigo AS c,
           CASE WHEN v_negocio = 'venda' THEN i.valor_venda
                ELSE coalesce(i.valor_aluguel, i.valor_venda) END AS v
      FROM imoveis i
     WHERE (v_livre OR nay_normalizar_lugar(i.bairro, true) LIKE '%' || nay_normalizar_lugar(p_bairro, true) || '%'
            OR i.bairro = ANY (v_lug_bairros))
       AND nai_oferta_serve(i, k.telefone, v_teto, v_q, v_sem, v_com, v_negocio, v_tipo)
       AND (v_q_min IS NULL OR coalesce(i.quartos, 0) BETWEEN v_q_min AND v_q_max) AND (NOT v_elev OR nai_imovel_tem_elevador(i.codigo) IS TRUE)  -- 218
     ORDER BY (v_lug_rx IS NOT NULL AND nai_lugar_normal(i.condominio_nome) ~ v_lug_rx) DESC, 2 LIMIT 5) z;

  -- 219: AO REDOR PELO MAPA -- divisa ou até 3 km dos bairros pedidos (um ou vários)
  v_viz := CASE WHEN v_livre THEN '{}'::text[]
                ELSE coalesce(nai_bairros_ao_redor(coalesce(v_lug_bairros, ARRAY(
                       SELECT DISTINCT i.bairro FROM imoveis i
                        WHERE coalesce(btrim(i.bairro), '') <> ''
                          AND nay_normalizar_lugar(i.bairro, true) LIKE '%' || nay_normalizar_lugar(p_bairro, true) || '%'))),
                       '{}'::text[]) END;
  IF coalesce(array_length(v_viz, 1), 0) > 0 THEN
    SELECT string_agg(nai_bloco_oferta(z.c, v_negocio), E'\n\n' ORDER BY z.v) INTO v_alt FROM (
      SELECT i.codigo AS c,
             CASE WHEN v_negocio = 'venda' THEN i.valor_venda
                  ELSE coalesce(i.valor_aluguel, i.valor_venda) END AS v
        FROM imoveis i
       WHERE i.bairro = ANY (v_viz)
         AND nay_normalizar_lugar(i.bairro, true) NOT LIKE '%' || nay_normalizar_lugar(p_bairro, true) || '%'
         AND i.bairro <> ALL (coalesce(v_lug_bairros, '{}'::text[]))
         AND nai_oferta_serve(i, k.telefone, v_teto, v_q, v_sem, v_com, v_negocio, v_tipo)
       AND (v_q_min IS NULL OR coalesce(i.quartos, 0) BETWEEN v_q_min AND v_q_max) AND (NOT v_elev OR nai_imovel_tem_elevador(i.codigo) IS TRUE)  -- 218
       ORDER BY (v_lug_rx IS NOT NULL AND nai_lugar_normal(i.condominio_nome) ~ v_lug_rx) DESC, 2 LIMIT 5) z;
  END IF;

  -- 218: A FAIXA VAZIA, MAS HÁ O QUE CABE NO VALOR ("até 4 mil" e o #5724 de
  -- R$ 2.600 ficava de fora da faixa de 3.200 a 4.400)
  IF v_aqui IS NULL AND v_alt IS NULL AND v_teto IS NOT NULL THEN
    SELECT string_agg(nai_bloco_oferta(z.c, v_negocio), E'\n\n' ORDER BY z.v DESC) INTO v_aqui FROM (
      SELECT i.codigo AS c,
             CASE WHEN v_negocio = 'venda' THEN i.valor_venda
                  ELSE coalesce(i.valor_aluguel, i.valor_venda) END AS v
        FROM imoveis i
       WHERE (v_livre OR nay_normalizar_lugar(i.bairro, true) LIKE '%' || nay_normalizar_lugar(p_bairro, true) || '%'
              OR i.bairro = ANY (v_lug_bairros))
         AND nai_oferta_serve(i, k.telefone, NULL, v_q, v_sem, v_com, v_negocio, v_tipo)
         AND (v_q_min IS NULL OR coalesce(i.quartos, 0) BETWEEN v_q_min AND v_q_max) AND (NOT v_elev OR nai_imovel_tem_elevador(i.codigo) IS TRUE)
         AND CASE WHEN v_negocio = 'venda'
                  THEN coalesce(i.valor_venda, 0) > 0
                       AND i.valor_venda <= v_teto * (1 + nai_cfg_int('faixa_acima_pct', 10) / 100.0)
                  ELSE coalesce(i.valor_aluguel, 0) > 0
                       AND i.valor_aluguel <= v_teto * (1 + nai_cfg_int('faixa_acima_pct', 10) / 100.0) END
       ORDER BY 2 DESC LIMIT 5) z;
    -- 219: nos bairros pedidos não coube nada? os mais em conta ao redor
    IF v_aqui IS NULL AND coalesce(array_length(v_viz, 1), 0) > 0 THEN
      SELECT string_agg(nai_bloco_oferta(z.c, v_negocio), E'\n\n' ORDER BY z.v DESC) INTO v_alt FROM (
        SELECT i.codigo AS c,
               CASE WHEN v_negocio = 'venda' THEN i.valor_venda
                    ELSE coalesce(i.valor_aluguel, i.valor_venda) END AS v
          FROM imoveis i
         WHERE i.bairro = ANY (v_viz)
           AND nai_oferta_serve(i, k.telefone, NULL, v_q, v_sem, v_com, v_negocio, v_tipo)
           AND (v_q_min IS NULL OR coalesce(i.quartos, 0) BETWEEN v_q_min AND v_q_max) AND (NOT v_elev OR nai_imovel_tem_elevador(i.codigo) IS TRUE)
           AND CASE WHEN v_negocio = 'venda'
                    THEN coalesce(i.valor_venda, 0) > 0
                         AND i.valor_venda <= v_teto * (1 + nai_cfg_int('faixa_acima_pct', 10) / 100.0)
                    ELSE coalesce(i.valor_aluguel, 0) > 0
                         AND i.valor_aluguel <= v_teto * (1 + nai_cfg_int('faixa_acima_pct', 10) / 100.0) END
         ORDER BY 2 DESC LIMIT 5) z;
    END IF;
    v_mais_barato := v_aqui IS NOT NULL OR v_alt IS NOT NULL;
    IF v_mais_barato THEN
      PERFORM nai_anotar(p_turno, 7, 'faixa_vazia_mais_em_conta', 'mudou', 'nada na faixa do valor: saíram os que cabem nele');
    END IF;
  END IF;

  -- NADA AQUI NEM PERTO (105, Tel 23/09: "nao e para ocorrer esse tipo de
  -- dupla busca, se eu coloco regra e para seguir").
  --
  -- Ate aqui, quando esta busca nao achava nada, quem respondia era a busca
  -- ANTIGA -- que nao conhece tipo, nem finalidade, nem faixa de teto. Era a
  -- unica porta por onde as regras dele nao passavam, e foi por ela que
  -- sairam dois apartamentos para quem pediu casa. Agora quem responde e
  -- aqui, com as mesmas regras do resto da funcao.
  IF v_aqui IS NULL AND v_alt IS NULL THEN

    -- 146: O TIPO PEDIDO NAO TEM, O RESTO DO PERFIL TEM -> LISTA OS OUTROS
    -- ("ela deveria listar os imoveis que temos para ela"). Perguntar "quer
    -- que eu mande?" nao serve: na volta o tipo sairia da conversa de novo.
    IF v_tipo IS NOT NULL THEN
      SELECT string_agg(nai_bloco_oferta(z.c, v_negocio), E'

' ORDER BY z.v) INTO v_aqui FROM (
        SELECT i.codigo AS c,
               CASE WHEN v_negocio = 'venda' THEN i.valor_venda
                    ELSE coalesce(i.valor_aluguel, i.valor_venda) END AS v
          FROM imoveis i
         WHERE (v_livre OR nay_normalizar_lugar(i.bairro, true) LIKE '%' || nay_normalizar_lugar(p_bairro, true) || '%'
            OR i.bairro = ANY (v_lug_bairros))
           AND nai_oferta_serve(i, k.telefone, v_teto, v_q, v_sem, v_com, v_negocio, NULL)
           AND (v_q_min IS NULL OR coalesce(i.quartos, 0) BETWEEN v_q_min AND v_q_max) AND (NOT v_elev OR nai_imovel_tem_elevador(i.codigo) IS TRUE)  -- 218
         ORDER BY (v_lug_rx IS NOT NULL AND nai_lugar_normal(i.condominio_nome) ~ v_lug_rx) DESC, 2 LIMIT 5) z;
      IF v_aqui IS NOT NULL THEN
        RETURN QUERY SELECT
          (initcap(coalesce(v_rotulo, 'esse tipo')) || ' nesse perfil eu não tenho no momento. Mas tenho estas opções nesse valor:'
           || E'

' || v_aqui || E'

'
           || 'Qual deles é de seu interesse? Assim, posso lhe enviar mais informações e detalhes.')::text,
          ('mande o texto_pronto EXATAMENTE como veio: cada imovel no seu bloco. NAO resuma e NAO invente imovel. '
           || 'Se ele quiser detalhe de um, chame imovel_por_codigo.')::text;
        RETURN;
      END IF;
    END IF;

    -- 1. O BAIRRO EXISTE? Pode ser so o jeito de escrever.
    IF NOT v_livre AND v_lug_bairros IS NULL AND NOT EXISTS (
         SELECT 1 FROM imoveis i
          WHERE nay_normalizar_lugar(i.bairro, true)
                LIKE '%' || nay_normalizar_lugar(p_bairro, true) || '%') THEN

      SELECT i.bairro INTO v_perto
        FROM imoveis i
       WHERE i.bairro IS NOT NULL AND btrim(i.bairro) <> ''
       GROUP BY i.bairro
       ORDER BY similarity(lower(unaccent(i.bairro)), lower(unaccent(coalesce(p_bairro, '')))) DESC
       LIMIT 1;

      IF v_perto IS NOT NULL
         AND similarity(lower(unaccent(v_perto)), lower(unaccent(coalesce(p_bairro, '')))) >= 0.45 THEN
        RETURN QUERY SELECT
          ('Você quis dizer ' || v_perto || '?')::text,
          ('o bairro que ele escreveu nao existe no catalogo, mas parece com este. '
           || 'Confirme com ele antes de procurar.')::text;
        RETURN;
      END IF;

      RETURN QUERY SELECT
        ('Não tenho imóvel nesse bairro. Em qual outro o cliente aceita?')::text,
        ('esse bairro nao esta no catalogo. NUNCA diga que nao trabalhamos em Manaus: '
         || 'a imobiliaria e de Manaus.')::text;
      RETURN;
    END IF;

    -- 2. O BAIRRO EXISTE, mas nao ha nada no perfil pedido. Dizer isso e a
    -- resposta certa -- trocar por outro tipo ou outro negocio nao e.
    RETURN QUERY SELECT
      (CASE WHEN v_livre
            THEN 'Não tenho ' || v_nada || ' nesse perfil disponível no momento.'
            ELSE 'No ' || coalesce(v_lug_rotulo, initcap(btrim(coalesce(p_bairro, '')))) || ' não tenho ' || v_nada
                 || ' nesse perfil agora, nem nos bairros aqui pertinho.' END
       || CASE WHEN v_teto IS NULL AND NOT v_sem_valor
               THEN ' Me diz até que valor o cliente vai, que eu procuro em toda a cidade.'
               ELSE '' END)::text,
      ('nao existe nada no perfil pedido' || coalesce(' (' || v_rotulo || ')', '')
       || '. NAO ofereca outro tipo nem outra finalidade no lugar. Pergunte outro bairro '
       || 'ou outra faixa de preco.')::text;
    RETURN;
  END IF;

  SELECT coalesce((SELECT i.bairro FROM imoveis i
                    WHERE nay_normalizar_lugar(i.bairro, true) LIKE '%' || nay_normalizar_lugar(p_bairro, true) || '%'
                    LIMIT 1), initcap(btrim(p_bairro))) INTO v_nome_b;

  -- AREA (Tel, 18/09): quem pediu "Vieiralves" ouve "No Vieiralves", e nao o
  -- nome oficial do bairro. A busca ja procurou em Nossa Senhora das Gracas; so
  -- o jeito de falar acompanha a pessoa.
  SELECT coalesce((SELECT a.area FROM nai_area_citada(p_bairro) a LIMIT 1), v_nome_b)
    INTO v_nome_b;
  -- 206: conjunto e avenida dizem de que bairro e a lista (o Vieiralves segue a regra de cima)
  IF v_lug_rotulo IS NOT NULL AND (v_multi OR NOT EXISTS (SELECT 1 FROM nai_area_citada(p_bairro))) THEN
    v_nome_b := v_lug_rotulo;
  END IF;

  -- UM SO, em lugar nenhum mais: vai o CARD (Tel, 22/09, caso 162). O card traz
  -- "Codigo:", e e isso que faz o sistema mandar as fotos e o fechamento.
  IF (SELECT count(*) FROM regexp_matches(coalesce(v_aqui, '') || coalesce(v_alt, ''), ' #[0-9]{3,5}\*', 'g')) = 1 THEN
    RETURN QUERY SELECT
      (CASE WHEN v_aqui IS NULL AND NOT v_livre
              THEN 'No ' || v_nome_b || ' eu não tenho ' || v_nada || ' nesse perfil agora, mas bem pertinho de lá eu tenho este'
                   || CASE WHEN v_mais_barato THEN ', um pouco mais em conta' ELSE '' END || ':' || E'\n\n'
            WHEN v_mais_barato
              THEN 'Nessa faixa de valor eu não tenho, mas tenho este um pouco mais em conta:' || E'\n\n'
            ELSE '' END
       || (SELECT cc.texto_pronto FROM nai_card_do_imovel(
         (regexp_match(coalesce(v_aqui, '') || coalesce(v_alt, ''), ' #([0-9]{3,5})\*'))[1]::int) cc)
       -- 222: o semimobiliado pergunta se serve
       || CASE WHEN coalesce(v_aqui, '') || coalesce(v_alt, '') ~ 'está 80% mobiliado'
               THEN E'\n\n' || 'Esse imóvel está 80% mobiliado, serve para seu cliente?' ELSE '' END),
      ('e um imovel so nesse perfil: mande o card EXATAMENTE como veio. O sistema manda as '
       || 'fotos e a sugestao de visita logo depois.')::text;
    RETURN;
  END IF;

  IF v_aqui IS NOT NULL THEN
    v_txt := CASE WHEN v_mais_barato AND v_livre
                    THEN 'Nessa faixa de valor eu não tenho, mas tenho estas opções mais em conta:'
                  WHEN v_mais_barato
                    THEN 'No ' || v_nome_b || ', nessa faixa de valor eu não tenho, mas tenho estas opções mais em conta:'
                  WHEN v_livre THEN 'Tenho estas opções:'
                  ELSE 'No ' || v_nome_b || ' eu tenho estas opções:' END
             || E'\n\n' || v_aqui;
    IF v_alt IS NOT NULL THEN
      v_txt := v_txt || E'\n\n' || 'E tenho estas aqui perto:' || E'\n\n' || v_alt;
    END IF;
  ELSE
    v_txt := 'No ' || v_nome_b || ' eu não tenho ' || v_nada || ' nesse perfil agora, mas separei estas opções bem pertinho de lá'
             || CASE WHEN v_mais_barato THEN ', um pouco mais em conta' ELSE '' END || ':' || E'\n\n' || v_alt;
  END IF;

  -- DEPOIS DE UMA LISTA, A PERGUNTA E PADRAO (Tel, 22/09, caso 159: "faltou ela
  -- perguntar De qual deles a Sra. quer mais informacoes? isso tem que ser
  -- padrao apos o envio de uma lista"). Vem daqui, e nao do prompt, para nao
  -- depender de ela lembrar.
  -- 222: sem outra pergunta (a parede de uma pergunta por mensagem cortaria)
  IF coalesce(v_aqui, '') || coalesce(v_alt, '') ~ 'está 80% mobiliado' THEN
    v_txt := v_txt || E'\n\n' || 'Os semimobiliados estão 80% mobiliados.';
  END IF;
  v_txt := v_txt || E'\n\n' || 'Qual deles é de seu interesse? Assim, posso lhe enviar mais informações e detalhes.';
  -- 146: e continua oferecendo os filtros que ainda nao foram usados
  v_falta := array_remove(ARRAY[
    CASE WHEN nullif(btrim(coalesce(p_bairro, '')), '') IS NULL THEN 'a região' END,
    CASE WHEN nullif(v_mob, '') IS NULL THEN 'se prefere mobiliado ou semimobiliado' END,
    CASE WHEN v_teto IS NULL AND NOT v_sem_valor THEN 'até que valor o cliente vai' END], NULL);
  IF coalesce(array_length(v_falta, 1), 0) > 0 THEN
    v_txt := v_txt || E'\n' || 'Se quiser mais opções, me diz ' || nai_lista_pt(v_falta) || ' que eu filtro aqui.';
  END IF;

  RETURN QUERY SELECT v_txt,
    ('mande o texto_pronto EXATAMENTE como veio: cada imovel no seu bloco, com o icone, o negrito e as linhas com •. '
     || 'NAO resuma, NAO junte tudo numa linha, NAO reescreva e NAO invente imovel que nao esta na lista. '
     || 'Se ele quiser detalhe de um, chame imovel_por_codigo. NAO sugira visita aqui.')::text;
END;
$function$;
