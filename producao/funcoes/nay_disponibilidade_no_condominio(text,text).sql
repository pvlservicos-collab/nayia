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
  --
  -- 153 (Tel, 28/09): SO DE PARCERIA E O MESMO QUE NADA. "Ela nunca pode falar
  -- isso, os imoveis de parceria estao oficialmente fora de tudo por enquanto"
  -- -- ela tinha dito "No Ibiza Flex o que eu tenho e imovel de parceria, nao da
  -- Imob Easy" (e o mesmo no Turim, no Brisas do Parque e no Shizen I). O
  -- condominio continua reconhecido (nao vira "nao existe"); so a resposta nao
  -- fala mais em parceria.
  IF coalesce(v_venda_n,0) = 0 AND coalesce(v_loc_n,0) = 0 THEN
    RETURN QUERY SELECT
      ('no ' || v_cond || ' não tenho nada disponível no momento')::text,
      NULL::text,
      ('conhecemos o condominio, mas nao ha imovel disponivel nele agora. '
       || 'Diga isso e pare. NAO diga que vai verificar, NAO escale e NUNCA '
       || 'fale em parceria ou parceiro.')::text;
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
       || 'manda a sugestao de visita logo depois; foto so sai se ele pedir. NAO escale.')::text;
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
