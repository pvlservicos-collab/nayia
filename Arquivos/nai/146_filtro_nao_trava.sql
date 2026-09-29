-- =====================================================================
-- 146 — O FILTRO NÃO TRAVA: LISTA COM O QUE TEM E OFERECE O RESTO (28/09/2026)
--
-- Tel: "a corretora disse que o cliente não disse o valor que ele queria,
-- então ela deve ir para outro filtro e não forçar a corretora a enviar o
-- valor, ela deve perguntar região ou se é mobiliado ou semimobiliado,
-- lembrando que o filtro de valor é até 20% a menos ou 10% a mais o valor que
-- o cara sugerir, e ela deveria listar os imóveis que temos para ela e
-- continuar perguntando depois se a corretora quer mais imóveis em outros
-- filtros". Caso: 92 8192-5962, "O que vc teria até 2800 mobiliado" ->
-- ela respondeu "você está procurando imóveis em qual bairro?".
-- =====================================================================
\set ON_ERROR_STOP on
BEGIN;
SET LOCAL lock_timeout = '5s';
UPDATE nai_config SET valor = '20', atualizado_em = now() WHERE chave = 'faixa_abaixo_pct';

CREATE OR REPLACE FUNCTION nai_negocio_do_pedido(p_contato bigint, p_texto text)
RETURNS text
LANGUAGE sql
STABLE
AS $fn$
  -- 146: "tem apartamento de 2 quartos?" virava aluguel de R$ 2. Valor de
  -- verdade comeca em R$ 300.
  SELECT coalesce(nai_negocio_da_conversa(p_contato, p_texto),
                  CASE WHEN x.v IS NULL OR x.v < 300 THEN NULL
                       WHEN x.v <= 30000 THEN 'locacao' WHEN x.v >= 100000 THEN 'venda' END)
    FROM (SELECT coalesce(nay_maior_valor(coalesce(p_texto, '')), nay_valor_em_reais(coalesce(p_texto, ''))) AS v) x;
$fn$;
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
  v_q      int := NULLIF(regexp_replace(coalesce(p_quartos, ''), '[^0-9]', '', 'g'), '')::int;
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
  v_falta      text[];     -- 146: os filtros que ainda da para oferecer
BEGIN
  SELECT * INTO t FROM nai_turno WHERE id = p_turno;
  SELECT * INTO k FROM nai_contato WHERE id = t.contato_id;

  -- POR ONDE ELE ENTROU (Tel, 15/09: "ou a pessoa vem pelo grupo ou a pessoa
  -- manda msg pedindo imoveis especificos"). Nao precisa de marca nova: quem
  -- veio do grupo tem um imovel na conversa -- o card que colou, o codigo que
  -- escreveu, a foto que pediu. Quem chegou perguntando "tem apartamento de 2
  -- quartos?" nao tem nenhum.
  -- O texto do turno vai junto de proposito: e por ele que a funcao
  -- reconhece o card que ele acabou de colar, na PRIMEIRA mensagem --
  -- sem isso, quem cola o card e pede outras opcoes na mesma mensagem
  -- cairia no caminho de quem chegou do zero.
  v_direta := nai_imovel_da_conversa(k.id, t.texto) IS NULL;

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
             OR nai_sem_preferencia_de_bairro(concat_ws(' ', p_bairro, t.texto));
  v_mostra_logo := nai_pede_os_valores(concat_ws(' ', t.texto, p_bairro))
                   OR nai_quantos_no_bairro(p_bairro, k.telefone, v_q, v_negocio, v_tipo)
                      BETWEEN 1 AND nai_cfg_int('limite_sem_teto', 5);
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
  v_sem_valor := lower(unaccent(concat_ws(' ', p_teto, t.texto))) ~
    '(nao\s+(disse|sabe|informou|falou|definiu|passou|me\s+disse)|sem\s+valor|qualquer\s+valor|tanto\s+faz|valor\s+(livre|aberto)|nao\s+tem\s+(um\s+)?valor)';
  v_tem_filtro := v_teto IS NOT NULL
               OR (nullif(btrim(coalesce(p_bairro, '')), '') IS NOT NULL AND NOT v_livre)
               OR (nullif(v_mob, '') IS NOT NULL AND v_mob !~ '(tanto faz|indiferente|qualquer)')
               OR v_tipo IS NOT NULL OR v_q IS NOT NULL;

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

  IF NOT v_tem_filtro THEN
    IF v_sem_valor THEN
      RETURN QUERY SELECT 'Sem problema! Tem alguma região que atende o seu cliente? Ou ele prefere mobiliado ou semimobiliado?'::text,
        ('o cliente nao disse o valor: NAO pergunte o valor de novo. Quando ele responder a regiao ou a mobilia, '
         || 'chame buscar_por_perfil com isso e teto vazio.')::text;
      RETURN;
    END IF;
    RETURN QUERY SELECT
      CASE WHEN v_direta
           THEN 'Eu vou fazer um filtro com você para poder te enviar as opções que mais podem atender a sua demanda. Até que valor o seu cliente quer?'
           ELSE 'Eu também tenho outras opções de ' || v_diz || ', você está procurando imóveis em qual bairro?' END::text,
      ('filtro: diga SO essa pergunta. Se ele disser que o cliente nao disse o valor, chame buscar_por_perfil com '
       || 'teto "sem valor". Com qualquer filtro que ele der (valor, bairro, mobilia), chame buscar_por_perfil de novo: '
       || 'a ferramenta ja lista.')::text;
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
     WHERE (v_livre OR nay_normalizar_lugar(i.bairro, true) LIKE '%' || nay_normalizar_lugar(p_bairro, true) || '%')
       AND nai_oferta_serve(i, k.telefone, v_teto, v_q, v_sem, v_com, v_negocio, v_tipo)
     ORDER BY 2 LIMIT 5) z;

  v_viz := CASE WHEN v_livre THEN '{}'::text[]
                ELSE nay_bairros_proximos(btrim(coalesce(p_bairro, ''))) END;
  IF coalesce(array_length(v_viz, 1), 0) > 1 THEN
    SELECT string_agg(nai_bloco_oferta(z.c, v_negocio), E'\n\n' ORDER BY z.v) INTO v_alt FROM (
      SELECT i.codigo AS c,
             CASE WHEN v_negocio = 'venda' THEN i.valor_venda
                  ELSE coalesce(i.valor_aluguel, i.valor_venda) END AS v
        FROM imoveis i
       WHERE i.bairro = ANY (v_viz)
         AND nay_normalizar_lugar(i.bairro, true) NOT LIKE '%' || nay_normalizar_lugar(p_bairro, true) || '%'
         AND nai_oferta_serve(i, k.telefone, v_teto, v_q, v_sem, v_com, v_negocio, v_tipo)
       ORDER BY 2 LIMIT 5) z;
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
         WHERE (v_livre OR nay_normalizar_lugar(i.bairro, true) LIKE '%' || nay_normalizar_lugar(p_bairro, true) || '%')
           AND nai_oferta_serve(i, k.telefone, v_teto, v_q, v_sem, v_com, v_negocio, NULL)
         ORDER BY 2 LIMIT 5) z;
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
    IF NOT v_livre AND NOT EXISTS (
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
            ELSE 'No ' || initcap(btrim(coalesce(p_bairro, ''))) || ' não tenho ' || v_nada
                 || ' nesse perfil, nem nos bairros aqui perto.' END
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

  -- UM SO, em lugar nenhum mais: vai o CARD (Tel, 22/09, caso 162). O card traz
  -- "Codigo:", e e isso que faz o sistema mandar as fotos e o fechamento.
  IF (SELECT count(*) FROM regexp_matches(coalesce(v_aqui, '') || coalesce(v_alt, ''), ' #[0-9]{3,5}\*', 'g')) = 1 THEN
    RETURN QUERY SELECT
      (SELECT cc.texto_pronto FROM nai_card_do_imovel(
         (regexp_match(coalesce(v_aqui, '') || coalesce(v_alt, ''), ' #([0-9]{3,5})\*'))[1]::int) cc),
      ('e um imovel so nesse perfil: mande o card EXATAMENTE como veio. O sistema manda as '
       || 'fotos e a sugestao de visita logo depois.')::text;
    RETURN;
  END IF;

  IF v_aqui IS NOT NULL THEN
    v_txt := CASE WHEN v_livre THEN 'Tenho estas opções:'
                  ELSE 'No ' || v_nome_b || ' eu tenho estas opções:' END
             || E'\n\n' || v_aqui;
    IF v_alt IS NOT NULL THEN
      v_txt := v_txt || E'\n\n' || 'E tenho estas aqui perto:' || E'\n\n' || v_alt;
    END IF;
  ELSE
    v_txt := 'No ' || v_nome_b || ', não tenho ' || v_nada || ' nesse perfil disponível no momento.' || E'\n\n' ||
             'Mas tenho estas opções aqui perto:' || E'\n\n' || v_alt;
  END IF;

  -- DEPOIS DE UMA LISTA, A PERGUNTA E PADRAO (Tel, 22/09, caso 159: "faltou ela
  -- perguntar De qual deles a Sra. quer mais informacoes? isso tem que ser
  -- padrao apos o envio de uma lista"). Vem daqui, e nao do prompt, para nao
  -- depender de ela lembrar.
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

COMMIT;
