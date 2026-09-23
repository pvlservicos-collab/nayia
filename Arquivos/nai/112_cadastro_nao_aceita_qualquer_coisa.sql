-- =====================================================================
-- NAI -- 112: o cadastro para de aceitar qualquer coisa (23/09/2026)
--
-- O QUE ACONTECEU HOJE, com o Luiz Bastos, na producao:
--
--   ele:  "Eu to com uma locacao no Paradise River, la no Dom Pedro..."
--   ela:  "Pode mandar sim. E apartamento, casa ou outro tipo de imovel?"
--   ele:  "Ta, entao vou te anunciar o que eu tenho aqui, OS IMOVEIS que eu
--          tenho, pra locacao tambem..."
--   ela:  "Quantos quartos tem o imovel do Paradise River?"
--   ele:  "Tai, Nay 3 dormitorios sendo uma suite"
--   ele:  "3.650 + caucao E locacao"
--   ela:  "Obrigada! Ja deixei registrado aqui."
--
-- E entrou no catalogo, PUBLICADO, o imovel 5747 assim:
--     tipo       = "apartamentos, casas e imoveis em predios"
--     condominio = "Living Comfort e Coral Gables"
--     bairro     = "Parque Dez e Flores"
--
-- Ele estava descrevendo A CARTEIRA DELE, e a ferramenta gravou a frase
-- inteira em cada campo. O imovel ja foi bloqueado a mao; isto aqui e para
-- nao acontecer de novo.
--
-- AS TRAVAS (o mesmo principio das outras: o banco nao aceita o que nao faz
-- sentido, em vez de pedir para o modelo tomar cuidado):
--   - TIPO so entra se for UM tipo que existe no catalogo. "apartamentos,
--     casas e imoveis em predios" nao e tipo nenhum.
--   - CONDOMINIO e BAIRRO so entram com UM nome. "Living Comfort e Coral
--     Gables" sao dois, e dois nomes nao cabem num imovel so.
--   - VALOR acima de 100 milhoes nao e valor de imovel; e engano.
-- O que nao passa na trava simplesmente nao e gravado -- e ai a ficha
-- continua faltando aquilo, e ela pergunta de novo. Melhor perguntar duas
-- vezes do que publicar errado.
-- =====================================================================

\set ON_ERROR_STOP on

BEGIN;

-- 1 ------------------------------------------------ UM TIPO QUE EXISTE
CREATE OR REPLACE FUNCTION public.nai_tipo_canonico(p_texto text)
 RETURNS text LANGUAGE sql STABLE
AS $function$
  -- Devolve o rotulo do catalogo, ou NULL quando nao da para dizer qual e.
  -- A frase tem que caber num tipo so: "apartamento ou casa" nao vale.
  SELECT CASE
    WHEN s !~ '\m(apartamento|apto|casa|cobertura|flat|sala|andar|loja|ponto|galpao|deposito|lote|terreno|chacara|sitio|predio)' THEN NULL
    WHEN (SELECT count(DISTINCT g) FROM unnest(ARRAY[
            CASE WHEN s ~ '\m(apartamento|apartamentos|apto|aptos)\M' THEN 'ap' END,
            CASE WHEN s ~ '\m(casa|casas|sobrado)\M'                  THEN 'casa' END,
            CASE WHEN s ~ '\m(cobertura|coberturas)\M'                THEN 'cob' END,
            CASE WHEN s ~ '\m(flat|flats)\M'                          THEN 'flat' END,
            CASE WHEN s ~ '\m(sala|salas|andar)\M'                    THEN 'sala' END,
            CASE WHEN s ~ '\m(loja|lojas|ponto)\M'                    THEN 'loja' END,
            CASE WHEN s ~ '\m(galpao|galpoes|deposito)\M'             THEN 'galpao' END,
            CASE WHEN s ~ '\m(lote|lotes|terreno|terrenos)\M'         THEN 'lote' END,
            CASE WHEN s ~ '\m(chacara|chacaras|sitio)\M'              THEN 'chacara' END,
            CASE WHEN s ~ '\m(predio|predios)\M'                      THEN 'predio' END
          ]) g WHERE g IS NOT NULL) <> 1 THEN NULL
    WHEN s ~ '\m(apartamento|apartamentos|apto|aptos)\M' THEN 'Apartamento'
    WHEN s ~ '\m(casa|casas|sobrado)\M'                  THEN 'Casa'
    WHEN s ~ '\m(cobertura|coberturas)\M'                THEN 'Cobertura'
    WHEN s ~ '\m(flat|flats)\M'                          THEN 'Flat'
    WHEN s ~ '\m(sala|salas|andar)\M'                    THEN 'Sala/Andar'
    WHEN s ~ '\m(loja|lojas|ponto)\M'                    THEN 'Loja/Ponto'
    WHEN s ~ '\m(galpao|galpoes|deposito)\M'             THEN 'Galpão'
    WHEN s ~ '\m(lote|lotes|terreno|terrenos)\M'         THEN 'Lote'
    WHEN s ~ '\m(chacara|chacaras|sitio)\M'              THEN 'Chácara'
    WHEN s ~ '\m(predio|predios)\M'                      THEN 'Prédio'
  END
  FROM (SELECT lower(unaccent(coalesce(p_texto, ''))) AS s) x;
$function$;

-- 2 ------------------------------------------------------- UM NOME SO
CREATE OR REPLACE FUNCTION public.nai_um_nome_so(p_texto text)
 RETURNS boolean LANGUAGE sql IMMUTABLE
AS $function$
  SELECT s <> ''
     -- a conjuncao so conta com palavra DOS DOIS LADOS: "Living Comfort e
     -- Coral Gables" e dois nomes, mas "e no Living Comfort" e um so.
     AND s !~ '[a-z]\s+(e|ou)\s+[a-z]'
     AND s !~ ','                   -- "Flores, Parque Dez"
     AND s !~ '/'                   -- "Flores/Parque Dez"
     AND array_length(regexp_split_to_array(s, '\s+'), 1) <= 6
    FROM (SELECT btrim(lower(unaccent(coalesce(p_texto, '')))) AS s) x;
$function$;

-- 3 ------------------------- AS TRAVAS DENTRO DA FERRAMENTA QUE GRAVA
DO $mig$
DECLARE v_def text;
BEGIN
  v_def := pg_get_functiondef('nai_sec_guardar_do_imovel(bigint,text,text,text,text,text,text,text,text,text,text,text,text)'::regprocedure);
  IF position('nai_tipo_canonico' IN v_def) > 0 THEN
    RAISE NOTICE 'as travas ja estao no cadastro'; RETURN;
  END IF;

  v_def := replace(v_def,
    '    tipo       = coalesce(nullif(btrim(coalesce(p_tipo, '''')), ''''), n.tipo),',
    '    -- TIPO SO SE FOR UM TIPO (112): "apartamentos, casas e imoveis em' || E'\n'
 || '    -- predios" nao e tipo, e foi isso que virou imovel em 23/09.' || E'\n'
 || '    tipo       = coalesce(nai_tipo_canonico(p_tipo), n.tipo),');

  v_def := replace(v_def,
    '    condominio = coalesce(nullif(btrim(coalesce(p_condominio, '''')), ''''), n.condominio),',
    '    -- UM NOME SO (112): "Living Comfort e Coral Gables" sao dois.' || E'\n'
 || '    condominio = coalesce(CASE WHEN nai_um_nome_so(p_condominio) THEN btrim(p_condominio) END, n.condominio),');

  v_def := replace(v_def,
    '    bairro     = coalesce(nullif(btrim(coalesce(p_bairro, '''')), ''''), n.bairro),',
    '    bairro     = coalesce(CASE WHEN nai_um_nome_so(p_bairro) THEN btrim(p_bairro) END, n.bairro),');

  v_def := replace(v_def,
    '    valor      = coalesce(nay_maior_valor(p_valor), nay_valor_em_reais(p_valor), n.valor),',
    '    -- acima de 100 milhoes nao e imovel, e engano de digitacao (112)' || E'\n'
 || '    valor      = coalesce(nullif(least(coalesce(nay_maior_valor(p_valor),' || E'\n'
 || '                                              nay_valor_em_reais(p_valor)), 100000000), 100000000), n.valor),');

  EXECUTE v_def;
  RAISE NOTICE 'travas postas no cadastro';
END $mig$;

COMMIT;

SELECT t AS veio, coalesce(nai_tipo_canonico(t), '(nao gravo)') AS tipo_que_entra,
       nai_um_nome_so(t) AS serve_como_nome
  FROM unnest(ARRAY[
    'apartamentos, casas e imóveis em prédios',
    'É um apartamento',
    'casa',
    'apartamento ou casa, tanto faz',
    'Living Comfort e Coral Gables',
    'Living Comfort',
    'Parque Dez e Flores',
    'Dom Pedro'
  ]) t;
