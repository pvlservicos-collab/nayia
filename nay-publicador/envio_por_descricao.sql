-- O Tel cola uma LISTA e a Nay descobre de que imóveis ele está falando.
--
-- O PEDIDO (11/09), com o exemplo literal dele:
--
--   Nay envia esses imóveis para o número 92994717316
--   Arezzo Residencial / 2 quartos / 2.5k
--   Ariranhas / 2 quartos / 2.6k (incluso a tx)
--   Estilo Golf / 2 quartos sendo 1 suíte / 2.6k
--   Estilo Golf / 2 quartos sendo 1 suíte / 2.6k
--
-- A DESCOBERTA QUE DEFINE O DESENHO: essas linhas não são texto livre -- são
-- saída LITERAL de `nay_linha_da_lista` (lista_de_imoveis.sql), a mesma que
-- responde `Nay lista de apartamento para locação`. Conferido caractere por
-- caractere nas quatro, inclusive o "(incluso a tx)" do Ariranhas. A prova
-- fina é ele ter escrito "Arezzo RESIDENCIAL": `nay_condominio_de_verdade`
-- mantém a palavra, e o `_nome_curto` do publicador a apagaria.
--
-- Então o casamento é REVERSO, não adivinhação: gera-se a linha de cada
-- candidato e compara-se. Determinístico, e pelo mesmo arquivo que produziu
-- o texto -- se a regra de formatação mudar, os dois lados mudam juntos.
--
-- E é o casamento reverso que EXPLICA a ambiguidade do pedido dele:
-- `nay_linha_da_lista` NÃO É INJETORA. O 5719 e o 5728 são os dois 2 quartos,
-- 1 suíte, aluguel 2.600 no Estilo Golf, e rendem a MESMA string. Foi por
-- isso que a linha apareceu duplicada na colagem. Nenhum casamento desempata
-- isso -- tem que perguntar, como ele mesmo pediu.
--
-- Medido no catálogo de 11/09: das linhas de LOCAÇÃO no mercado, uma única é
-- ambígua (a do Estilo Golf). Na VENDA são 769 imóveis para 745 linhas
-- distintas -- ali a pergunta é rotina, não exceção.
--
--   docker cp envio_por_descricao.sql nay-postgres:/tmp/ed.sql
--   docker exec nay-postgres psql -U nay -d naydb -f /tmp/ed.sql

-- --------------------------------------------------------------------
-- AS CINCO FAIXAS, EXTRAÍDAS.
--
-- O corpo desta função estava dentro do plpgsql de
-- `nay_disponibilidade_no_condominio` e só de lá podia ser usado. Copiar as
-- faixas para cá criaria a SEXTA cópia de uma regra de casamento de nome --
-- o padrão 4.3 do HISTORICO, o bug mais caro deste projeto. Então ela sai
-- para uma função própria e a antiga passa a chamar esta, no mesmo commit.
--
-- `teste_disponibilidade_condominio.sql` é a rede: ele afirma que os 387
-- condomínios do catálogo se resolvem a si mesmos. Se a extração mudou
-- alguma coisa, ele fica vermelho.
--
-- Devolve SÓ a melhor faixa não vazia. A ambiguidade vale DENTRO da faixa,
-- nunca entre faixas -- sem isso, quanto mais preciso o nome, pior a
-- resposta ("Liverpool Reserva Inglesa" empatava com "London Reserva
-- Inglesa" por word_similarity 0.615 contra o limiar 0.6).
CREATE OR REPLACE FUNCTION nay_condominios_candidatos(p_nome text)
RETURNS TABLE(nome text, faixa int)
LANGUAGE sql STABLE AS $fn$
  WITH alvo AS (
    SELECT nay_normalizar_lugar(coalesce(p_nome,''), true) AS norm,
           nay_chave_condominio(coalesce(p_nome,''))       AS chave
  ), pedido AS (
    SELECT a.norm, a.chave,
           -- Metade das palavras, arredondando para cima. Ver a faixa 2.
           ceil(coalesce(array_length(string_to_array(a.chave,' '),1),1) / 2.0) AS minimo
      FROM alvo a
  ), cands AS (
    -- TODO o cadastro: reconhecer o nome não é a mesma decisão que poder
    -- enviar o imóvel. Quem filtra anúncio no ar é o chamador.
    SELECT DISTINCT i.condominio_nome AS nome,
           nay_chave_condominio(i.condominio_nome) AS chave
      FROM imoveis i
     WHERE coalesce(i.condominio_nome,'') <> ''
  ), com_faixa AS (
    SELECT c.nome,
           CASE
             -- 0. o nome inteiro, letra por letra. "Condomínio Laranjeiras" e
             --    "Residencial Laranjeiras" são DOIS condomínios cuja chave é
             --    a mesma palavra: sem esta faixa, escolher o nome que ela
             --    ofereceu devolvia a mesma pergunta -- laço fechado.
             WHEN nay_normalizar_lugar(c.nome, true) = p.norm THEN 0
             -- 1. o nome exato do cadastro, sem as palavras genéricas
             WHEN c.chave = p.chave THEN 1
             -- 2. ele escreveu o nome inteiro e mais alguma coisa. O piso de
             --    palavras não é enfeite: sem ele o "Parque Verde" (chave de
             --    UMA palavra) engolia "Vila Verde 1".
             WHEN string_to_array(c.chave,' ') <@ string_to_array(p.chave,' ')
              AND coalesce(array_length(string_to_array(c.chave,' '),1),0) >= p.minimo THEN 2
             -- 3. ele escreveu um pedaço: "Liverpool"
             WHEN string_to_array(p.chave,' ') <@ string_to_array(c.chave,' ') THEN 3
             -- 4. FAIXA FRACA: pedaço de palavra ou parecença. Daqui não sai
             --    afirmação nenhuma -- só "você quis dizer?".
             WHEN position(p.chave in c.chave) > 0
               OR position(c.chave in p.chave) > 0
               OR word_similarity(p.chave, c.chave) >= 0.6 THEN 4
           END AS faixa
      FROM cands c CROSS JOIN pedido p
     -- Chave vazia casa com TUDO por `position('' in x) > 0`. "Apartamento" e
     -- "Casa" existem como condominio_nome e a chave deles fica vazia.
     WHERE btrim(c.chave) <> '' AND btrim(p.chave) <> ''
  ), melhor AS (
    SELECT min(f.faixa) AS faixa FROM com_faixa f WHERE f.faixa IS NOT NULL
  )
  SELECT c.nome, c.faixa
    FROM com_faixa c, melhor m
   WHERE c.faixa IS NOT NULL AND c.faixa = m.faixa;
$fn$;

-- --------------------------------------------------------------------
-- O VALOR QUE ELE ESCREVEU, em reais.
--
-- As formas são dele, ditas em 11/09: "2.5k", "2.500", "2.6", "2.600",
-- "3.500". Mais as que `nay_valor_curto` produz e ele cola de volta: "280k",
-- "1.2M", "5k".
--
-- POR QUE NÃO SERVE `nay_valor_em_reais`: ela pega o PRIMEIRO número do
-- texto, então "2 quartos 2.500" devolve 2. Esta recebe o token do valor já
-- isolado.
--
-- "2.500" e "2.5" dão o MESMO resultado de propósito -- em português os dois
-- são dois mil e quinhentos, e ele escreve das duas formas. O corte de 1.000
-- é o mesmo de `nay_valor_curto`: abaixo disso, o número está em milhares.
--
-- `trim_scale` porque 2.5*1000 guarda a escala e vira "2500.0", enquanto
-- "2.500" vira "2500" -- o mesmo dinheiro com dois textos. A comparação
-- numérica não se importa, mas o teste e a mensagem ao Tel se importam.
CREATE OR REPLACE FUNCTION nay_valor_escrito(p_token text)
RETURNS numeric LANGUAGE plpgsql IMMUTABLE AS $fn$
DECLARE
  t     text := lower(btrim(coalesce(p_token,'')));
  corpo text;
  n     numeric;
BEGIN
  IF t = '' THEN RETURN NULL; END IF;

  -- POR EXTENSO, do jeito que ele escreve o pedido: "600 mil", "3 milhões",
  -- "1.2 mi". AQUI e não no Python: quem lê dinheiro escrito é UMA função só,
  -- senão a linha colada e o pedido descrito dariam números diferentes.
  --
  -- MEDIDO em 15/09, e por isso existe: "até 3 milhões" caía no ramo do
  -- número solto, e como 3 < 1000 virava R$ 3.000 -- o pedido de venda até
  -- três milhões voltava os imóveis de ALUGUEL até três mil, calado.
  IF t ~ '^[0-9]+([.,][0-9]+)?\s*(milh|mi$)' THEN
    corpo := (regexp_match(t, '^([0-9]+(?:[.,][0-9]+)?)'))[1];
    RETURN trim_scale(replace(corpo, ',', '.')::numeric * 1000000);
  END IF;

  IF t ~ '^[0-9]+([.,][0-9]+)?\s*mil$' THEN
    corpo := (regexp_match(t, '^([0-9]+(?:[.,][0-9]+)?)'))[1];
    RETURN trim_scale(replace(corpo, ',', '.')::numeric * 1000);
  END IF;

  -- milhão: "1.2M", "2.1m"
  IF t ~ '^[0-9]+([.,][0-9]+)?\s*m$' THEN
    corpo := regexp_replace(t, '\s*m$', '');
    RETURN trim_scale(replace(corpo, ',', '.')::numeric * 1000000);
  END IF;

  -- milhar explícito: "2.5k", "280k", "5k"
  IF t ~ '^[0-9]+([.,][0-9]+)?\s*k$' THEN
    corpo := regexp_replace(t, '\s*k$', '');
    RETURN trim_scale(replace(corpo, ',', '.')::numeric * 1000);
  END IF;

  IF t !~ '^[0-9]+([.,][0-9]+)?$' THEN RETURN NULL; END IF;

  -- "2.500" / "2,500": separador de milhar. TRÊS casas depois do ponto é a
  -- marca -- "2.50" não é isso, e "2.5" também não.
  IF t ~ '^[0-9]+[.,][0-9]{3}$' THEN
    RETURN trim_scale(regexp_replace(t, '[.,]', '', 'g')::numeric);
  END IF;

  n := replace(t, ',', '.')::numeric;
  -- "2.6" e "2.5" são dois mil e seiscentos / quinhentos. Nenhum imóvel
  -- deste catálogo custa R$ 2,60.
  IF n < 1000 THEN RETURN trim_scale(n * 1000); END IF;
  RETURN trim_scale(n);
END;
$fn$;

-- --------------------------------------------------------------------
-- AS PARTES DA LINHA que o Tel colou.
--
-- Serve tanto para a linha inteira que veio da lista dela
-- ("Arezzo Residencial / 2 quartos / 2.5k") quanto para a forma curta que
-- ele digita ("Estilo Golf 2.6", "acquarelle de 3 quartos").
--
-- O NOME sai antes da primeira barra; sem barra, antes do primeiro número.
-- "acquarelle de 3 quartos" deixaria um "de" pendurado, e ele sai junto com
-- as outras palavras de ligação.
-- ATUALIZADA EM 28/09 (`codigo_na_linha_da_lista.sql`): a linha passou a
-- trazer "cod NNNN". Rodar a versão antiga deste arquivo DESFARIA a
-- mudança em silêncio -- por isso a definição vive aqui também, igual.
-- Lidas por `nay_partes_da_linha` e `nay_imoveis_da_linha` (28/09).
CREATE OR REPLACE FUNCTION nay_codigo_da_linha(p_linha text)
RETURNS text LANGUAGE sql IMMUTABLE AS $fn$
  SELECT (regexp_match(coalesce(p_linha,''),
                       '\mc[óo]d(?:igo)?\.?\s*:?\s*([0-9]{2,5})\M', 'i'))[1];
$fn$;

CREATE OR REPLACE FUNCTION nay_linha_sem_codigo(p_linha text)
RETURNS text LANGUAGE sql IMMUTABLE AS $fn$
  SELECT btrim(regexp_replace(
           regexp_replace(coalesce(p_linha,''),
                          '\mc[óo]d(?:igo)?\.?\s*:?\s*[0-9]{2,5}\M', ' ', 'gi'),
           '\s+', ' ', 'g'));
$fn$;

CREATE OR REPLACE FUNCTION nay_partes_da_linha(p_linha text)
RETURNS TABLE(nome text, quartos int, suites int, area int, valor numeric)
LANGUAGE plpgsql IMMUTABLE AS $fn$
DECLARE
  t      text;
  v_nome text;
  v_q    int;
  v_s    int;
  v_a    int;
  v_val  numeric;
  tok    text;
BEGIN
  t := btrim(coalesce(p_linha,''));
  t := regexp_replace(t, '^\s*([-*•·✅✔☑]|\d+[.)])\s*', '');
  t := regexp_replace(t, '\(\s*incluso\s+a\s+tx\s*\)', ' ', 'gi');
  t := regexp_replace(t, '[/,]?\s*\+\s*tx\s+de\s+[0-9.,]+', ' ', 'gi');
  -- O CÓDIGO sai aqui (28/09), antes de tudo: ele não identifica o NOME, e
  -- o número dele competiria com o valor na busca do último token numérico.
  t := nay_linha_sem_codigo(t);
  t := btrim(regexp_replace(t, '\s+', ' ', 'g'));
  IF t = '' THEN RETURN; END IF;

  v_q := (regexp_match(t, '([0-9]+)\s*quartos?', 'i'))[1]::int;
  v_s := (regexp_match(t, '([0-9]+)\s*su[íi]tes?', 'i'))[1]::int;
  v_a := (regexp_match(t, '([0-9]+)\s*m(?:2|²)\M', 'i'))[1]::int;

  IF v_q IS NULL AND v_s IS NOT NULL THEN v_q := v_s; END IF;

  t := regexp_replace(t, '[0-9]+\s*quartos?', ' ', 'gi');
  t := regexp_replace(t, '[0-9]+\s*su[íi]tes?', ' ', 'gi');
  t := regexp_replace(t, '[0-9]+\s*m(?:2|²)\M', ' ', 'gi');

  SELECT z.achado INTO tok FROM (
    SELECT x[1] AS achado, row_number() OVER () AS n
      FROM regexp_matches(t || ' ', '([0-9]+(?:[.,][0-9]+)?\s*[kmKM]?)(?:\s|/)', 'g') x
     ORDER BY n DESC LIMIT 1) z;
  v_val := nay_valor_escrito(tok);

  -- O NOME: antes da primeira barra; sem barra, antes do primeiro número.
  -- LÊ DE `p_linha`, não de `t` -- é assim desde 11/09, porque `t` já perdeu
  -- os pedaços que ajudam a cortar. Por isso o código sai DE NOVO aqui: a
  -- limpeza lá em cima não alcança esta variável.
  v_nome := nay_linha_sem_codigo(split_part(btrim(coalesce(p_linha,'')), '/', 1));
  v_nome := regexp_replace(v_nome, '^\s*([-*•·✅✔☑]|\d+[.)])\s*', '');
  IF position('/' in coalesce(p_linha,'')) = 0 THEN
    v_nome := (regexp_match(v_nome, '^([^0-9]*)'))[1];
  END IF;
  -- palavras de ligação penduradas no fim: "acquarelle de" -> "acquarelle"
  v_nome := regexp_replace(v_nome, '\s+(de|da|do|com|a|o|e|para|pra)\s*$', '', 'i');
  v_nome := btrim(regexp_replace(v_nome, '\s+', ' ', 'g'));

  IF v_nome = '' THEN RETURN; END IF;
  RETURN QUERY SELECT v_nome, v_q, v_s, v_a, v_val;
END;
$fn$;


-- --------------------------------------------------------------------
-- DE QUE IMÓVEIS ESTA LINHA FALA.
--
-- Por FAIXA DE PRECISÃO, e só a melhor faixa não vazia vira candidato -- a
-- mesma hierarquia de `nay_condominios_candidatos`, pelo mesmo motivo: a
-- ambiguidade vale DENTRO da faixa, nunca entre faixas.
--
--   0  a linha que a própria Nay gera, IGUAL à que ele colou
--   1  o nome inteiro do condomínio  (+ quartos/suítes/valor conferidos)
--   2  o nome sem as palavras genéricas
--   3  ele escreveu o nome e mais alguma coisa
--   4  ele escreveu um pedaço do nome
--   5  SÓ PARECENÇA -- daqui NÃO SAI ENVIO, só "você quis dizer?"
--
-- A faixa 5 é a mesma parede do `nay_disponibilidade_no_condominio`: afirmar
-- com firmeza sobre um condomínio que ele nem escreveu é o pior resultado
-- daquele funil. Aqui seria pior -- manda a carteira e não tem desfazer.
--
-- O FUNIL DE NOME VEM PRIMEIRO, e não é só desempenho: sem ele, a faixa 0
-- geraria `nay_linha_da_lista` dos 1.172 imóveis vezes dois negócios A CADA
-- LINHA colada. Restringir não muda o resultado -- se a linha gerada é
-- idêntica, o nome dentro dela também é, então o imóvel casaria pelo nome de
-- qualquer jeito.
--
-- O VALOR é conferido por IGUALDADE, nunca por aproximação. Dinheiro perto
-- não é dinheiro igual: "não achei" é resposta honesta, mandar o imóvel de
-- 2.550 porque ele escreveu 2.5 não é.
--
-- `no_mercado` sai junto em vez de filtrar: reconhecer o imóvel e poder
-- enviá-lo são decisões diferentes (o bug dos 35 imóveis fora do site,
-- 09/09). Quem decide é o chamador, e a decisão do Tel em 11/09 foi recusar
-- DIZENDO qual -- sumiço calado foi o que escondeu 112 apartamentos.
-- ATUALIZADA EM 28/09 (`codigo_na_linha_da_lista.sql`): a linha passou a
-- trazer "cod NNNN". Rodar a versão antiga deste arquivo DESFARIA a
-- mudança em silêncio -- por isso a definição vive aqui também, igual.
CREATE OR REPLACE FUNCTION nay_imoveis_da_linha(p_linha text)
RETURNS TABLE(codigo text, faixa int, negocio text, no_mercado boolean)
LANGUAGE plpgsql STABLE AS $fn$
DECLARE
  v_cod   text := nay_codigo_da_linha(p_linha);
  v_valor numeric;
BEGIN
  -- ATALHO PELO CÓDIGO, e ele é a razão de esta função ter virado plpgsql.
  --
  -- MEDIDO em 28/09: uma chamada custa ~2 segundos, e quase tudo é
  -- `nay_condominios_candidatos` comparando o nome contra os 387 condomínios
  -- em cinco faixas. A colagem dele tem 24 linhas -- eram 48 segundos só de
  -- casamento, antes de mandar qualquer coisa.
  --
  -- Com o código na linha não há nome a adivinhar: é igualdade. Quando ele
  -- resolve, o funil inteiro é PULADO. O formato novo ficou mais rápido que
  -- o antigo, não mais lento.
  --
  -- DUAS FAIXAS:
  --   -1  o código bate E o valor da linha bate o do negócio
  --    0  o código bate e o valor não bate (ou a linha não traz valor)
  --
  -- A segunda não é luxo: desde 28/09 a lista relê os preços no site antes de
  -- sair, então ele pode colar uma lista de ontem cujo valor já mudou. Sem
  -- ela, o código certo na mão daria "não achei".
  IF v_cod IS NOT NULL THEN
    SELECT pp.valor INTO v_valor FROM nay_partes_da_linha(p_linha) pp;
    RETURN QUERY
      SELECT i.codigo::text,
             CASE WHEN v_valor IS NOT NULL AND v_valor =
                       CASE WHEN n.negocio = 'locacao' THEN coalesce(i.valor_aluguel,0)
                            ELSE coalesce(i.valor_venda,0) END
                  THEN -1 ELSE 0 END,
             n.negocio,
             nay_esta_no_mercado(i.disponivel, i.bloqueado, i.publicado_no_site)
        FROM imoveis i
        CROSS JOIN (VALUES ('locacao'),('venda')) AS n(negocio)
       WHERE i.codigo::text = v_cod
         AND (CASE WHEN n.negocio = 'locacao' THEN coalesce(i.valor_aluguel,0)
                   ELSE coalesce(i.valor_venda,0) END) > 0
       -- Com os dois negócios, o que bate o valor ganha; sem valor que bata,
       -- voltam os dois e quem pergunta é o chamador.
       ORDER BY 2, 3;
    IF FOUND THEN RETURN; END IF;
    -- Código que NÃO EXISTE na tabela não atrapalha: cai no funil de sempre.
  END IF;

  RETURN QUERY
  WITH p AS (SELECT * FROM nay_partes_da_linha(p_linha)),
  neg AS (SELECT * FROM (VALUES ('locacao'),('venda')) AS n(negocio)),
  por_nome AS (
    SELECT i.codigo::text AS cod, c.faixa AS faixa_nome, i.tipo, i.condominio_nome,
           i.quartos, i.suites, i.area_util, i.valor_aluguel, i.valor_venda,
           i.disponivel, i.bloqueado, i.publicado_no_site
      FROM p CROSS JOIN LATERAL nay_condominios_candidatos(p.nome) c
      JOIN imoveis i ON i.condominio_nome = c.nome
    UNION ALL
    SELECT i.codigo::text, 0, i.tipo, i.condominio_nome,
           i.quartos, i.suites, i.area_util, i.valor_aluguel, i.valor_venda,
           i.disponivel, i.bloqueado, i.publicado_no_site
      FROM p JOIN imoveis i
        ON nay_condominio_de_verdade(i.tipo, i.condominio_nome) IS NULL
       AND nay_normalizar_lugar(btrim(coalesce(i.tipo,'') || ' ' || coalesce(i.bairro,'')), true)
         = nay_normalizar_lugar(p.nome, true)
  ),
  com_negocio AS (
    SELECT c.*, n.negocio
      FROM por_nome c CROSS JOIN neg n
     WHERE (n.negocio = 'locacao' AND coalesce(c.valor_aluguel,0) > 0)
        OR (n.negocio = 'venda'   AND coalesce(c.valor_venda,0)   > 0)
  ),
  exata AS (
    SELECT c.cod, 0 AS faixa, c.negocio,
           nay_esta_no_mercado(c.disponivel, c.bloqueado, c.publicado_no_site) AS no_mercado
      FROM com_negocio c
     WHERE nay_normalizar_lugar(nay_linha_sem_codigo(nay_linha_da_lista(c.cod,
             nay_categoria_do_imovel(c.tipo, c.condominio_nome), c.negocio)))
         = nay_normalizar_lugar(nay_linha_sem_codigo(p_linha))
  ),
  por_atributo AS (
    SELECT c.cod, c.faixa_nome + 1 AS faixa, c.negocio,
           nay_esta_no_mercado(c.disponivel, c.bloqueado, c.publicado_no_site) AS no_mercado
      FROM com_negocio c CROSS JOIN p
     WHERE (p.quartos IS NULL OR coalesce(c.quartos,0)   = p.quartos)
       AND (p.suites  IS NULL OR coalesce(c.suites,0)    = p.suites)
       AND (p.area    IS NULL OR coalesce(c.area_util,0) = p.area)
       AND (p.valor   IS NULL
            OR (c.negocio = 'locacao' AND coalesce(c.valor_aluguel,0) = p.valor)
            OR (c.negocio = 'venda'   AND coalesce(c.valor_venda,0)   = p.valor))
  ),
  tudo AS (SELECT * FROM exata UNION ALL SELECT * FROM por_atributo),
  por_codigo AS (SELECT t.cod, min(t.faixa) AS faixa FROM tudo t GROUP BY t.cod),
  melhor AS (SELECT min(pc.faixa) AS faixa FROM por_codigo pc)
  SELECT DISTINCT ON (pc.cod) pc.cod, pc.faixa, t.negocio, t.no_mercado
    FROM por_codigo pc
    JOIN melhor m ON pc.faixa = m.faixa
    JOIN tudo t ON t.cod = pc.cod AND t.faixa = pc.faixa
   ORDER BY pc.cod, t.negocio;
END;
$fn$;

-- --------------------------------------------------------------------
-- O ENVIO QUE FICOU ESPERANDO A RESPOSTA DO TEL.
--
-- POR QUE PRECISA DE ESTADO, quando todo o resto do caminho do Tel é
-- stateless: `POST /comando` recebe só `{"texto": ...}` e cada mensagem dele
-- é uma requisição independente. Quando ela pergunta "qual desses códigos?",
-- a resposta dele ("Nay codigo 5719") não carrega nem a lista nem o
-- destinatário -- e adivinhar o destinatário é exatamente o erro que este
-- projeto trata como o pior possível.
--
-- A DECISÃO DO TEL (11/09) foi SEGURAR TUDO: nada sai enquanto a lista
-- inteira não estiver resolvida, para o corretor receber uma leva só. Então
-- esta linha guarda o envio COMPLETO -- destinatário, o que já resolveu e o
-- que ficou pendurado.
--
-- UMA SÓ EM ABERTO, garantido por índice. Com duas, "Nay codigo 5719" seria
-- ambíguo e ela aplicaria à pergunta errada -- mandando a carteira para o
-- corretor da lista anterior. O portão falha FECHADO: sem linha aberta, ou
-- com a janela vencida, a resposta é recusa com o comando pronto para colar,
-- nunca envio.
--
-- A JANELA existe porque estado sem prazo vira resposta errada dias depois.
-- O `pendencia_rascunho` não expira e por isso precisou de uma verificação
-- no `saude.sql`; aqui o prazo mora em `config.envio_pendente_minutos` e
-- muda com UPDATE, como o `lista_repete_minutos`.
CREATE TABLE IF NOT EXISTS envio_pendente (
    id                serial PRIMARY KEY,
    destino_telefone  text        NOT NULL,
    destino_nome      text        NOT NULL,
    -- o que já resolveu para UM código só
    codigos           text[]      NOT NULL DEFAULT '{}',
    -- [{"linha": "...", "vezes": 2, "candidatos": ["5719","5728"]}]
    ambiguas          jsonb       NOT NULL DEFAULT '[]',
    -- linha que não casou com imóvel nenhum, para ela dizer qual foi
    sem_casar         text[]      NOT NULL DEFAULT '{}',
    -- código reconhecido mas com o anúncio fora do ar
    fora_do_site      text[]      NOT NULL DEFAULT '{}',
    criado_em         timestamptz NOT NULL DEFAULT now(),
    fechado_em        timestamptz,
    -- 'enviado', 'trocado' (ele mandou outra lista), 'vencido'
    fechado_motivo    text
);

CREATE UNIQUE INDEX IF NOT EXISTS envio_pendente_um_aberto
    ON envio_pendente ((true)) WHERE fechado_em IS NULL;

INSERT INTO config (chave, valor) VALUES ('envio_pendente_minutos', '60')
    ON CONFLICT (chave) DO NOTHING;
