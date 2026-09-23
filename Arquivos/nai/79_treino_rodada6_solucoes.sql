-- =====================================================================
-- NAI -- 79: as solucoes do Tel na rodada 6 de treino (22/09/2026)
--
-- Tudo no SISTEMA, nao no prompt: sao formatos e regras fixas, e o Tel ja
-- disse que ela "ta muito empolgada, isso e contexto grande". Regra que mora
-- no banco nao varia e nao pesa no contexto dela.
--
--   caso 164 -- "recria uma versao da lista melhor e mais organizada", com o
--     modelo dele: um bloco por imovel, "*Imovel 5724* -- Apartamento |
--     2 quartos | R$ 2.600", uma linha de local e, no fim, "Qual dos dois
--     imoveis e de seu interesse? Assim, posso lhe enviar mais informacoes".
--     O modelo trazia "Rua [Nome da Rua]": endereco de rua so pode ir para
--     imovel ADMINISTRADO (regra do imovel_por_codigo), entao a linha de local
--     leva o condominio e o bairro.
--     -> nay_disponibilidade_no_condominio (as duas listas dela).
--
--   caso 159 -- "faltou ela perguntar De qual deles a Sra. quer mais
--     informacoes? isso tem que ser padrao apos o envio de uma lista".
--     -> a mesma pergunta do modelo do 164 fecha a lista da busca por perfil.
--
--   caso 162 -- "se achou so 1 mandar logo o card junto, e oferecer outras
--     opcoes na regiao". -> as duas funcoes: um resultado so vira o CARD. O
--     card faz o sistema mandar as fotos e o fechamento padrao, que ja oferece
--     mais imoveis.
--
--   caso 161 -- "ela perguntou se queria fotos mas depois mandou as fotos,
--     nesse caso espera o cliente responder". -> nai_enfileirar_resposta:
--     resposta com 2+ imoveis que pergunta qual deles nao leva foto.
--
--   pedido do Tel no chat -- foto que o corretor pede DE NOVO sai de novo
--     ("manda de novo conforme solicitado"). A trava de 24h e a de 10 minutos
--     passam a valer so para foto que ele nao pediu.
--     -> nai_conferir_resposta e nai_liberar_saida.
--
-- Funcoes VIVAS copiadas do pg_proc e remendadas trecho por trecho (cada
-- trecho conferido: tem que aparecer uma vez so).
-- =====================================================================

\set ON_ERROR_STOP on

BEGIN;

CREATE OR REPLACE FUNCTION public.nay_disponibilidade_no_condominio(p_nome text, p_negocio text DEFAULT NULL::text)
 RETURNS TABLE(texto_pronto text, codigo text, instrucao_para_voce text)
 LANGUAGE plpgsql
 STABLE
AS $function$
DECLARE
  v_nome    text := btrim(coalesce(p_nome,''));
  v_neg     text := lower(btrim(coalesce(p_negocio,'')));
  v_locacao boolean := v_neg LIKE 'loc%' OR v_neg LIKE 'alug%';
  v_venda   boolean := v_neg LIKE 'vend%' OR v_neg LIKE 'compr%';
  v_chave   text;
  v_faixa   int;
  v_cands   text[];
  v_cond    text;
  v_venda_n int;
  v_loc_n   int;
  v_parc_n  int;
  v_lista   text;
  v_um      text;
  v_n_amb   int;      -- quantos imoveis existem nos condominios ambiguos
  v_teto    int := 8; -- acima disto a lista vira parede de texto
BEGIN
  IF v_nome = '' THEN
    RETURN QUERY SELECT
      'de qual condomínio você fala?'::text, NULL::text,
      'sem o nome do condominio nao da para responder. PERGUNTE o nome.'::text;
    RETURN;
  END IF;

  v_chave := nay_chave_condominio(v_nome);

  -- "Apartamento" e "Casa" existem como condominio_nome no cadastro, e a
  -- chave deles fica VAZIA -- chave vazia casa com tudo por
  -- `position('' in x) > 0`. Por isso os dois lados exigem chave não vazia.
  IF v_chave = '' THEN
    RETURN QUERY SELECT
      'de qual condomínio você fala?'::text, NULL::text,
      ('o que ele escreveu nao tem nome de condominio, so palavra generica. '
       || 'PERGUNTE o nome do condominio.')::text;
    RETURN;
  END IF;

  -- Os candidatos saem de TODO o cadastro: reconhecer o nome não é a mesma
  -- decisão que oferecer o imóvel. Quem filtra parceiro/disponível é a
  -- política de oferta, mais abaixo.
  -- AS CINCO FAIXAS MORAM EM `nay_condominios_candidatos` (envio_por_descricao.sql).
  -- Elas estavam AQUI DENTRO, e por isso só daqui podiam ser usadas -- quando o
  -- comando "envia esses imóveis" precisou do mesmo casamento de nome, a saída
  -- fácil seria copiar as faixas para lá. Copiar regra de casamento é o padrão
  -- 4.3 do HISTORICO, o bug mais caro deste projeto. Então elas saíram para uma
  -- função própria e esta passou a chamá-la, no mesmo commit.
  --
  -- A função devolve SÓ a melhor faixa não vazia, então todas as linhas trazem
  -- a mesma `faixa` e o GROUP BY produz uma linha só (ou nenhuma).
  SELECT c.faixa, array_agg(DISTINCT c.nome ORDER BY c.nome)
    INTO v_faixa, v_cands
    FROM nay_condominios_candidatos(v_nome) c
   GROUP BY c.faixa;

  IF v_faixa IS NULL THEN
    -- NÃO EXISTE NO CADASTRO, nem como parceiro, nem vendido. Decisão do
    -- Tel: isso é resposta, não pergunta. Escalar aqui é mandar o Tel
    -- confirmar o que a consulta já disse -- foi o que travou o Erick por
    -- quinze minutos.
    RETURN QUERY SELECT
      ('não temos imóvel no ' || v_nome || ' no momento')::text, NULL::text,
      ('esse condominio NAO existe no nosso cadastro. Isso e RESPOSTA, nao '
       || 'motivo de escalar: diga que nao temos e NAO diga que vai verificar. '
       || 'Se ele insistir que anunciou, explique que o que nao esta no nosso '
       || 'sistema ja saiu da nossa carteira. NAO chame escalar_ao_tel.')::text;
    RETURN;
  END IF;

  -- Dois ou mais na MESMA faixa: perguntar qual. "Reserva Inglesa" sozinho
  -- é o Liverpool E o London; "Alphaville" é 1, 2, 3 e 4. Escolher um seria
  -- dar resposta sobre o imóvel errado.
  --
  -- A lista só pode conter nome que resolva na volta -- senão ele escolhe o
  -- que ela ofereceu e ouve a mesma pergunta. Com as faixas isso vale
  -- sozinho: nome de cadastro cai na faixa 1.
  IF coalesce(array_length(v_cands,1),0) > 1 THEN
    IF v_faixa >= 4 THEN
      -- Nenhum deles é o nome que ele escreveu. Oferecer é uma coisa;
      -- afirmar "temos mais de um com esse nome" seria dizer que temos.
      RETURN QUERY SELECT
        ('você quis dizer algum destes?' || chr(10)
         || array_to_string(ARRAY(SELECT '• ' || x FROM unnest(v_cands) x), chr(10)))::text,
        NULL::text,
        ('o nome que ele deu NAO bate com condominio nenhum; esses sao os '
         || 'parecidos. Pergunte qual e chame esta ferramenta de novo com o que '
         || 'ele confirmar. NAO afirme que temos nem que nao temos. NAO escale.')::text;
      RETURN;
    END IF;
    -- MOSTRAR OS IMOVEIS, nao os nomes (Tel, 15/09). Ele perguntou "casa no
    -- Itapuranga para alugar" e ouviu de volta tres NOMES de condominio, sem
    -- nenhuma informacao -- e existiam tres casas para alugar, que caberiam na
    -- mesma mensagem. Perguntar "qual deles?" faz o corretor gastar uma volta
    -- para descobrir o que ele ja podia estar vendo.
    --
    -- O TETO existe porque a ambiguidade nem sempre e pequena: neste catalogo
    -- ha raiz de nome com 16, 37 e ate 55 condominios. Acima do teto, a
    -- pergunta pelos nomes continua sendo a resposta certa.
    -- FORMATO DO TEL (22/09, caso 164): um bloco por imovel, o codigo em negrito.
    SELECT string_agg((E'\u2022 *Imóvel ' || i.codigo || E'* \u2014 '
                      || initcap(coalesce(NULLIF(i.tipo, ''), 'imóvel'))
                      || coalesce(' | ' || i.quartos || CASE WHEN i.quartos = 1 THEN ' quarto' ELSE ' quartos' END, '')
                      || ' | R$ ' || replace(to_char(
                           CASE WHEN v_locacao THEN i.valor_aluguel ELSE i.valor_venda END,
                           'FM999,999,990'), ',', '.')
                      || E'\n\U0001F4CD ' || coalesce(nai_condominio_ok(i.condominio_nome), i.condominio_nome)
                      || coalesce(E' \u2014 ' || NULLIF(i.bairro, ''), '')), E'\n\n'
                      ORDER BY i.condominio_nome, i.codigo),
           count(*)
      INTO v_lista, v_n_amb
      FROM imoveis i
     WHERE i.condominio_nome = ANY (v_cands)
       AND nay_esta_no_mercado(i.disponivel, i.bloqueado, i.publicado_no_site)
       AND NOT coalesce(i.e_parceiro, false)
       AND (CASE WHEN v_locacao THEN coalesce(i.valor_aluguel, 0)
                 WHEN v_venda   THEN coalesce(i.valor_venda, 0)
                 ELSE greatest(coalesce(i.valor_aluguel, 0), coalesce(i.valor_venda, 0)) END) > 0;

    IF v_lista IS NOT NULL AND coalesce(v_n_amb, 0) BETWEEN 1 AND v_teto THEN
      RETURN QUERY SELECT
        ('Tenho estas opções:' || E'\n\n' || v_lista || E'\n\n' ||
         CASE WHEN v_n_amb = 2 THEN 'Qual dos dois imóveis é de seu interesse?'
              ELSE 'Qual deles é de seu interesse?' END ||
         ' Assim, posso lhe enviar mais informações e detalhes.')::text,
        CASE WHEN v_n_amb = 1
             THEN (SELECT min(i.codigo::text) FROM imoveis i
                    WHERE i.condominio_nome = ANY (v_cands)
                      AND nay_esta_no_mercado(i.disponivel, i.bloqueado, i.publicado_no_site)
                      AND NOT coalesce(i.e_parceiro, false)) END,
        ('o nome dele bate com mais de um condominio, e os imoveis cabiam na '
         || 'mensagem: repita a lista como veio, com o condominio de cada um. '
         || 'Deixe ele escolher pelo codigo. NAO escale.')::text;
      RETURN;
    END IF;

    RETURN QUERY SELECT
      ('temos mais de um com esse nome. qual deles?' || chr(10)
       || array_to_string(ARRAY(SELECT '• ' || x FROM unnest(v_cands) x), chr(10)))::text,
      NULL::text,
      ('mais de um condominio bate com o nome que ele deu, e sao imoveis demais '
       || 'para listar. Mostre a lista de nomes e deixe ele escolher -- responder '
       || 'por um so seria informacao do imovel errado. NAO escale.')::text;
    RETURN;
  END IF;

  v_cond := v_cands[1];

  -- Faixa 4 é só parecença: o nome que ele escreveu NÃO é este. Confirmar
  -- antes é o mesmo caminho do "você quis dizer Ponta Negra?" da busca por
  -- bairro -- e evita a pior saída deste funil, que é negar com firmeza um
  -- condomínio que ele nem perguntou.
  IF v_faixa >= 4 THEN
    RETURN QUERY SELECT
      ('você quis dizer ' || v_cond || '?')::text, NULL::text,
      ('o nome que ele deu NAO bate com nenhum condominio nosso; o mais '
       || 'parecido e esse. CONFIRME o nome antes de responder qualquer coisa '
       || 'sobre disponibilidade, e chame esta ferramenta de novo com o nome '
       || 'que ele confirmar. NAO afirme que temos nem que nao temos. NAO escale.')::text;
    RETURN;
  END IF;

  SELECT count(*) FILTER (WHERE coalesce(i.valor_venda,0) > 0
                            AND NOT coalesce(i.e_parceiro,false)),
         count(*) FILTER (WHERE coalesce(i.valor_aluguel,0) > 0
                            AND NOT coalesce(i.e_parceiro,false)),
         count(*) FILTER (WHERE coalesce(i.e_parceiro,false))
    INTO v_venda_n, v_loc_n, v_parc_n
    FROM imoveis i
   WHERE i.condominio_nome = v_cond
     -- Contar sem olhar o anúncio faria ela dizer "temos" de imóvel que
     -- saiu do site. `e_parceiro` continua fora daqui, nos FILTER acima:
     -- "é de parceria" e "não tenho nada" são respostas diferentes.
     AND nay_esta_no_mercado(i.disponivel, i.bloqueado, i.publicado_no_site);

  -- Conhecemos o condomínio e não temos NADA para oferecer nele. As duas
  -- respostas abaixo são diferentes de "não existe", e é justamente essa
  -- diferença que a primeira versão apagava.
  IF coalesce(v_venda_n,0) = 0 AND coalesce(v_loc_n,0) = 0 THEN
    IF coalesce(v_parc_n,0) > 0 THEN
      RETURN QUERY SELECT
        ('no ' || v_cond || ' o que eu tenho é imóvel de parceria, não da Imob Easy')::text,
        NULL::text,
        ('esse condominio existe, mas so temos imovel de PARCERIA nele -- nao e '
         || 'da nossa carteira. Diga isso e pare. NAO chame escalar_ao_tel.')::text;
    ELSE
      RETURN QUERY SELECT
        ('no ' || v_cond || ' não tenho nada disponível no momento')::text,
        NULL::text,
        ('conhecemos o condominio, mas nao ha imovel disponivel nele agora. '
         || 'Diga isso e pare. NAO diga que vai verificar e NAO escale.')::text;
    END IF;
    RETURN;
  END IF;

  -- Ele disse o negócio e não temos nada nele: é resposta, não escalação.
  IF v_locacao AND coalesce(v_loc_n,0) = 0 THEN
    RETURN QUERY SELECT
      ('no ' || v_cond || ' não tenho nada para locação no momento'
       || CASE WHEN coalesce(v_venda_n,0) > 0
               THEN ', só para venda' ELSE '' END)::text,
      NULL::text,
      ('nao ha imovel de LOCACAO nesse condominio. Diga isso e pare: se nao '
       || 'esta no sistema, ja saiu da carteira. NAO diga que vai verificar e '
       || 'NAO chame escalar_ao_tel.')::text;
    RETURN;
  END IF;

  IF v_venda AND coalesce(v_venda_n,0) = 0 THEN
    RETURN QUERY SELECT
      ('no ' || v_cond || ' não tenho nada para venda no momento'
       || CASE WHEN coalesce(v_loc_n,0) > 0
               THEN ', só para locação' ELSE '' END)::text,
      NULL::text,
      ('nao ha imovel de VENDA nesse condominio. Diga isso e pare. NAO diga '
       || 'que vai verificar e NAO chame escalar_ao_tel.')::text;
    RETURN;
  END IF;

  -- Ele não disse o negócio e temos os dois: perguntar é o certo aqui.
  IF NOT v_locacao AND NOT v_venda
     AND coalesce(v_venda_n,0) > 0 AND coalesce(v_loc_n,0) > 0 THEN
    RETURN QUERY SELECT
      ('no ' || v_cond || ' tenho ' || v_venda_n || ' para venda e '
       || v_loc_n || ' para locação. é venda ou locação?')::text,
      NULL::text,
      ('temos os DOIS negocios nesse condominio. Pergunte qual e chame esta '
       || 'ferramenta de novo com a resposta dele. NAO escale.')::text;
    RETURN;
  END IF;

  -- Tem o que ele quer. Lista, e devolve o código quando é um só.
  -- FORMATO DO TEL (22/09, caso 164): um bloco por imovel, o codigo em negrito.
  SELECT string_agg((E'\u2022 *Imóvel ' || i.codigo || E'* \u2014 '
                      || initcap(coalesce(NULLIF(i.tipo, ''), 'imóvel'))
                      || coalesce(' | ' || i.quartos || CASE WHEN i.quartos = 1 THEN ' quarto' ELSE ' quartos' END, '')
                      || ' | R$ ' || replace(to_char(
                           CASE WHEN v_locacao OR (NOT v_venda AND coalesce(v_loc_n,0) > 0) THEN i.valor_aluguel ELSE i.valor_venda END,
                           'FM999,999,990'), ',', '.')
                      || E'\n\U0001F4CD ' || coalesce(nai_condominio_ok(i.condominio_nome), i.condominio_nome)
                      || coalesce(E' \u2014 ' || NULLIF(i.bairro, ''), '')),
                    E'\n\n' ORDER BY i.codigo),
         min(i.codigo::text)
    INTO v_lista, v_um
    FROM imoveis i
   WHERE i.condominio_nome = v_cond
     AND nay_esta_no_mercado(i.disponivel, i.bloqueado, i.publicado_no_site)
     AND NOT coalesce(i.e_parceiro, false)
     AND (CASE WHEN v_locacao OR (NOT v_venda AND coalesce(v_loc_n,0) > 0)
               THEN coalesce(i.valor_aluguel,0) ELSE coalesce(i.valor_venda,0) END) > 0;

  -- Cinto e suspensório: nenhum caminho pode afirmar "sim, temos" com lista
  -- vazia. Antes ele podia -- bastava um UPDATE de `bloqueado`.
  IF v_lista IS NULL THEN
    RETURN QUERY SELECT
      ('no ' || v_cond || ' não tenho nada disponível no momento')::text,
      NULL::text,
      ('nao sobrou nenhum imovel para listar nesse condominio. Diga que nao '
       || 'tem e pare. NAO escale.')::text;
    RETURN;
  END IF;

  -- UM SO: vai o CARD, nao uma lista de um item (Tel, 22/09, caso 162: "se
  -- achou so 1 mandar logo o card junto"). O card traz "Codigo:", e e isso que
  -- faz o sistema mandar as fotos e o fechamento padrao, que ja oferece mais
  -- imoveis ("ou se quiser mais imoveis me fala o que esta procurando").
  -- Conta o que esta NA LISTA, nao o condominio inteiro: com 1 para venda e
  -- 1 para locacao, quem pediu venda ve um so.
  IF (SELECT count(*) FROM regexp_matches(v_lista, '[*]Imóvel [0-9]+[*]', 'g')) = 1
     AND (SELECT cc.texto_pronto FROM nai_card_do_imovel((regexp_match(v_lista, '[*]Imóvel ([0-9]+)[*]'))[1]::int) cc) IS NOT NULL THEN
    RETURN QUERY SELECT
      (SELECT cc.texto_pronto FROM nai_card_do_imovel((regexp_match(v_lista, '[*]Imóvel ([0-9]+)[*]'))[1]::int) cc),
      (regexp_match(v_lista, '[*]Imóvel ([0-9]+)[*]'))[1],
      ('e um imovel so nesse condominio: mande o card EXATAMENTE como veio. O sistema '
       || 'manda as fotos e a sugestao de visita logo depois. NAO escale.')::text;
    RETURN;
  END IF;

  RETURN QUERY SELECT
    ('Sim, temos estas opções disponíveis no ' || v_cond || ':' || E'\n\n' || v_lista || E'\n\n' ||
     CASE WHEN (SELECT count(*) FROM regexp_matches(v_lista, '[*]Imóvel [0-9]+[*]', 'g')) = 2
          THEN 'Qual dos dois imóveis é de seu interesse?'
          ELSE 'Qual deles é de seu interesse?' END ||
     ' Assim, posso lhe enviar mais informações e detalhes.')::text,
    CASE WHEN (coalesce(v_loc_n,0) + coalesce(v_venda_n,0)) = 1 THEN v_um ELSE NULL END,
    ('esta disponivel. Repita a lista como veio. Se for UM imovel so, o codigo '
     || 'veio preenchido e voce ja pode seguir com ele -- ele identificou o '
     || 'imovel pelo NOME do condominio, que vale tanto quanto o codigo.')::text;
END;
$function$;

CREATE OR REPLACE FUNCTION public.nai_buscar_por_perfil(p_turno bigint, p_bairro text, p_teto text, p_quartos text, p_mobilia text)
 RETURNS TABLE(texto_pronto text, instrucao_para_voce text)
 LANGUAGE plpgsql
 STABLE
AS $function$
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
  v_direta boolean;   -- entrou PEDINDO imovel, sem vir de um card
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

  -- A SEQUENCIA DO FLUXO (cards do Tel): bairro -> faixa de preco -> mobilia,
  -- UMA PERGUNTA POR MENSAGEM. Quem manda a pergunta e esta funcao, nao o
  -- modelo: em 12/09 ele juntou duas perguntas numa mensagem so, duas vezes.
  -- Enquanto faltar resposta, ela devolve a PROXIMA pergunta e nada mais.
  IF nullif(btrim(coalesce(p_bairro, '')), '') IS NULL THEN
    RETURN QUERY SELECT
      CASE WHEN v_direta
           -- ele chegou pedindo: nao existe "tambem", porque ela ainda nao
           -- ofereceu nada.
           THEN 'Claro! Você está procurando imóveis em qual bairro?'
           ELSE 'Eu também tenho outras opções de locação, você está procurando imóveis em qual bairro?'
      END::text,
      ('etapa 1 de ' || CASE WHEN v_direta THEN '2' ELSE '3' END || ' da sequencia. Diga SO essa pergunta, '
       || 'sem listar imovel nenhum e sem juntar outra pergunta. Quando ele responder, chame '
       || 'buscar_por_perfil de novo com o bairro.')::text;
    RETURN;
  END IF;
  IF nullif(btrim(coalesce(p_teto, '')), '') IS NULL THEN
    RETURN QUERY SELECT 'E qual a faixa de preço que seus clientes estão buscando?'::text,
      ('etapa 2 de ' || CASE WHEN v_direta THEN '2' ELSE '3' END || ' da sequencia. Diga SO essa pergunta, '
       || 'sem listar imovel nenhum e sem juntar outra pergunta. Quando ele responder, chame '
       || 'buscar_por_perfil de novo com bairro e teto.')::text;
    RETURN;
  END IF;
  -- A MOBILIA e a terceira pergunta SO de quem veio do grupo. Quem chegou
  -- pedindo imovel responde duas e ja ve a lista (Tel, 15/09: "essas 2
  -- perguntas padroes e mais filtros so se o cliente ja pedir"). Se ele falar
  -- de mobilia por conta propria, o filtro entra do mesmo jeito -- o valor
  -- chega em p_mobilia e e usado logo abaixo.
  IF NOT v_direta AND nullif(btrim(coalesce(p_mobilia, '')), '') IS NULL THEN
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
    v_txt := 'No ' || v_nome_b || ' eu tenho estas opções:' || E'\n\n' || v_aqui;
    IF v_alt IS NOT NULL THEN
      v_txt := v_txt || E'\n\n' || 'E tenho estas aqui perto:' || E'\n\n' || v_alt;
    END IF;
  ELSE
    v_txt := 'No ' || v_nome_b || ', não tenho nenhum imóvel nesse perfil disponível no momento.' || E'\n\n' ||
             'Mas tenho estas opções aqui perto:' || E'\n\n' || v_alt;
  END IF;

  -- DEPOIS DE UMA LISTA, A PERGUNTA E PADRAO (Tel, 22/09, caso 159: "faltou ela
  -- perguntar De qual deles a Sra. quer mais informacoes? isso tem que ser
  -- padrao apos o envio de uma lista"). Vem daqui, e nao do prompt, para nao
  -- depender de ela lembrar.
  v_txt := v_txt || E'\n\n' || 'Qual deles é de seu interesse? Assim, posso lhe enviar mais informações e detalhes.';

  RETURN QUERY SELECT v_txt,
    ('mande o texto_pronto EXATAMENTE como veio: cada imovel no seu bloco, com o icone, o negrito e as linhas com •. '
     || 'NAO resuma, NAO junte tudo numa linha, NAO reescreva e NAO invente imovel que nao esta na lista. '
     || 'Se ele quiser detalhe de um, chame imovel_por_codigo. NAO sugira visita aqui.')::text;
END;
$function$;

CREATE OR REPLACE FUNCTION public.nai_enfileirar_resposta(p_turno bigint, p_texto text, p_codigos jsonb, p_escreveu text, p_fotos_site jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
AS $function$
DECLARE
  t        nai_turno;
  d        jsonb;
  v_texto  text;
  v_cods   int[];
  v_gate   boolean;
  v_cod    int;
  v_ordem  int := 0;
  v_ini    int := 1;
  v_bloco  text;
  v_resto  text;
  m        record;
  f        record;
  v_fotos  int := 0;
  v_textos int := 0;
BEGIN
  SELECT * INTO t FROM nai_turno WHERE id = p_turno;
  IF t.id IS NULL THEN RETURN jsonb_build_object('ok', false, 'motivo', 'turno_inexistente'); END IF;

  d := nai_conferir_resposta(p_turno, p_texto, p_codigos, p_escreveu, p_fotos_site);
  IF d->>'acao' <> 'responder' THEN
    RETURN jsonb_build_object('ok', d->>'acao' <> 'parou' OR (d->>'motivo') IS NULL,
                              'textos', 0, 'fotos', 0, 'guarda', d->>'guarda',
                              'motivo', d->>'motivo');
  END IF;

  v_texto := d->>'texto';
  v_gate  := coalesce((d->>'gate')::boolean, false);
  -- ELA PERGUNTOU QUAL, ENTAO ESPERA (Tel, 22/09, caso 161: "ela perguntou se
  -- queria fotos mas depois mandou as fotos, nesse caso espera o cliente
  -- responder"). Resposta com dois ou mais imoveis que termina perguntando
  -- qual deles: vai o texto, e nenhuma foto -- as fotos saem quando ele
  -- escolher.
  IF v_gate
     AND coalesce(array_length(nay_codigos_citados(coalesce(d->>'texto', '')), 1), 0) >= 2
     AND lower(unaccent(coalesce(d->>'texto', ''))) ~
         '(qual|quais) (dos|das|deles|delas|desses|dessas|dois|duas|imove|interessa|prefere|o sr|a sra|voce)' THEN
    v_gate := false;
  END IF;
  SELECT coalesce(array_agg(x::int), '{}') INTO v_cods FROM jsonb_array_elements_text(coalesce(d->'cods', '[]'::jsonb)) x;

  -- COM CARD: cada bloco termina no seu "Código: NNNN" e leva as fotos dele.
  IF v_texto ~* 'C[óo]digo:\s*\d{3,5}' AND (v_gate OR position('📍' IN v_texto) > 0) THEN
    FOR m IN SELECT (regexp_matches(v_texto, '(C[óo]digo:\s*(\d{3,5}))', 'gi')) AS g LOOP
      v_cod := m.g[2]::int;
      v_bloco := substr(v_texto, v_ini, strpos(substr(v_texto, v_ini), m.g[1]) + length(m.g[1]) - 1);
      v_ini := v_ini + length(v_bloco);
      v_ordem := v_ordem + 1;
      PERFORM nai_enfileirar_texto(p_turno, NULL, t.contato_id, 'turno', v_bloco, 'resposta', v_ordem);
      v_textos := v_textos + 1;
      IF v_gate THEN
        FOR f IN SELECT * FROM nai_imagens_do_envio(v_cod) LOOP
          v_ordem := v_ordem + 1;
          INSERT INTO nai_saida (turno_id, contato_id, papel_destino, chave_destino, tipo, imagem_url, codigo, ordem, motivo)
               VALUES (p_turno, t.contato_id, 'turno', '', 'imagem', f.url, v_cod, v_ordem,
                       CASE WHEN f.e_colagem THEN 'colagem' ELSE 'foto' END);
          v_fotos := v_fotos + 1;
        END LOOP;
      END IF;
    END LOOP;
    v_resto := btrim(substr(v_texto, v_ini), ' ' || chr(9) || chr(10) || chr(13));
    IF v_fotos > 0 AND (v_resto = '' OR nai_so_anuncia_fotos(v_resto) OR nai_pergunta_qual_imovel(v_resto)) THEN
      PERFORM nai_depois_das_fotos(p_turno, v_ordem);
      v_textos := v_textos + 2;
    ELSIF v_resto <> '' THEN
      PERFORM nai_enfileirar_texto(p_turno, NULL, t.contato_id, 'turno', nai_sem_pergunta_de_identidade(nai_sem_emoji_resposta(v_resto)), 'resposta', v_ordem + 1);
      v_textos := v_textos + 1;
      -- O PADRAO DE ATENDIMENTO VAI JUNTO (Tel, 21/09). Mandou card com foto,
      -- o fechamento sai SEMPRE -- depois da frase dela, nao no lugar dela.
      -- Antes so saia quando ela nao tinha mais nada a dizer, e bastava ela
      -- escrever uma linha a mais para o padrao sumir: em 19/09, dois dos
      -- quatro cards do dia sairam sem fechamento por causa disso.
      IF v_fotos > 0 THEN
        PERFORM nai_depois_das_fotos(p_turno, v_ordem + 1);
        v_textos := v_textos + 2;
      END IF;
    END IF;
  ELSE
    -- SEM CARD: as fotos primeiro, a frase depois (pedido do Tel em 31/08).
    IF v_gate THEN
      FOR f IN SELECT g.* FROM unnest(v_cods) WITH ORDINALITY AS c(cod, i)
                CROSS JOIN LATERAL nai_imagens_do_envio(c.cod) g
                ORDER BY c.i LOOP
        v_ordem := v_ordem + 1;
        INSERT INTO nai_saida (turno_id, contato_id, papel_destino, chave_destino, tipo, imagem_url, codigo, ordem, motivo)
             VALUES (p_turno, t.contato_id, 'turno', '', 'imagem', f.url, f.codigo, v_ordem,
                     CASE WHEN f.e_colagem THEN 'colagem' ELSE 'foto' END);
        v_fotos := v_fotos + 1;
      END LOOP;
    END IF;
    IF v_fotos > 0 AND (nai_so_anuncia_fotos(v_texto) OR nai_pergunta_qual_imovel(v_texto)) THEN
      PERFORM nai_depois_das_fotos(p_turno, v_ordem);
      v_textos := 2;
    -- ELE pediu foto e nao se sabe o imovel: a pergunta certa, UMA vez. Antes
    -- isto se apoiava no portao (`v_gate`), que agora esta sempre aberto e e
    -- fechado de volta quando nao ha imovel -- entao a condicao passa a olhar
    -- o que ELE escreveu, que e o que de fato importa aqui.
    ELSIF v_fotos = 0 AND coalesce(nai_pede_foto(p_escreveu), false)
          AND coalesce(array_length(v_cods, 1), 0) = 0
          AND (v_texto = '' OR nai_so_anuncia_fotos(v_texto) OR nai_pergunta_qual_imovel(v_texto)) THEN
      -- Pediu foto e NENHUM imóvel foi identificado: a pergunta certa, UMA vez.
      PERFORM nai_enfileirar_texto(p_turno, NULL, t.contato_id, 'turno',
        'De qual imóvel o Sr. quer as fotos? Me passa o código que eu já mando.', 'foto_sem_imovel', v_ordem + 1);
      v_textos := 1;
    ELSIF v_fotos = 0 AND v_gate AND coalesce(array_length(v_cods, 1), 0) > 0
          AND (v_texto = '' OR nai_so_anuncia_fotos(v_texto) OR nai_pergunta_qual_imovel(v_texto)) THEN
      -- 14/09 (teste do Tel): ele marcou o card do 5737, o imóvel FOI
      -- identificado, mas estava sem foto -- e ela perguntou "de qual imóvel o
      -- Sr. quer as fotos?". Imóvel conhecido e sem foto: não se pergunta de qual
      -- imóvel, não se promete foto. O Tel já foi avisado na conferência 17.
      v_textos := 0;
    ELSIF v_texto <> '' THEN
      PERFORM nai_enfileirar_texto(p_turno, NULL, t.contato_id, 'turno', nai_sem_pergunta_de_identidade(nai_sem_emoji_resposta(v_texto)), 'resposta', v_ordem + 1);
      v_textos := 1;
    END IF;
  END IF;

  -- A sugestão do Tel, sozinha, depois de tudo. Nunca junto de foto e NUNCA num
  -- pedido de foto (14/09: "sugeriu visita e outros imóveis antes de mandar as
  -- fotos, sendo que isso é só depois"). Depois das fotos quem convida é o
  -- "depois das fotos".
  IF coalesce((d->>'sugerir')::boolean, false) THEN
    IF v_fotos > 0 THEN
      -- AS FOTOS FORAM JUNTO (Tel, 16/09). Antes a sugestao so saia quando NAO
      -- havia foto, porque foto so saia a pedido e o texto era so o anuncio
      -- ("aqui estao as fotos") -- e ali quem convidava era o "depois das
      -- fotos". Agora que a foto acompanha a ficha, sem esta linha o convite
      -- nunca mais sairia: o texto tem conteudo, entao nao entra no caminho do
      -- anuncio, e o `v_fotos = 0` fechava o outro.
      IF NOT EXISTS (SELECT 1 FROM nai_saida s
                      WHERE s.turno_id = p_turno AND s.motivo = 'depois_das_fotos') THEN
        PERFORM nai_depois_das_fotos(p_turno, v_ordem + 5);
        v_textos := v_textos + 2;
      END IF;
    ELSIF NOT v_gate THEN
      PERFORM nai_enfileirar_texto(p_turno, NULL, t.contato_id, 'turno',
        'Quer fazer uma visita? Só me informar um horário', 'sugere_visita', v_ordem + 5);
      PERFORM nai_enfileirar_texto(p_turno, NULL, t.contato_id, 'turno',
        'Ou se tiver alguma dúvida ou quiser mais imóveis me fala o que está procurando, que já vejo aqui para você, ok?',
        'sugere_visita', v_ordem + 6);
      UPDATE nai_contato SET visita_sugerida_em = now() WHERE id = t.contato_id;
      v_textos := v_textos + 2;
    END IF;
  END IF;

  PERFORM nai_anotar(p_turno, 20, 'montagem', 'passou', v_textos || ' mensagens e ' || v_fotos || ' fotos na caixa de saída');

  RETURN jsonb_build_object('ok', true, 'textos', v_textos, 'fotos', v_fotos, 'guarda', d->>'guarda',
                            'mandou_fotos', v_gate, 'codigos', to_jsonb(v_cods));
END;
$function$;

CREATE OR REPLACE FUNCTION public.nai_conferir_resposta(p_turno bigint, p_texto text, p_codigos jsonb, p_escreveu text, p_fotos_site jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
AS $function$
DECLARE
  t        nai_turno;
  k        nai_contato;
  v_texto  text := btrim(coalesce(p_texto, ''));
  v_guarda text;
  v_alvo   int;
  v_cods   int[];
  v_sem    int[] := '{}';
  v_gate   boolean := false;
  v_sugerir boolean := false;
  v_base   text;
  v_novo   text;
  v_corretor boolean;
  v_calada boolean;
  c_ok     int;
  c_card   text;
  v_n      int;
BEGIN
  SELECT * INTO t FROM nai_turno WHERE id = p_turno;
  IF t.id IS NULL THEN RETURN jsonb_build_object('acao', 'parou', 'motivo', 'turno_inexistente'); END IF;
  SELECT * INTO k FROM nai_contato WHERE id = t.contato_id;
  v_corretor := t.papel = 'corretor';
  v_calada := v_texto = '' OR upper(v_texto) ~ '^\W*SIL[EÊ]NCIO\W*$';

  -- 01 -------------------------------------------------- DE QUAL IMÓVEL É
  -- O código do turno (card marcado, card da resposta, o que ele escreveu) e,
  -- faltando esse, o imóvel da CONVERSA. O turno guarda o que achou: é o fio
  -- para a mensagem seguinte ("me manda as fotos dele").
  SELECT CASE WHEN count(DISTINCT x) = 1 THEN min(x)::int END INTO v_alvo
    FROM jsonb_array_elements_text(coalesce(p_codigos, '[]'::jsonb)) x WHERE x ~ '^[0-9]{3,5}$' AND x::int > 0;
  IF v_alvo IS NULL THEN v_alvo := nai_imovel_da_conversa(t.contato_id, p_escreveu); END IF;
  IF v_alvo IS NOT NULL THEN
    UPDATE nai_turno SET codigo = v_alvo WHERE id = p_turno AND codigo IS DISTINCT FROM v_alvo;
  END IF;
  PERFORM nai_anotar(p_turno, 1, 'imovel_da_conversa',
                     CASE WHEN v_alvo IS NULL THEN 'passou' ELSE 'mudou' END,
                     coalesce('imóvel ' || v_alvo, 'nenhum imóvel identificado'));

  -- 02 ------------------------------------------- FOTOS LIDAS NO SITE (camada 2)
  v_n := nai_gravar_fotos_do_site(p_fotos_site);
  PERFORM nai_anotar(p_turno, 2, 'fotos_do_site', CASE WHEN v_n > 0 THEN 'mudou' ELSE 'passou' END,
                     CASE WHEN v_n > 0 THEN v_n || ' fotos gravadas do anúncio' END);

  -- 03 --------------------------------- PERGUNTA SEM RESPOSTA / PROMESSA DE RETORNO
  -- Não existe "vou ver e te aviso": ou responde com a base, ou o Tel responde.
  IF v_corretor AND NOT (coalesce(t.ferramentas, '{}') && ARRAY['escalar', 'visita']::text[])
     AND ((v_calada AND coalesce(p_escreveu, '') ~ '\?') OR v_texto ~* nai_re_promessa()) THEN
    v_base := nai_escalar_calado(p_turno, p_escreveu,
      CASE WHEN v_texto ~* nai_re_promessa() THEN 'prometeu retorno' ELSE 'pergunta sem resposta' END, v_alvo);
    IF v_base IS NULL THEN
      PERFORM nai_anotar(p_turno, 3, 'promessa_ou_sem_resposta', 'parou', 'subiu ao Tel e parou o chat');
      RETURN jsonb_build_object('acao', 'parou', 'guarda', 'sem_resposta_foi_ao_tel');
    END IF;
    v_texto := v_base; v_calada := false; v_guarda := 'respondido_pela_base';
    PERFORM nai_anotar(p_turno, 3, 'promessa_ou_sem_resposta', 'mudou', 'a ficha respondeu no lugar');
  ELSIF v_corretor AND 'escalar' = ANY (coalesce(t.ferramentas, '{}')) AND v_texto ~* nai_re_promessa() THEN
    PERFORM nai_anotar(p_turno, 3, 'promessa_ou_sem_resposta', 'cortou', 'já escalou neste turno: promessa cortada');
    RETURN jsonb_build_object('acao', 'silencio', 'guarda', 'promessa_cortada');
  ELSE
    PERFORM nai_anotar(p_turno, 3, 'promessa_ou_sem_resposta', 'passou', NULL);
  END IF;

  -- 04 ----------------------------------------------- RESPOSTA SEM CONSULTA
  -- Afirmou sobre imóvel sem ter chamado ferramenta nenhuma.
  IF v_corretor AND '_lidas' = ANY (coalesce(t.ferramentas, '{}'))
     AND coalesce(array_length(array_remove(t.ferramentas, '_lidas'), 1), 0) = 0
     AND NOT v_calada
     AND v_texto !~ '\?\s*\S{0,3}\s*$'
     AND (coalesce(p_escreveu, '') ~ '\?' OR coalesce(p_escreveu, '') ~ '\m\d{3,5}\M')
     AND (coalesce(p_escreveu, '') || ' ' || v_texto) ~* nai_re_assunto_imovel()
     AND v_guarda IS DISTINCT FROM 'respondido_pela_base' THEN
    v_base := nai_escalar_calado(p_turno, p_escreveu, 'respondeu sem consultar a base', v_alvo);
    IF v_base IS NULL THEN
      PERFORM nai_anotar(p_turno, 4, 'resposta_sem_consulta', 'parou', 'afirmou sem ferramenta: subiu ao Tel');
      RETURN jsonb_build_object('acao', 'parou', 'guarda', 'resposta_sem_consulta_foi_ao_tel');
    END IF;
    v_texto := v_base; v_guarda := 'respondido_pela_base';
    PERFORM nai_anotar(p_turno, 4, 'resposta_sem_consulta', 'mudou', 'trocada pela resposta da ficha');
  ELSE
    PERFORM nai_anotar(p_turno, 4, 'resposta_sem_consulta', 'passou', NULL);
  END IF;

  -- 05 ------------------------------------------- O FORMATO É DO TEL, NÃO DO MODELO
  IF v_corretor AND v_alvo IS NOT NULL AND coalesce(p_escreveu, '') ~ '\?'
     AND v_texto !~* 'c[óo]digo:'
     AND NOT (coalesce(t.ferramentas, '{}') && ARRAY['escalar', 'visita']::text[]) THEN
    v_base := nai_resposta_da_base(v_alvo, p_escreveu);
    IF v_base IS NOT NULL AND v_texto IS DISTINCT FROM v_base THEN
      v_texto := v_base; v_calada := false;
      v_guarda := coalesce(v_guarda || '+', '') || 'formato_da_base';
      PERFORM nai_anotar(p_turno, 5, 'formato_da_base', 'mudou', 'resposta da ficha, no formato dele');
    ELSE
      PERFORM nai_anotar(p_turno, 5, 'formato_da_base', 'passou', NULL);
    END IF;
  ELSE
    PERFORM nai_anotar(p_turno, 5, 'formato_da_base', 'passou', NULL);
  END IF;

  -- 06 ------------------------------------------------------------- SILÊNCIO
  IF v_texto = '' OR upper(v_texto) ~ '^\W*SIL[EÊ]NCIO\W*$' THEN
    PERFORM nai_anotar(p_turno, 6, 'silencio', 'parou', 'ela não responde nada, de propósito');
    RETURN jsonb_build_object('acao', 'silencio', 'guarda', v_guarda);
  END IF;
  PERFORM nai_anotar(p_turno, 6, 'silencio', 'passou', NULL);

  -- 07 ---------------------------------------------------- A VOZ DE CADA PAPEL
  IF t.papel IN ('proprietario', 'motoboy') THEN
    v_novo := nai_sem_emoji(v_texto);
    PERFORM nai_anotar(p_turno, 7, 'voz_sem_emoji', CASE WHEN v_novo <> v_texto THEN 'mudou' ELSE 'passou' END,
                       'proprietário e ' || nai_acompanhante() || ': voz da captação');
    v_texto := v_novo;
  ELSE
    PERFORM nai_anotar(p_turno, 7, 'voz_sem_emoji', 'passou', NULL);
  END IF;

  -- 08 ------------------------------------------ SUGERIR VISITA (uma vez por dia)
  IF v_corretor AND v_texto !~ '\?'
     AND (v_guarda LIKE '%respondido_pela_base%' OR v_guarda LIKE '%formato_da_base%' OR v_texto ~* '^\s*sobre isso:'
          OR coalesce(t.ferramentas, '{}') && ARRAY['o_que_sei_do_imovel', 'imovel_por_codigo',
                                                    'disponibilidade_no_condominio', 'listar_no_condominio',
                                                    'resumo_do_condominio']::text[])
     AND NOT (coalesce(t.ferramentas, '{}') && ARRAY['escalar', 'visita']::text[])
     AND v_texto !~* nai_re_sugere_visita()
     AND coalesce((k.visita_sugerida_em AT TIME ZONE 'America/Manaus')::date, date '1900-01-01')
         <> (now() AT TIME ZONE 'America/Manaus')::date
     AND NOT EXISTS (SELECT 1 FROM nai_visita x WHERE x.corretor_id = k.id AND nai_visita_aberta(x.estado)) THEN
    v_sugerir := true;
    PERFORM nai_anotar(p_turno, 8, 'sugerir_visita', 'mudou', 'sai em outra mensagem, depois da resposta');
  ELSE
    PERFORM nai_anotar(p_turno, 8, 'sugerir_visita', 'passou', NULL);
  END IF;

  -- 09 ------------------------------------------ SUGESTÃO REPETIDA NO MESMO DIA
  IF v_corretor AND v_texto ~* nai_re_sugere_visita()
     AND NOT coalesce(nay_pede_visita(coalesce(p_escreveu, '')), false)
     AND NOT EXISTS (SELECT 1 FROM nai_visita x WHERE x.corretor_id = k.id AND x.estado IN ('coletando', 'negociando')) THEN
    IF (k.visita_sugerida_em AT TIME ZONE 'America/Manaus')::date = (now() AT TIME ZONE 'America/Manaus')::date THEN
      v_texto := btrim(regexp_replace(v_texto, '(\m(e|se)\s+)?' || nai_re_sugere_visita() || '[^?!\n]*[?!]?', '', 'gi'));
      v_guarda := 'visita_repetida_cortada';
      PERFORM nai_anotar(p_turno, 9, 'sugestao_repetida', 'cortou', 'já sugeriu visita hoje');
      IF v_texto = '' THEN
        RETURN jsonb_build_object('acao', 'silencio', 'guarda', v_guarda);
      END IF;
    ELSE
      UPDATE nai_contato SET visita_sugerida_em = now() WHERE id = k.id;
      PERFORM nai_anotar(p_turno, 9, 'sugestao_repetida', 'passou', 'primeira sugestão do dia, registrada');
    END IF;
  ELSE
    PERFORM nai_anotar(p_turno, 9, 'sugestao_repetida', 'passou', NULL);
  END IF;

  -- 10 --------------------------------------------- NEGOU IMÓVEL QUE EXISTE
  IF v_corretor AND v_texto ~* nai_re_nega_imovel() THEN
    SELECT i.codigo INTO c_ok
      FROM unnest(coalesce(nay_codigos_citados(coalesce(p_escreveu, '')), '{}'::text[])) x
      JOIN imoveis i ON i.codigo::text = x
     WHERE x ~ '^[0-9]{3,5}$'
       AND nay_esta_no_mercado(i.disponivel, i.bloqueado, i.publicado_no_site)
     ORDER BY i.codigo LIMIT 1;
    IF c_ok IS NOT NULL THEN
      SELECT texto_pronto INTO c_card FROM nai_card_do_imovel(c_ok);
      IF coalesce(c_card, '') <> '' THEN
        v_texto := c_card;
        v_guarda := coalesce(v_guarda || '+', '') || 'negou_imovel_que_existe';
        PERFORM nai_anotar(p_turno, 10, 'negou_imovel_que_existe', 'mudou', 'negativa trocada pelo card do ' || c_ok);
      END IF;
    ELSE
      PERFORM nai_anotar(p_turno, 10, 'negou_imovel_que_existe', 'passou', 'negou, mas o código não é nosso ou não está no ar');
    END IF;
  ELSE
    PERFORM nai_anotar(p_turno, 10, 'negou_imovel_que_existe', 'passou', NULL);
  END IF;

  -- 11 -------------------------------------- FRASE DE VISITA SEM A FERRAMENTA
  IF v_corretor AND NOT ('visita' = ANY (coalesce(t.ferramentas, '{}')))
     AND v_texto ~* nai_re_frase_de_visita() THEN
    v_texto := nai_tirar_frase(v_texto, nai_re_frase_de_visita());
    v_guarda := coalesce(v_guarda || '+', '') || 'visita_sem_ferramenta';
    PERFORM nai_avisar_tel(p_turno, NULL,
      'Tel, o corretor ' || coalesce(k.nome_completo, k.nome_whatsapp, k.telefone) ||
      ' (' || nai_fone_fmt(k.telefone) || ') falou de visita e eu não consegui resolver aqui. Ele disse: "' ||
      left(coalesce(p_escreveu, ''), 300) ||
      E'". Não respondi nada e parei de responder esse chat: quem responde é você. Para eu voltar: DEVOLVER ' || nai_fone_fmt(k.telefone) || '.',
      'visita_sem_ferramenta');
    PERFORM nai_parar_chat(k.id, 'visita que eu nao consegui tratar');
    PERFORM nai_anotar(p_turno, 11, 'visita_sem_ferramenta', 'parou', 'falou de visita sem chamar a ferramenta');
    RETURN jsonb_build_object('acao', 'parou', 'guarda', v_guarda);
  END IF;
  PERFORM nai_anotar(p_turno, 11, 'visita_sem_ferramenta', 'passou', NULL);

  -- 12 ------------------------------------------------------ CITOU O TEL
  IF t.papel IN ('corretor', 'proprietario', 'motoboy') AND v_texto ~* '\mtel\M' THEN
    v_texto := nai_tirar_frase(v_texto, '\mtel\M');
    v_guarda := coalesce(v_guarda || '+', '') || 'citou_o_tel_cortado';
    PERFORM nai_anotar(p_turno, 12, 'citou_o_tel', 'cortou', 'quem sobe para o Tel não conta para ninguém');
    IF v_texto = '' THEN
      RETURN jsonb_build_object('acao', 'silencio', 'guarda', v_guarda);
    END IF;
  ELSE
    PERFORM nai_anotar(p_turno, 12, 'citou_o_tel', 'passou', NULL);
  END IF;

  -- 13 --------------------------------------------- UMA PERGUNTA POR MENSAGEM
  IF v_corretor THEN
    v_novo := nai_uma_pergunta_da_sequencia(v_texto);
    IF v_novo IS NOT NULL THEN
      v_texto := v_novo;
      v_guarda := coalesce(v_guarda || '+', '') || 'sequencia_uma_pergunta';
      PERFORM nai_anotar(p_turno, 13, 'uma_pergunta_por_mensagem', 'mudou', 'juntou duas perguntas: saiu só a primeira');
    ELSE
      PERFORM nai_anotar(p_turno, 13, 'uma_pergunta_por_mensagem', 'passou', NULL);
    END IF;
  ELSE
    PERFORM nai_anotar(p_turno, 13, 'uma_pergunta_por_mensagem', 'passou', NULL);
  END IF;

  -- 14 ------------------------------------------------------------- MARKDOWN
  v_novo := nai_limpar_markdown(v_texto);
  PERFORM nai_anotar(p_turno, 14, 'markdown', CASE WHEN v_novo <> v_texto THEN 'mudou' ELSE 'passou' END, NULL);
  v_texto := v_novo;

  -- 15 ------------------------------------------- DE QUAIS IMÓVEIS SÃO AS FOTOS
  SELECT coalesce(array_agg(DISTINCT x::int), '{}') INTO v_cods
    FROM jsonb_array_elements_text(coalesce(p_codigos, '[]'::jsonb)) x
   WHERE x ~ '^[0-9]{3,5}$' AND x::int > 0;
  IF t.papel IN ('corretor', 'tel') THEN
    -- AS FOTOS VAO SEMPRE (Tel, 16/09): falou de imovel, recebe informacao e
    -- foto na mesma resposta. Antes era preciso pedir "foto" com todas as
    -- letras, e quem escrevia "me encaminha o 5717" recebia so o card.
    v_gate := coalesce(nai_deve_mandar_fotos(t.contato_id, k.telefone, coalesce(p_escreveu, '')), false);
  END IF;
  IF v_gate AND coalesce(array_length(v_cods, 1), 0) = 0 THEN
    v_cods := array_remove(ARRAY[coalesce(v_alvo, nai_imovel_da_conversa(t.contato_id, p_escreveu))], NULL);
  END IF;
  -- SEM IMOVEL NAO HA FOTO. Com o portao sempre aberto, ele continuava "true"
  -- mesmo quando nao se sabe de qual imovel se fala -- e os passos seguintes
  -- tratavam a resposta como se fotos fossem sair. Medido: seis testes de
  -- formato e de sugestao de visita cairam por isso.
  IF v_gate AND coalesce(array_length(v_cods, 1), 0) = 0 THEN
    v_gate := false;
  END IF;

  -- NAO REPETE (Tel, 16/09): "o Tel ja tinha pedido manualmente para ela mandar
  -- as fotos do arezzo, mas ela foi la e mandou novamente". O imovel cujas
  -- fotos ja sairam para esta pessoa hoje sai da lista -- as informacoes
  -- continuam indo, so as fotos e que nao se repetem.
  -- ...A NAO SER QUE ELE PECA (Tel, 22/09: "manda de novo conforme
  -- solicitado"). A trava vale para foto que ele nao pediu.
  IF v_gate AND coalesce(array_length(v_cods, 1), 0) >= 1
     AND NOT nai_pede_foto(coalesce(p_escreveu, '')) THEN
    SELECT coalesce(array_agg(c), '{}') INTO v_cods
      FROM unnest(v_cods) c
     WHERE NOT nai_fotos_ja_mandadas(t.contato_id, c, 24);
    IF coalesce(array_length(v_cods, 1), 0) = 0 THEN
      v_gate := false;
    END IF;
  END IF;

  PERFORM nai_anotar(p_turno, 15, 'portao_de_fotos', CASE WHEN v_gate THEN 'mudou' ELSE 'passou' END,
                     CASE WHEN v_gate THEN 'ele pediu foto; imóveis: ' || coalesce(array_to_string(v_cods, ', '), 'nenhum')
                          ELSE 'ele não pediu foto' END);

  -- 16 ------------------------------- NEGOU FOTO QUE EXISTE / PROMETEU A QUE NÃO
  IF v_gate AND v_texto ~* nai_re_nega_foto() AND coalesce(array_length(v_cods, 1), 0) >= 1 THEN
    SELECT count(*) INTO v_n FROM imovel_fotos WHERE codigo = v_cods[1];
    IF v_n > 0 THEN
      v_texto := regexp_replace(v_texto, '[^.?!\n]*' || nai_re_nega_foto() || '[^.?!\n]*[.?!]?', 'segue as fotos', 'i');
      v_guarda := 'negacao_corrigida';
      PERFORM nai_anotar(p_turno, 16, 'negou_foto_que_existe', 'mudou', 'a foto existe: negativa trocada');
    END IF;
  END IF;
  IF v_gate THEN
    SELECT coalesce(array_agg(c), '{}') INTO v_sem FROM unnest(v_cods) c
     WHERE NOT EXISTS (SELECT 1 FROM imovel_fotos fx WHERE fx.codigo = c);
    IF coalesce(array_length(v_sem, 1), 0) >= 1 THEN
      -- 14/09: antes esta conferência TROCAVA a frase por "as fotos desse eu vou
      -- confirmar com o Tel e já te mando" -- promessa de retorno, que o fluxo
      -- v17 proíbe ("não existe vou ver e te aviso"). Agora a frase de foto
      -- (promessa ou negativa) sai fora e o Tel é avisado; o corretor não recebe
      -- promessa nenhuma.
      v_texto := nai_tirar_frase(v_texto, nai_re_promete_foto() || '|' || nai_re_nega_foto());
      PERFORM nai_avisar_tel(p_turno, NULL,
        'Tel, o corretor ' || coalesce(k.nome_whatsapp, k.telefone) || ' pediu fotos do ' ||
        array_to_string(v_sem, ', ') || ' e não achei foto nem no banco nem no anúncio do site. Pode me mandar?',
        'foto_inexistente');
      v_guarda := coalesce(v_guarda || '+', '') || 'promessa_sem_foto';
      PERFORM nai_anotar(p_turno, 17, 'foto_que_nao_existe', 'mudou', 'imóvel sem foto: o Tel foi avisado');
    ELSE
      PERFORM nai_anotar(p_turno, 17, 'foto_que_nao_existe', 'passou', NULL);
    END IF;
  ELSE
    PERFORM nai_anotar(p_turno, 17, 'foto_que_nao_existe', 'passou', NULL);
  END IF;

  RETURN jsonb_build_object(
    'acao', 'responder',
    'texto', v_texto,
    'guarda', v_guarda,
    'alvo', v_alvo,
    'cods', to_jsonb(v_cods),
    'gate', v_gate,
    'sugerir', v_sugerir);
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
  -- PROPRIETARIO PELO TEL (Tel, 19/09) -- ver o bloco la embaixo.
  v_prop_tel boolean := nai_cfg('proprietario_pelo_tel', 'nao') = 'sim';
  v_fone_prop text;
  v_v        record;
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
             WHERE s2.contato_id = r.contato_id AND s2.estado IN ('enviado', 'simulado', 'enviando')
               AND s2.tipo = 'texto' AND s2.texto = r.texto
               AND s2.visita_id IS NOT DISTINCT FROM r.visita_id
               AND coalesce(s2.enviado_em, s2.criado_em) > greatest(now() - interval '10 minutes',
                     coalesce((SELECT k3.zerado_em FROM nai_contato k3 WHERE k3.id = r.contato_id), '-infinity'::timestamptz))) THEN
      v_bloq := 'repetida';
    -- foto que ELE pediu de novo sai de novo (Tel, 22/09)
    ELSIF r.tipo = 'imagem'
      AND NOT coalesce((SELECT nai_pede_foto(coalesce(tt.texto, '')) FROM nai_turno tt WHERE tt.id = r.turno_id), false)
      AND EXISTS (
            SELECT 1 FROM nai_saida s2
             WHERE s2.contato_id = r.contato_id AND s2.estado IN ('enviado', 'simulado', 'enviando')
               AND s2.tipo = 'imagem' AND s2.imagem_url = r.imagem_url
               AND coalesce(s2.enviado_em, s2.criado_em) > greatest(now() - interval '10 minutes',
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

    -- ---------------------------------------------------------------
    -- PROPRIETARIO PELO TEL (Tel, 19/09): "so as mensagens para
    -- proprietarios estao temporariamente bloqueadas, entao elas vao para o
    -- Tel". O proprietario NAO recebe nada; o Tel recebe o nome e o numero
    -- de quem ele precisa ligar.
    --
    -- Isto NAO e o modo teste: vale em producao (`modo = todos`), e o desvio
    -- do teste continua mandando tudo para o numero de teste, como antes.
    --
    -- O aviso carrega o comando de volta (`VISITA <id> OK`). Sem ele a visita
    -- fica parada para sempre: a Nay pergunta, o Tel liga para o dono, e nao
    -- tem como dizer a ela que o dono confirmou.
    --
    -- `ult_msg_prop_em` continua sendo carimbado no `nai_confirmar_envio`,
    -- de proposito: e o relogio que espaca os lembretes. Sem o carimbo, o
    -- ciclo remarcaria o passo do proprietario na hora e encheria o Tel de
    -- mensagens iguais. E o mesmo que o modo teste ja faz ao redirecionar.
    -- ---------------------------------------------------------------
    IF v_bloq IS NULL AND v_modo = 'todos' AND v_prop_tel
       AND r.papel_destino = 'proprietario' THEN
      SELECT * INTO v_v FROM nai_visita WHERE id = r.visita_id;
      IF r.tipo <> 'texto' OR v_v.id IS NULL THEN
        -- Foto para proprietario nao existe (o gatilho barra na insercao). Se
        -- um dia existir, ela para aqui em vez de virar um desvio improvisado.
        v_bloq := 'prop_pelo_tel_sem_texto';
      ELSE
        v_fone_prop := v_tel;
        v_redir     := true;
        v_tel       := nai_fone_envio(nai_cfg('tel_telefone'));
        v_texto     := 'Visita agendada, pergunte ao proprietário '
          || coalesce(nullif(btrim(coalesce(v_nome, '')), ''),
                      nullif(btrim(coalesce(v_v.proprietario_nome, '')), ''),
                      'do imóvel ' || v_v.codigo)
          || ' de número ' || nai_fone_fmt(v_fone_prop)
          || ' se a visita ' || coalesce(nai_quando_humano(coalesce(v_v.quando, v_v.quando_sugerido)),
                                         'no horário combinado')
          || ' pode ser realizada.'
          || E'\n\nImóvel ' || v_v.codigo || ' · visita #' || v_v.id
          || E'\nMe responda: VISITA ' || v_v.id || ' OK (proprietário confirmou) · VISITA '
          || v_v.id || ' CANCELA · VISITA ' || v_v.id || ' REMARCA 16h'
          || E'\n\n— o que eu ia mandar para ele:\n' || r.texto;
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

COMMIT;
