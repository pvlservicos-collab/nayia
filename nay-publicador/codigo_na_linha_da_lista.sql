-- O CÓDIGO ENTRA NA LINHA DA LISTA (Tel, 28/09)
--
-- O PEDIDO, com o exemplo dele:
--   ✅Conquista rio negro cod 3304 / 2 quartos / semi-mobiliado / 1.9k (incluso a tx)
--
-- Vai colado ao NOME, antes da primeira " / ", que é onde ele pôs em sete das
-- oito linhas do exemplo. (Na oitava ele escreveu "Ariranhas / 2 quartos cod
-- 3404 / mobiliado" -- leio como escorregão de digitação, não como segunda
-- forma: as outras sete concordam entre si.)
--
-- POR QUE ISTO NÃO É SÓ COSMÉTICO, e é a parte que importa:
--
-- `nay_linha_da_lista` é a IDENTIDADE da linha. O "Nay envia esses imóveis
-- para X" casa a colagem dele por REVERSO -- gera a linha de cada candidato e
-- compara. E o CLAUDE.md registra que essa função NÃO É INJETORA: o 5719 e o
-- 5728 são os dois "2 quartos sendo 1 suíte / 2.6k" no Estilo Golf e rendem a
-- MESMA string, e por isso ela precisa PERGUNTAR qual dos dois.
--
-- Com o código dentro, cada linha passa a ser única. A pergunta de
-- desambiguação deixa de existir para toda lista nova -- não porque alguém
-- mexeu no desempate, mas porque a ambiguidade sumiu da origem.
--
-- POR ISSO O CÓDIGO VIRA A FAIXA MAIS PRECISA do `nay_imoveis_da_linha`:
-- linha que traz "cod 3304" resolve por igualdade de código, e nem chega ao
-- funil de nome. Código que não existe na tabela não atrapalha nada -- a
-- faixa fica vazia e o funil de sempre corre.
--
-- E A COLAGEM ANTIGA CONTINUA CASANDO. Ele pode colar uma lista que a Nay
-- mandou ontem, sem código. A faixa 0 (o reverso) passou a comparar os dois
-- lados SEM o "cod NNNN", então a linha velha bate com a linha nova do mesmo
-- imóvel. Sem isso, toda colagem anterior a hoje cairia para as faixas de
-- atributo, que são menos precisas.
--
-- O "cod" NÃO DISPARA O GATILHO DE FOTOS: aquele nó procura "Código: NNNN",
-- com dois pontos (`/C[óo]digo:\s*(\d{3,5})/i`). "cod 3304" não casa -- e é
-- por isso que o formato dele é "cod", não "Código:". Conferido antes de
-- escrever, porque o contrário mandaria um álbum a cada linha da lista.

-- --------------------------------------------------------------------
-- 1. A LINHA passa a trazer o código.
CREATE OR REPLACE FUNCTION nay_linha_da_lista(p_codigo text, p_categoria text,
                                              p_negocio text DEFAULT 'locacao')
RETURNS text LANGUAGE plpgsql STABLE AS $fn$
DECLARE
  i record;
  partes text[] := '{}';
  quartos text;
  mob text;
  valor numeric;
  cauda text;
BEGIN
  SELECT * INTO i FROM imoveis WHERE codigo::text = p_codigo;
  IF i IS NULL THEN RETURN NULL; END IF;

  -- 1. o nome: o condomínio, ou tipo + bairro para o de rua -- e o CÓDIGO
  --    colado nele, que é onde o Tel pôs no exemplo de 28/09.
  partes := array_append(partes,
    coalesce(nay_condominio_de_verdade(i.tipo, i.condominio_nome),
             btrim(coalesce(i.tipo,'imóvel') || ' ' || coalesce(i.bairro,'')))
    || ' cod ' || i.codigo::text);

  -- 2. SALA mostra a metragem; o resto mostra quartos. Decisão do Tel.
  IF p_categoria = 'sala' THEN
    IF coalesce(i.area_util,0) > 0 THEN
      partes := array_append(partes, to_char(i.area_util,'FM999990') || 'm2');
    END IF;
  ELSE
    IF coalesce(i.quartos,0) > 0 THEN
      quartos := i.quartos || CASE WHEN i.quartos = 1 THEN ' quarto' ELSE ' quartos' END;
      IF coalesce(i.suites,0) > 0 THEN
        -- "3 suítes" quando TODOS os quartos são suíte -- é como ele escreve
        -- ("Morada dos pássarros / 3 suítes").
        IF i.suites >= i.quartos THEN
          quartos := i.suites || CASE WHEN i.suites = 1 THEN ' suíte' ELSE ' suítes' END;
        ELSE
          quartos := quartos || ' sendo ' || i.suites
                     || CASE WHEN i.suites = 1 THEN ' suíte' ELSE ' suítes' END;
        END IF;
      END IF;
      partes := array_append(partes, quartos);
    END IF;
  END IF;

  -- 3. mobília, quando se sabe.
  mob := lower(coalesce(i.mobilia,''));
  IF mob LIKE 'semi%' THEN partes := array_append(partes, 'semi-mobiliado');
  ELSIF mob LIKE 'mobiliad%' THEN partes := array_append(partes, 'mobiliado');
  ELSIF mob ~ 'ar[- ]condicionado' THEN partes := array_append(partes, 'climatizado');
  END IF;

  -- 4. o valor, e o que acontece com a taxa.
  valor := CASE WHEN p_negocio = 'venda' THEN i.valor_venda ELSE i.valor_aluguel END;
  partes := array_append(partes, nay_valor_curto(valor));

  IF p_negocio <> 'venda' THEN
    IF coalesce(i.extras->>'incluso no aluguel','') ILIKE '%condom%' THEN
      cauda := '(incluso a tx)';
    ELSIF coalesce(i.taxa_condominio,0) > 0 THEN
      cauda := '+ tx de ' || replace(replace(replace(
                 to_char(i.taxa_condominio,'FM999,999,990.00'), '.', '@'),
                 ',', '.'), '@', ',');
    END IF;
  END IF;

  RETURN array_to_string(partes, ' / ')
         || coalesce(CASE WHEN cauda LIKE '(%' THEN ' ' || cauda
                          ELSE ' / ' || cauda END, '');
END;
$fn$;

-- --------------------------------------------------------------------
-- 2. LER O CÓDIGO DE VOLTA, num lugar só.
--
-- Aceita as formas que ele e os corretores escrevem: "cod 3304", "cód. 3304",
-- "codigo: 3304", "código 3304". A que a lista GERA é a primeira.
CREATE OR REPLACE FUNCTION nay_codigo_da_linha(p_linha text)
RETURNS text LANGUAGE sql IMMUTABLE AS $fn$
  SELECT (regexp_match(coalesce(p_linha,''),
                       '\mc[óo]d(?:igo)?\.?\s*:?\s*([0-9]{2,5})\M', 'i'))[1];
$fn$;

-- E TIRAR O CÓDIGO da linha, para comparar colagem velha com linha nova.
CREATE OR REPLACE FUNCTION nay_linha_sem_codigo(p_linha text)
RETURNS text LANGUAGE sql IMMUTABLE AS $fn$
  SELECT btrim(regexp_replace(
           regexp_replace(coalesce(p_linha,''),
                          '\mc[óo]d(?:igo)?\.?\s*:?\s*[0-9]{2,5}\M', ' ', 'gi'),
           '\s+', ' ', 'g'));
$fn$;

-- --------------------------------------------------------------------
-- 3. O NOME não pode levar o "cod 3304" junto.
--
-- `nay_partes_da_linha` fatia a linha colada. Sem tirar o código, o nome do
-- condomínio viraria "Conquista rio negro cod 3304" e nenhuma das cinco
-- faixas de casamento de nome o reconheceria. Sai junto com a cauda da taxa,
-- no mesmo lugar e pelo mesmo motivo: pedaço que não identifica imóvel.
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
-- 4. O CÓDIGO VIRA A FAIXA MAIS PRECISA.
--
-- Linha que traz "cod 3304" resolve por IGUALDADE e nem chega ao funil de
-- nome. É o que faz a pergunta de desambiguação desaparecer: o 5719 e o 5728
-- rendiam a mesma string e a Nay tinha de perguntar qual dos dois -- com o
-- código dentro, não há mais o que perguntar.
--
-- A faixa do código é -1, ABAIXO da 0, e não 0: se empatasse com a faixa
-- exata, um imóvel que casasse o texto por outro caminho voltaria junto.
--
-- E A FAIXA 0 passou a comparar os dois lados SEM o código, para a colagem
-- de uma lista ANTIGA (sem "cod") continuar batendo com a linha nova do mesmo
-- imóvel. Sem isso, toda colagem anterior a 28/09 cairia para as faixas de
-- atributo.
--
-- CÓDIGO QUE NÃO EXISTE não atrapalha: a faixa fica vazia e o funil corre
-- como sempre. Falha para o lado de perguntar, nunca de mandar errado.
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
