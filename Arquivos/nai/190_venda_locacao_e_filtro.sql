-- 190 -- venda não se mistura com locação, o filtro vem antes do imóvel, e
-- palavra de gente não vira nome de condomínio (29/09/2026).
--
-- DOIS CASOS DO MESMO DIA:
--
-- 1. Corretor da Ponta Negra (contato 11238). De manhã pediu "a sua lista de
--    vc tem disponível na ponta negra ii de 7mil" e recebeu 5 cards de
--    LOCAÇÃO. Às 17:13: "Tem Vieira Alves e Adrianópolis 3 quartos?". A Nay
--    respondeu "Sim! Tem 4 quartos, sendo 4 suítes..." e mandou 24 fotos do
--    5748 -- Jardim Adrianópolis, VENDA, R$ 2 milhões. Três falhas em fila:
--    a) `nai_imovel_pelo_condominio`, no último recurso (parecença), achou
--       "adrianopolis+quartos" 50% parecido com "jardimadrianopolis": o nome
--       do BAIRRO virou o imóvel;
--    b) a conversa não sabia que era locação: `nai_negocio_da_conversa` só
--       lia palavra explícita ("aluguel", "venda") e ignorava o "7mil" e os
--       cards que ela mesma tinha mandado;
--    c) a conferência trocou a resposta da busca pela ficha do 5748 (etapa
--       05, formato da base) e o portão de fotos pegou o imóvel da conversa.
--    Pedro: "se o cara tá pedindo locação ela deve continuar enviando
--    locação, a não ser se ele peça claramente venda... ela nunca deve
--    confundir as duas listas de imóveis sem um pedido claro do corretor,
--    seria bom até desvincular esses 2 bancos de dados".
--
-- 2. Sulivam (contato 13117): "Ela precisa de mais um cômodo P escritório
--    Ideal 3 quartos" chegou à Nay como "...mais um Coroado P escritório"
--    (`nai_corrigir_nomes`, piso 0,70) e ela respondeu "No Coroado não tenho
--    nenhuma casa nesse perfil". E antes disso a busca já tinha listado com
--    "casa, 5 mil" sem perguntar região (regra 146: qualquer filtro lista).
--    Pedro: "ela precisa fazer o filtro... sempre que tiver uma nova
--    solicitação de imóveis... primeiro fazer o filtro antes de enviar
--    qualquer imóvel".
--
-- O QUE MUDA
--   * `nai_finalidade_do_imovel` / `nai_finalidade_serve`: a finalidade do
--     imóvel num lugar só (antes cada função adivinhava). E as duas listas
--     separadas por nome: `vw_catalogo_locacao` e `vw_catalogo_venda`.
--   * `nai_negocio_da_conversa`: palavra dele, depois valor com cara de
--     dinheiro ("7mil", "R$ 700 mil"), nas falas dos últimos 3 dias; na falta
--     disso, a finalidade do que ela já mandou para ele (se for toda igual).
--   * A PAREDE, em `nai_saida_validar` (190p): card ou foto de imóvel de
--     venda não sai em conversa de locação, nem o contrário -- salvo o código
--     que ELE digitou ou colou.
--   * `nai_imovel_da_conversa` só enxerga imóvel da finalidade da conversa
--     (salvo o código que ele digitou), e `nai_imovel_pelo_condominio` não usa
--     nome de bairro como pista de condomínio na parecença.
--   * A conferência não troca a resposta da busca pela ficha de um imóvel, e
--     sem card na resposta da busca não há foto.
--   * `nai_buscar_por_perfil` (190p): o filtro (locação/venda, casa/apto,
--     valor, região) vem antes de qualquer imóvel. Cada pergunta uma vez por
--     dia; "não sabe / tanto faz" pula (a 146 continua: não força).
--   * `nai_corrigir_nomes`: piso 0,80 e palavra conhecida não é trocada.
--
-- As funções vivas (conferência, gatilho da caixa, imóvel da conversa e
-- busca) são remendadas a partir do `pg_proc` por `190_remendos.py`, que gera
-- `190p_remendos.sql` -- nunca reaplicar arquivo antigo delas.

BEGIN;
SET LOCAL lock_timeout = '5s';

-- ----------------------------------------------------------- A FINALIDADE
CREATE OR REPLACE FUNCTION nai_finalidade_do_imovel(p_codigo int)
RETURNS text LANGUAGE sql STABLE AS $$
  -- A mesma régua de `nai_oferta_serve`: aluguel > 0 é locação, venda > 0 é
  -- venda, os dois é 'ambos'. Sem preço nenhum: NULL (não se sabe).
  SELECT CASE WHEN a AND v THEN 'ambos' WHEN a THEN 'locacao' WHEN v THEN 'venda' END
    FROM (SELECT coalesce(i.valor_aluguel, 0) > 0 AS a, coalesce(i.valor_venda, 0) > 0 AS v
            FROM imoveis i WHERE i.codigo = p_codigo) x;
$$;

CREATE OR REPLACE FUNCTION nai_finalidade_serve(p_codigo int, p_negocio text)
RETURNS boolean LANGUAGE sql STABLE AS $$
  -- Conversa sem negócio definido, ou 'ambos': não barra (quem pergunta
  -- "alugar ou comprar?" é a busca). Imóvel sem preço: não barra.
  SELECT CASE WHEN p_negocio IS NULL OR p_negocio NOT IN ('locacao', 'venda') THEN true
              ELSE coalesce(nai_finalidade_do_imovel(p_codigo) IN (p_negocio, 'ambos'), true) END;
$$;

CREATE OR REPLACE VIEW vw_catalogo_locacao AS
  SELECT i.* FROM imoveis i WHERE coalesce(i.valor_aluguel, 0) > 0;
COMMENT ON VIEW vw_catalogo_locacao IS
  '190: os imóveis de LOCAÇÃO (valor_aluguel > 0). Conversa de locação só recebe daqui; o gatilho nai_saida_validar barra o resto.';
CREATE OR REPLACE VIEW vw_catalogo_venda AS
  SELECT i.* FROM imoveis i WHERE coalesce(i.valor_venda, 0) > 0;
COMMENT ON VIEW vw_catalogo_venda IS
  '190: os imóveis de VENDA (valor_venda > 0). Conversa de venda só recebe daqui; o gatilho nai_saida_validar barra o resto.';

-- ------------------------------------------------------ O NEGÓCIO DA CONVERSA
CREATE OR REPLACE FUNCTION nai_negocio_pelo_valor(p_texto text)
RETURNS text LANGUAGE sql STABLE AS $$
  -- Só valor com cara de dinheiro: "de 7mil", "até 3.500", "R$ 700 mil",
  -- "média de 5mil". "3 quartos", "apto 1601" e "bloco 13" não contam.
  SELECT CASE WHEN x.v IS NULL OR x.v < 300 THEN NULL
              WHEN x.v <= 30000 THEN 'locacao'
              WHEN x.v >= 100000 THEN 'venda' END
    FROM (SELECT coalesce(nay_maior_valor(coalesce(p_texto, '')), nay_valor_em_reais(coalesce(p_texto, ''))) AS v) x
   WHERE lower(unaccent(coalesce(p_texto, ''))) ~
         '(r\$|\d\s*(mil|k)\M|\mmil\M|reais|\mate\s+(r\$\s*)?\d|\mvalor|orcamento|\mmedia\s+de|\mfaixa\s+de|\mpaga\s)';
$$;

CREATE OR REPLACE FUNCTION nai_negocio_das_falas(p_falas text[])
RETURNS text LANGUAGE sql STABLE AS $$
  -- Primeiro a PALAVRA (a fala mais nova que disse locação ou venda); se
  -- nenhuma disse, o VALOR (190). A fala em que ele oferece o imóvel DELE
  -- ("vendo meu apartamento por 450 mil") não diz o que o cliente procura.
  SELECT coalesce(
    (SELECT nay_negocio_pedido(f.fala) FROM unnest(p_falas) WITH ORDINALITY f(fala, pos)
      WHERE nay_negocio_pedido(f.fala) IS NOT NULL AND NOT nai_fala_e_dele(f.fala)
      ORDER BY f.pos LIMIT 1),
    (SELECT nai_negocio_pelo_valor(f.fala) FROM unnest(p_falas) WITH ORDINALITY f(fala, pos)
      WHERE nai_negocio_pelo_valor(f.fala) IS NOT NULL AND NOT nai_fala_e_dele(f.fala)
      ORDER BY f.pos LIMIT 1));
$$;

CREATE OR REPLACE FUNCTION nai_negocio_do_que_recebeu(p_contato bigint)
RETURNS text LANGUAGE sql STABLE AS $$
  -- O que ela já mandou para ele nos últimos 3 dias (card ou foto). Se tudo
  -- é de uma finalidade só, a conversa é dessa finalidade. Misturado: NULL.
  WITH cods AS (
    SELECT DISTINCT coalesce(s.codigo, (regexp_match(s.texto, 'C[óo]digo:\s*(\d{3,5})', 'i'))[1]::int) AS c
      FROM nai_saida s
     WHERE s.contato_id = ANY (nai_contato_irmaos(p_contato))
       AND s.estado = 'enviado' AND s.criado_em > now() - interval '3 days'
       AND (s.codigo IS NOT NULL OR (s.tipo = 'texto' AND position('📍' IN coalesce(s.texto, '')) > 0))
  ), f AS (SELECT nai_finalidade_do_imovel(c) AS fin FROM cods WHERE c IS NOT NULL)
  SELECT CASE WHEN count(*) FILTER (WHERE fin = 'locacao') > 0 AND count(*) FILTER (WHERE fin = 'venda') = 0 THEN 'locacao'
              WHEN count(*) FILTER (WHERE fin = 'venda') > 0 AND count(*) FILTER (WHERE fin = 'locacao') = 0 THEN 'venda' END
    FROM f;
$$;

CREATE OR REPLACE FUNCTION nai_negocio_da_conversa(p_contato bigint, p_texto text)
RETURNS text LANGUAGE sql STABLE AS $$
  -- 190: a conversa guarda o negócio por 3 dias. Ordem: o que ele disse
  -- AGORA (palavra, depois valor), o que ele disse antes (idem), e por
  -- último a finalidade do que ele já recebeu. Muda só com pedido claro:
  -- "venda", "comprar", "R$ 700 mil".
  SELECT coalesce(
    nai_negocio_das_falas(array[coalesce(p_texto, '')]),
    nai_negocio_das_falas(coalesce((SELECT array_agg(x.texto ORDER BY x.id DESC) FROM (
         SELECT t.id, t.texto FROM nai_turno t
          WHERE t.contato_id = ANY (nai_contato_irmaos(p_contato))
            AND t.criado_em > greatest(now() - interval '3 days',
                                       coalesce((SELECT k.zerado_em FROM nai_contato k WHERE k.id = p_contato), '-infinity'))
          ORDER BY t.id DESC LIMIT 40) x), '{}'::text[])),
    nai_negocio_do_que_recebeu(p_contato));
$$;

-- ------------------------------------------------ O CÓDIGO QUE ELE DIGITOU
CREATE OR REPLACE FUNCTION nai_codigos_que_ele_digitou(p_contato bigint)
RETURNS int[] LANGUAGE sql STABLE AS $$
  -- Código escrito ou card colado por ELE nos últimos 3 dias. É o pedido
  -- claro: esse imóvel vai, seja de venda ou de locação.
  SELECT coalesce(array_agg(DISTINCT x::int), '{}')
    FROM nai_turno t
   CROSS JOIN LATERAL unnest(coalesce(nay_codigos_citados(coalesce(t.texto, '')), '{}'::text[])) x
   WHERE t.contato_id = ANY (nai_contato_irmaos(p_contato))
     AND t.criado_em > now() - interval '3 days'
     AND x ~ '^[0-9]{3,5}$';
$$;

-- -------------------------------- NOME DE BAIRRO NÃO É PISTA DE CONDOMÍNIO
CREATE OR REPLACE FUNCTION public.nai_imovel_pelo_condominio(p_texto text, p_telefone text)
 RETURNS integer[]
 LANGUAGE sql
 STABLE COST 5000
AS $function$
  -- O NOME ESCRITO CERTO MANDA. A parecenca e ULTIMO RECURSO: so entra quando
  -- nenhum nome bateu pela escrita.
  WITH certo AS (
    -- 1. nome inteiro, como esta no cadastro (16/09)
    SELECT v.codigos FROM vw_condominio_som v
     WHERE length(v.nome) >= 8
       AND position(lower(unaccent(v.nome)) IN lower(unaccent(coalesce(p_texto, '')))) > 0
    UNION ALL
    -- 2. o nucleo, sem Condominio/Residencial/Edificio (86).
    -- O piso caiu de 8 para 6 letras (114): "Arezzo" tem 6 e ficava invisivel.
    -- Isto e casamento EXATO de palavra, nao parecenca -- por isso da para
    -- baixar sem risco. O que NAO pode entrar e nucleo que tambem e nome de
    -- bairro: "Taruma" e condominio E bairro, e viraria imovel toda vez que
    -- alguem falasse do bairro.
    SELECT v.codigos FROM vw_condominio_som v
     WHERE length(coalesce(v.nucleo, '')) >= 6
       AND NOT EXISTS (SELECT 1 FROM imoveis i
                        WHERE lower(unaccent(coalesce(i.bairro, ''))) = lower(unaccent(v.nucleo)))
       AND lower(unaccent(coalesce(p_texto, ''))) ~
           ('\m' || regexp_replace(v.nucleo, '([.^$*+?()\[\]{}|\-])', '\\\1', 'g') || '\M')
    UNION ALL
    -- 3. a chave de som IGUAL (88): "aquarele" = Acquarelle
    SELECT v.codigos FROM vw_condominio_som v, nai_pedacos_de_nome(p_texto) g
     WHERE length(v.chave) >= 7 AND length(g.chave) >= 7
       AND (position(v.chave IN g.chave) > 0
            OR (length(g.chave) >= 9 AND v.chave LIKE g.chave || '%'))
  ),
  -- 190: NOME DE BAIRRO NAO E PISTA DE CONDOMINIO na parecenca. "Tem Vieira
  -- Alves e Adrianopolis 3 quartos?" -- o pedaco "adrianopolis quartos" ficou
  -- 50% parecido com "Jardim Adrianopolis" (5748, venda, R$ 2 mi) e a Nay
  -- mandou 24 fotos dele para quem pedia aluguel. Pedaco que contem um bairro
  -- ou area da cidade sai da parecenca; o nome escrito certo (1 a 3) continua
  -- valendo.
  lugares AS MATERIALIZED (
    SELECT DISTINCT nai_chave_som(lower(unaccent(x))) AS ch
      FROM (SELECT bairro AS x FROM imoveis WHERE bairro IS NOT NULL
            UNION SELECT bairro FROM bairro_zona
            UNION SELECT area FROM bairro_area) y
     WHERE length(nai_chave_som(lower(unaccent(x)))) >= 6
  ),
  pedacos AS (
    SELECT g.chave FROM nai_pedacos_de_nome(p_texto) g
     WHERE length(g.chave) >= 7
       AND NOT EXISTS (SELECT 1 FROM lugares b WHERE position(b.ch IN g.chave) > 0)
  ),
  -- 4. PARECIDO (89), so se nada acima bateu
  parecido AS (
    SELECT v.codigos, similarity(v.chave, g.chave) AS s
      FROM vw_condominio_som v, pedacos g
     WHERE NOT EXISTS (SELECT 1 FROM certo)
       AND length(v.chave) >= 7
       AND similarity(v.chave, g.chave) >= 0.50
  ),
  melhor AS (
    SELECT codigos FROM parecido
     WHERE s >= (SELECT max(s) - 0.05 FROM parecido)
  )
  SELECT coalesce((SELECT array_agg(DISTINCT c)
                     FROM (SELECT unnest(codigos) AS c FROM certo
                           UNION ALL
                           SELECT unnest(codigos) FROM melhor) x), '{}');
$function$;

-- ------------------------------------------ A PERGUNTA DO FILTRO JÁ SAIU?
CREATE OR REPLACE FUNCTION nai_filtro_ja_perguntado(p_contato bigint, p_qual text)
RETURNS boolean LANGUAGE sql STABLE AS $$
  -- Cada pergunta do filtro sai uma vez por dia para a mesma pessoa (pelas
  -- duas linhas dela). Na segunda vez a busca segue sem ela: repetir a
  -- pergunta é o laço que a 102 e a 146 mataram.
  SELECT EXISTS (
    SELECT 1 FROM nai_saida s
     WHERE s.contato_id = ANY (nai_contato_irmaos(p_contato))
       AND s.tipo = 'texto' AND s.estado <> 'bloqueado'
       AND s.criado_em > now() - interval '24 hours'
       AND s.texto ~* CASE p_qual
             WHEN 'valor'    THEN 'at[ée] que valor'
             WHEN 'regiao'   THEN '(em qual bairro|qual regi[ãa]o|alguma regi[ãa]o|em qual outro)'
             WHEN 'abertura' THEN 'vou fazer um filtro com voc'
             ELSE '^$' END);
$$;

-- ------------------------------------------------ O CORRETOR DE NOMES (190)
INSERT INTO nai_config (chave, valor) VALUES ('piso_correcao_nome', '0.80')
ON CONFLICT (chave) DO UPDATE SET valor = '0.80';

COMMIT;
