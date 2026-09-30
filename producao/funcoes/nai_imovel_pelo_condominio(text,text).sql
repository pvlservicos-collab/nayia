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
