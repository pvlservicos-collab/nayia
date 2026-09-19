-- "Esse condomínio está disponível?" respondido pelo SISTEMA, sem escalar.
--
-- O CASO (01/09, 13h50): o Erick perguntou por áudio se um empreendimento
-- estava disponível. A Nay pediu o código; ele disse que não tinha ("qndo
-- vem pra mim já veio sem o código"); colou o anúncio inteiro do
-- Liverpool. Ela achou o condomínio, viu que só havia 1 imóvel e era pra
-- venda -- e mesmo assim escalou ao Tel e ficou dizendo "vou verificar e
-- retorno" seis vezes em quinze minutos.
--
-- A DECISÃO DO TEL (01/09), palavra por palavra: "se ela identificar no
-- nosso sistema que só tem para locação ela diz que está disponível, se
-- ela identificar que tem venda e locação ela pergunta se o interesse é
-- para venda ou locação... o imóvel que ele pediu é um liverpool e não
-- tem disponível para locação no sistema, neste caso é só dizer que não
-- está disponível, se não tem no sistema não tem o porque me perguntar".
--
-- E A URGÊNCIA que ele levantou: "ele não consegue identificar por código
-- e vai surgir vários corretores que vão pegar os imóveis para anunciar e
-- não vão lembrar o código, é de extrema urgência que a gente coloque o
-- nome do condomínio também para ela identificar".
--
-- ============ O QUE A AUDITORIA DE 01/09 ACHOU NA PRIMEIRA VERSÃO ============
-- Ela tratava as quatro formas de casar nome como IGUAIS, e montava os
-- candidatos só com imóvel nosso e disponível. Medido contra os nomes do
-- próprio catálogo, o estrago:
--   * quanto MAIS preciso o corretor, PIOR a resposta. "Liverpool" funcionava;
--     "Liverpool Reserva Inglesa" -- o nome exato do cadastro, e o que vem
--     colado no anúncio -- caía em "temos mais de um com esse nome", porque
--     word_similarity com o "London Reserva Inglesa" dá 0.615 contra um
--     limiar de 0.6. E o corretor que escolhe o nome que ela ofereceu ouve a
--     MESMA pergunta: laço fechado. 47 dos 159 nomes não se identificavam.
--   * condomínio que só tem imóvel de parceiro era declarado INEXISTENTE --
--     177 de 387 nomes -- e a instrução mandava não escalar. Resposta final
--     e falsa. Pior: 51 deles resolviam para o condomínio VIZINHO, e a função
--     ainda devolvia o código dele.
--
-- AS TRÊS MUDANÇAS, e o princípio de cada uma:
--   1. FAIXAS DE PRECISÃO. Nome exato ganha de subconjunto, que ganha de
--      substring, que ganha de parecença. Só a melhor faixa não vazia vira
--      candidato -- a ambiguidade passa a valer DENTRO da faixa, nunca entre
--      faixas. Sem isso, o nome certo empata com o vizinho parecido.
--   2. RECONHECER O NOME É UMA COISA; OFERECER É OUTRA. Os candidatos saem de
--      TODO o cadastro (parceiro e indisponível inclusive) e a política de
--      oferta entra depois. "Não é da Imob Easy" e "não tenho nada agora" são
--      respostas diferentes de "esse condomínio não existe" -- e a única que
--      ela não pode dar errado é a terceira.
--   3. PARECENÇA NÃO AFIRMA, PERGUNTA. Casou só por word_similarity? Ela
--      confirma o nome antes ("você quis dizer X?"), como a busca por bairro
--      já faz. Afirmar "não temos" sobre um condomínio que ele não perguntou
--      é o dano sério deste funil.
--
--   docker cp disponibilidade_por_condominio.sql nay-postgres:/tmp/dc.sql
--   docker exec nay-postgres psql -U nay -d naydb -f /tmp/dc.sql

-- A chave de comparação: sem acento, sem pontuação, sem as palavras que
-- todo condomínio tem. "Condomínio Residencial Parque Ajuricaba" e
-- "Ed. Ajuricaba" viram os dois `ajuricaba`.
--
-- O `\s+` no fim não é enfeite: tirar "condominio" e "parque" do meio deixa
-- espaço dobrado, e aí `string_to_array(chave,' ')` devolve elemento vazio,
-- que faz o teste de subconjunto falhar sempre.
CREATE OR REPLACE FUNCTION nay_chave_condominio(p_nome text)
RETURNS text LANGUAGE sql IMMUTABLE AS $fn$
  SELECT btrim(regexp_replace(
           regexp_replace(nay_normalizar_lugar(coalesce(p_nome,''), true),
             '\m(condominio|cond|residencial|resid|edificio|ed|apartamento|apto|'
             || 'parque|torre|bloco)\M', ' ', 'g'),
           '\s+', ' ', 'g'));
$fn$;

CREATE OR REPLACE FUNCTION nay_disponibilidade_no_condominio(
  p_nome    text,
  p_negocio text DEFAULT NULL          -- 'venda', 'locacao' ou nada
) RETURNS TABLE(texto_pronto text, codigo text, instrucao_para_voce text)
LANGUAGE plpgsql STABLE AS $fn$
DECLARE
  v_nome    text := btrim(coalesce(p_nome,''));
  v_neg     text := lower(btrim(coalesce(p_negocio,'')));
  v_locacao boolean := v_neg LIKE 'loc%' OR v_neg LIKE 'alug%';
  v_venda   boolean := v_neg LIKE 'vend%' OR v_neg LIKE 'compr%';
  v_chave   text;
  v_norm    text;
  v_minimo  int;                       -- palavras que a faixa 2 precisa cobrir
  v_faixa   int;
  v_cands   text[];
  v_cond    text;
  v_venda_n int;
  v_loc_n   int;
  v_parc_n  int;
  v_lista   text;
  v_um      text;
BEGIN
  IF v_nome = '' THEN
    RETURN QUERY SELECT
      'de qual condomínio você fala?'::text, NULL::text,
      'sem o nome do condominio nao da para responder. PERGUNTE o nome.'::text;
    RETURN;
  END IF;

  v_norm  := nay_normalizar_lugar(v_nome, true);
  v_chave := nay_chave_condominio(v_nome);
  -- Metade das palavras, arredondando para cima. Ver a faixa 2.
  v_minimo := ceil(coalesce(array_length(string_to_array(v_chave,' '),1),1) / 2.0);

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
  WITH cands AS (
    SELECT DISTINCT i.condominio_nome AS nome,
           nay_chave_condominio(i.condominio_nome) AS chave
      FROM imoveis i
     WHERE coalesce(i.condominio_nome,'') <> ''
  ), com_faixa AS (
    SELECT c.nome,
           CASE
             -- 0. o nome inteiro, letra por letra. Existe porque
             --    "Condomínio Laranjeiras" e "Residencial Laranjeiras" são
             --    DOIS condomínios cuja chave é a mesma palavra: sem esta
             --    faixa, escolher o nome que ela ofereceu devolvia a mesma
             --    pergunta -- laço fechado, não desambiguação.
             WHEN nay_normalizar_lugar(c.nome, true) = v_norm THEN 0
             -- 1. o nome exato do cadastro, sem as palavras genéricas
             WHEN c.chave = v_chave THEN 1
             -- 2. ele escreveu o nome inteiro e mais alguma coisa. Pega a
             --    ordem trocada: "Parque Reserva Inglesa - Liverpool".
             --    O piso de palavras não é enfeite: sem ele o "Parque Verde"
             --    (chave de UMA palavra) engolia "Vila Verde 1" e ela
             --    respondia com firmeza sobre o condomínio do vizinho.
             WHEN string_to_array(c.chave,' ') <@ string_to_array(v_chave,' ')
              AND coalesce(array_length(string_to_array(c.chave,' '),1),0) >= v_minimo THEN 2
             -- 3. ele escreveu um pedaço: "Liverpool"
             WHEN string_to_array(v_chave,' ') <@ string_to_array(c.chave,' ') THEN 3
             -- 4. FAIXA FRACA: pedaço de palavra ou parecença. Daqui não sai
             --    afirmação nenhuma -- só "você quis dizer?".
             WHEN position(v_chave in c.chave) > 0
               OR position(c.chave in v_chave) > 0
               OR word_similarity(v_chave, c.chave) >= 0.6 THEN 4
           END AS faixa
      FROM cands c
     WHERE btrim(c.chave) <> ''
  ), melhor AS (
    SELECT min(f.faixa) AS faixa FROM com_faixa f WHERE f.faixa IS NOT NULL
  )
  -- Faixa e candidatos na MESMA consulta: um CTE não sobrevive ao fim do
  -- comando, e separar em dois SELECT quebra com "relation does not exist".
  SELECT m.faixa,
         (SELECT array_agg(DISTINCT c.nome ORDER BY c.nome)
            FROM com_faixa c WHERE c.faixa = m.faixa)
    INTO v_faixa, v_cands
    FROM melhor m;

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
    RETURN QUERY SELECT
      ('temos mais de um com esse nome. qual deles?' || chr(10)
       || array_to_string(ARRAY(SELECT '• ' || x FROM unnest(v_cands) x), chr(10)))::text,
      NULL::text,
      ('mais de um condominio bate com o nome que ele deu. Mostre a lista e '
       || 'deixe ele escolher -- responder por um so seria informacao do imovel '
       || 'errado. NAO escale.')::text;
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
     AND coalesce(i.disponivel, true)
     AND NOT coalesce(i.bloqueado, false);

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
  SELECT string_agg('• ' || i.codigo || ' — '
                    || coalesce(NULLIF(i.tipo,''), 'imóvel')
                    || coalesce(' — ' || i.quartos || ' quartos', '')
                    || ' — ' || replace(to_char(
                         CASE WHEN v_locacao OR (NOT v_venda AND coalesce(v_loc_n,0) > 0)
                              THEN i.valor_aluguel ELSE i.valor_venda END,
                         'FM999,999,990'),',','.'),
                    chr(10) ORDER BY i.codigo),
         min(i.codigo::text)
    INTO v_lista, v_um
    FROM imoveis i
   WHERE i.condominio_nome = v_cond
     AND coalesce(i.disponivel, true)
     AND NOT coalesce(i.bloqueado, false)
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

  RETURN QUERY SELECT
    ('sim, temos no ' || v_cond || ':' || chr(10) || v_lista)::text,
    CASE WHEN (coalesce(v_loc_n,0) + coalesce(v_venda_n,0)) = 1 THEN v_um ELSE NULL END,
    ('esta disponivel. Repita a lista como veio. Se for UM imovel so, o codigo '
     || 'veio preenchido e voce ja pode seguir com ele -- ele identificou o '
     || 'imovel pelo NOME do condominio, que vale tanto quanto o codigo.')::text;
END;
$fn$;
