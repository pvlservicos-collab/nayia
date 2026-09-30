-- A lista por categoria que o Tel pede no WhatsApp.
--
-- O PEDIDO (09/09), com os exemplos dele:
--
--   Nay lista de apartamento para locação
--   🔥 APARTAMENTOS PARA LOCAÇÃO DE 1.9k A 10k 🔥
--
--   ✅Conquista rio negro / 2 quartos / semi-mobiliado / 1.9k (incluso a tx)
--   ✅Amazonas Flat / 2 quartos / semi-mobiliado / 2k (incluso a tx)
--
--   (formato de 15/09: 🔥 no título, ✅ colado na frente de cada imóvel. Até
--   14/09 o ✅ ficava no título.)
--
--   Nay lista de casa de via pública
--   ✅ CASAS EM VIA PÚBLICA de 5k a 7k
--   Casa parque dez / 3 quartos sendo 1 suíte / semi-mobiliado / 5k
--
--   Nay lista de salas comerciais
--   ✅ SALAS COMERCIAIS DE 5K A 6K
--   The Oficce / 30m2 / climatizado / 5k (incluso a tx)
--   the place / 28m2 / mobiliado / 5k / + tx de 850,00
--
-- QUATRO REGRAS QUE VIERAM DELE, e cada uma muda o resultado:
--   * sala comercial mostra **m²** no lugar de quartos, e **só entra a que
--     está em condomínio**;
--   * "(incluso a tx)" só quando a taxa está mesmo inclusa; quando não está e
--     nós sabemos o valor, sai "+ tx de 850,00";
--   * no título, o imóvel com taxa POR FORA conta pelo valor CHEIO
--     (aluguel + taxa) -- "está com o valor cheio então pode se somar";
--   * via pública é o imóvel SEM condomínio, o mesmo critério do card do
--     disparo (medido em 10 anúncios reais).
--
--   docker cp lista_de_imoveis.sql nay-postgres:/tmp/li.sql
--   docker exec nay-postgres psql -U nay -d naydb -f /tmp/li.sql

-- --------------------------------------------------------------------
-- A categoria de cada imóvel, do jeito que o Tel pede.
--
-- Sai do `tipo` do cadastro, e por isso `varrer_tipos.py` existe: 17 dos 54
-- imóveis de locação estavam com `tipo` vazio em 09/09 e ficariam de fora de
-- toda lista, calados.
-- CONDOMÍNIO DE MENTIRA. A importação de agosto pôs o TIPO no campo do
-- condomínio quando não havia um: os códigos 4561, 3640 e 3656 têm
-- `condominio_nome = 'Loja/Ponto'`, igual ao tipo. Sem esta parede eles
-- entravam na lista de salas comerciais (que o Tel restringiu a condomínio) e
-- ainda saíam com o nome "Loja/Ponto", que não identifica imóvel nenhum.
CREATE OR REPLACE FUNCTION nay_condominio_de_verdade(p_tipo text, p_condominio text)
RETURNS text LANGUAGE sql IMMUTABLE AS $fn$
  SELECT CASE
    WHEN coalesce(btrim(p_condominio),'') = '' THEN NULL
    -- igual ao tipo: é rótulo, não nome
    WHEN lower(btrim(p_condominio)) = lower(btrim(coalesce(p_tipo,''))) THEN NULL
    -- e as palavras de tipo sozinhas, que também aparecem no campo
    WHEN lower(btrim(p_condominio)) ~
         '^(apartamento|casa|casas|lote|loja|loja/ponto|sala|sala/andar|predio|prédio|terreno|kitnet|flat|cobertura|chacara|chácara|sobrado|galpao|galpão)$'
      THEN NULL
    WHEN btrim(p_condominio) ILIKE '%identificado%' THEN NULL
    ELSE btrim(p_condominio)
  END;
$fn$;

CREATE OR REPLACE FUNCTION nay_categoria_do_imovel(p_tipo text, p_condominio text)
RETURNS text LANGUAGE sql IMMUTABLE AS $fn$
  WITH c AS (SELECT nay_condominio_de_verdade(p_tipo, p_condominio) AS nome)
  SELECT CASE
    WHEN coalesce(p_tipo,'') ~* 'sala|loja|conjunto comercial|andar'
      -- Só a que está em condomínio: decisão do Tel. Sala solta na rua não
      -- entra na lista de salas comerciais.
      THEN CASE WHEN (SELECT nome FROM c) IS NOT NULL
                THEN 'sala' ELSE NULL END
    WHEN coalesce(p_tipo,'') ~* 'casa|sobrado'
      THEN CASE WHEN (SELECT nome FROM c) IS NOT NULL
                THEN 'casa_condominio' ELSE 'casa_via_publica' END
    WHEN coalesce(p_tipo,'') ~* 'apartamento|cobertura|flat|kitnet|kit'
      -- "Apartamento em Via Pública" existe no cadastro e NÃO é o mesmo
      -- produto: o Tel pede apartamento pensando em condomínio.
      THEN CASE WHEN (SELECT nome FROM c) IS NOT NULL
                THEN 'apartamento' ELSE 'apartamento_via_publica' END
    WHEN coalesce(p_tipo,'') ~* 'lote|terreno' THEN 'lote'
    ELSE NULL
  END FROM c;
$fn$;

-- O título de cada categoria, no plural e em maiúsculas como ele escreve.
CREATE OR REPLACE FUNCTION nay_titulo_da_categoria(p_categoria text, p_negocio text)
RETURNS text LANGUAGE sql IMMUTABLE AS $fn$
  SELECT CASE p_categoria
    WHEN 'apartamento'            THEN 'APARTAMENTOS'
    WHEN 'apartamento_via_publica' THEN 'APARTAMENTOS EM VIA PÚBLICA'
    WHEN 'casa_condominio'        THEN 'CASAS EM CONDOMÍNIO'
    WHEN 'casa_via_publica'       THEN 'CASAS EM VIA PÚBLICA'
    WHEN 'sala'                   THEN 'SALAS COMERCIAIS'
    WHEN 'lote'                   THEN 'LOTES'
    ELSE upper(coalesce(p_categoria,'IMÓVEIS'))
  END || CASE WHEN p_negocio = 'venda' THEN ' PARA VENDA'
              ELSE ' PARA LOCAÇÃO' END;
$fn$;

-- --------------------------------------------------------------------
-- O valor curto: 4600 -> "4.6k", 900000 -> "900k", 2100000 -> "2.1M".
-- O mesmo critério do `Nay VAGAS` (publicador `_valor_curto`), para o Tel não
-- ter que aprender duas notações.
CREATE OR REPLACE FUNCTION nay_valor_curto(p_valor numeric)
RETURNS text LANGUAGE plpgsql IMMUTABLE AS $fn$
DECLARE v numeric;
BEGIN
  IF coalesce(p_valor,0) = 0 THEN RETURN NULL; END IF;
  -- Abaixo de mil o "k" atrapalha: 900 vira "0.9k", que ninguém lê como
  -- novecentos. Sai o número inteiro.
  IF p_valor < 1000 THEN
    RETURN to_char(round(p_valor), 'FM999990');
  END IF;
  -- A unidade sai do valor JÁ ARREDONDADO: senão 999.999 vira "1000k",
  -- tecnicamente certo e ilegível.
  IF round(p_valor / 1000, 2) >= 1000 THEN
    v := round(p_valor / 1000000, 2);
    RETURN btrim(to_char(v, 'FM999999990.99'), '.') || 'M';
  END IF;
  v := round(p_valor / 1000, 2);
  RETURN btrim(to_char(v, 'FM999999990.99'), '.') || 'k';
END;
$fn$;

-- --------------------------------------------------------------------
-- Uma linha da lista.
-- ATUALIZADA EM 28/09 (`codigo_na_linha_da_lista.sql`): a linha passou a
-- trazer "cod NNNN". Rodar a versão antiga deste arquivo DESFARIA a
-- mudança em silêncio -- por isso a definição vive aqui também, igual.
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
-- O CUSTO CHEIO, que é o que vai no título.
--
-- Palavra do Tel: "a parte da sala comercial que está com a taxa de condomínio
-- está com o valor cheio então pode se somar para colocar no título". Ou seja,
-- imóvel com taxa POR FORA conta aluguel + taxa; com a taxa inclusa, conta só
-- o aluguel, porque ali já está tudo dentro.
CREATE OR REPLACE FUNCTION nay_custo_cheio(p_codigo text, p_negocio text DEFAULT 'locacao')
RETURNS numeric LANGUAGE sql STABLE AS $fn$
  SELECT CASE
    WHEN p_negocio = 'venda' THEN i.valor_venda
    WHEN coalesce(i.extras->>'incluso no aluguel','') ILIKE '%condom%'
      THEN i.valor_aluguel
    ELSE coalesce(i.valor_aluguel,0) + coalesce(i.taxa_condominio,0)
  END
  FROM imoveis i WHERE i.codigo::text = p_codigo;
$fn$;

-- --------------------------------------------------------------------
-- A lista inteira, pronta para mandar.
-- A ASSINATURA GANHOU DOIS PARÂMETROS em 15/09 (piso de valor e só condomínio,
-- para o grupo Alto Padrão). `CREATE OR REPLACE` com assinatura diferente NÃO
-- substitui: cria uma SOBRECARGA, e a versão velha continuaria chamável -- o
-- CLAUDE.md registra o caso da `nay_responder_conversando` de 31/08. Por isso o
-- DROP da antiga, e os dois juntos numa transação: o cron da grade chama esta
-- função a cada minuto, e não pode haver instante sem ela. Os padrões novos
-- deixam a chamada de dois argumentos idêntica ao que era.
BEGIN;
DROP FUNCTION IF EXISTS nay_lista_de_imoveis(text, text);
CREATE OR REPLACE FUNCTION nay_lista_de_imoveis(p_categoria text,
                                                p_negocio text DEFAULT 'locacao',
                                                p_valor_minimo numeric DEFAULT NULL,
                                                p_so_condominio boolean DEFAULT false)
RETURNS TABLE(texto_pronto text, quantos int)
LANGUAGE plpgsql STABLE AS $fn$
DECLARE
  v_neg text := CASE WHEN lower(coalesce(p_negocio,'')) LIKE 'vend%'
                       OR lower(coalesce(p_negocio,'')) LIKE 'compr%'
                     THEN 'venda' ELSE 'locacao' END;
  v_linhas text;
  v_n int;
  v_min numeric;
  v_max numeric;
BEGIN
  WITH achados AS (
    SELECT i.codigo::text AS cod,
           nay_custo_cheio(i.codigo::text, v_neg) AS custo,
           nay_linha_da_lista(i.codigo::text, p_categoria, v_neg) AS linha
      FROM imoveis i
     WHERE nay_esta_no_mercado(i.disponivel, i.bloqueado, i.publicado_no_site)
       AND NOT coalesce(i.e_parceiro, false)
       AND nay_categoria_do_imovel(i.tipo, i.condominio_nome) = p_categoria
       AND (CASE WHEN v_neg = 'venda' THEN coalesce(i.valor_venda,0)
                 ELSE coalesce(i.valor_aluguel,0) END) > 0
       -- O PISO DO GRUPO (15/09). Compara o valor que a linha mostra, não o
       -- custo cheio do título. Nulo é sem piso: a lista de sempre.
       AND (p_valor_minimo IS NULL
            OR (CASE WHEN v_neg = 'venda' THEN coalesce(i.valor_venda,0)
                     ELSE coalesce(i.valor_aluguel,0) END) >= p_valor_minimo)
       -- Condomínio DE VERDADE: a importação pôs "Casa" e "Loja/Ponto" no campo
       -- do condomínio de imóvel de rua, e nome de rótulo não pode passar.
       AND (NOT p_so_condominio
            OR nay_condominio_de_verdade(i.tipo, i.condominio_nome) IS NOT NULL)
  )
  -- O ✅ COLADO NA FRENTE DE CADA IMÓVEL, sem espaço, é o formato que o Tel
  -- escreveu em 15/09. Ele vai AQUI, na montagem, e não dentro de
  -- `nay_linha_da_lista`: aquela função é a identidade da linha, e o
  -- `nay_imoveis_da_linha` a gera de novo para casar o que ele cola. Emoji
  -- dentro dela seria mais uma coisa para as duas pontas concordarem.
  SELECT count(*), min(custo), max(custo),
         string_agg('✅' || linha, chr(10) ORDER BY custo, linha)
    INTO v_n, v_min, v_max, v_linhas
    FROM achados;

  IF coalesce(v_n,0) = 0 THEN
    RETURN QUERY SELECT
      ('não tenho nenhum imóvel nessa categoria para '
       || CASE WHEN v_neg = 'venda' THEN 'venda' ELSE 'locação' END
       || ' no momento.')::text, 0;
    RETURN;
  END IF;

  -- O TÍTULO ENTRE 🔥, com uma linha em branco antes dos imóveis (Tel, 15/09,
  -- com o exemplo dele). Até 14/09 o ✅ ficava no título e as linhas saíam
  -- cruas; ele inverteu: ✅ marca o imóvel, 🔥 marca o título.
  RETURN QUERY SELECT
    ('🔥 ' || nay_titulo_da_categoria(p_categoria, v_neg)
     || CASE WHEN v_min = v_max THEN ' — ' || nay_valor_curto(v_min)
             ELSE ' DE ' || nay_valor_curto(v_min) || ' A ' || nay_valor_curto(v_max) END
     || ' 🔥' || chr(10) || chr(10) || v_linhas)::text,
    v_n;
END;
$fn$;
COMMIT;
