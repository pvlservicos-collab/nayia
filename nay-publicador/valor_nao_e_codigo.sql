-- "Paga até 4000" não é um pedido do imóvel 4000.
--
-- O BUG (medido em 31/08 contra 30 dias de mensagens reais): a extração de
-- código de `nay_o_que_ficou_de_enviar` é `[0-9]{3,5}` cercado de não-dígito,
-- e os códigos deste catálogo vão de 45 a 5712 -- a mesma faixa de um
-- orçamento de aluguel. Três frases reais viraram código:
--
--     "Até 4500  Vou enviar as opções..."   -> imóvel 4500
--     "A proposta é para $4000"             -> imóvel 4000
--     "Paga até 4000"                       -> imóvel 4000
--
-- e 4000 e 4500 existem. A Nay concluiria que devia esses imóveis e o cron
-- os mandaria sozinho -- exatamente o "empurrar imóvel que ninguém pediu"
-- que a entrega pendente foi escrita para não fazer.
--
-- POR QUE TIRAR O VALOR ANTES, e não filtrar depois: é o mesmo caminho de
-- `_interpretar_posta`, que tira a hora do texto antes de procurar código.
-- Filtrar depois exigiria saber de onde cada número veio; apagar antes
-- deixa o resto da frase intacta e a busca burra continua correta.
--
--   docker cp valor_nao_e_codigo.sql nay-postgres:/tmp/vc.sql
--   docker exec nay-postgres psql -U nay -d naydb -f /tmp/vc.sql

-- O VÃO entre o rótulo e o valor: só espaço, dois-pontos, cifrão e no
-- máximo uma preposição. NUNCA quebra de linha -- num card, "Locação: R$
-- 2.300" e "Código: 1327" são linhas vizinhas, e um vão frouxo pula da
-- primeira para dentro da segunda e engole o código.
CREATE OR REPLACE FUNCTION nay_tirar_valores(p_texto text)
RETURNS text
LANGUAGE sql IMMUTABLE AS $fn$
  -- Cada linha é uma forma que aparece de verdade nas mensagens. Ordem
  -- importa: as mais específicas primeiro, senão a genérica come metade.
  -- Por último, a pontuação: vírgula/ponto que NÃO precede dígito é
  -- pontuação, não separador decimal. Sem isto "me manda o 3500, 3210 e
  -- 2943" perdia o 3500, porque a extração exige não-vírgula depois do
  -- número -- guarda que existe para não partir "4.000" ao meio.
  SELECT regexp_replace(
         regexp_replace(regexp_replace(regexp_replace(regexp_replace(
         regexp_replace(regexp_replace(regexp_replace(
    lower(coalesce(p_texto,'')),
    -- "entre 3000 e 5000", "de 2500 a 4000"
    '\m(entre|de)\s+[0-9][0-9.,]*\s*(a|e|至|ate|até)\s+[0-9][0-9.,]*', ' ', 'g'),
    -- "R$ 4.000", "R$4000", "$4000"
    '(r\$|\$)\s*[0-9][0-9.,]*', ' ', 'g'),
    -- "4000 reais", "4 mil", "400k", "4000 conto"
    '[0-9][0-9.,]*\s*(reais|real|contos?|mil|k)\M', ' ', 'g'),
    -- "até 4000", "no máximo 4000", "paga 4000", "orçamento de 4000"
    '\m(ate|at[ée]|m[aá]xim[oa]|min[ií]m[oa]|paga(r|ndo)?|pago|proposta|'
    'or[cç]amento|faixa|valor(es)?|limite|teto|budget|invest(ir|imento)?)\M'
    || '[ \t:=–-]*((r\$|\$)[ \t]*)?((de|por|a|at[eé]|em|custa|fica)[ \t]+)?((r\$|\$)[ \t]*)?' || '[0-9][0-9.,]*', ' ', 'g'),
    -- "aluguel de 3500", "venda por 450000", "condomínio 800"
    '\m(aluguel|loca[cç][aã]o|venda|condom[ií]nio|iptu|taxa|entrada|sinal|'
    'parcela|presta[cç][aã]o)\M' || '[ \t:=–-]*((r\$|\$)[ \t]*)?((de|por|a|at[eé]|em|custa|fica)[ \t]+)?((r\$|\$)[ \t]*)?' || '[0-9][0-9.,]*', ' ', 'g'),
    -- ÁREA não é código: "109m2", "88 m²", "120 metros". No card ela cai
    -- na mesma faixa dos códigos de 3 dígitos, e 11 imóveis têm código
    -- entre 100 e 999 -- colisão pequena, mas ela existe e é silenciosa.
    '[0-9][0-9.,]*\s*(m2|m²|mts?|metros?)\M', ' ', 'g'),
    -- número com separador de milhar nunca é código: "4.000", "4,500"
    '[0-9]+[.,][0-9]{3}\M', ' ', 'g'),
    '[.,](?![0-9])', ' ', 'g');
$fn$;

-- Os códigos citados num texto, já sem os valores. Uma definição só, para
-- os dois lados da conversa.
CREATE OR REPLACE FUNCTION nay_codigos_citados(p_texto text)
RETURNS text[]
LANGUAGE sql IMMUTABLE AS $fn$
  SELECT coalesce(array_agg(DISTINCT m[1]), ARRAY[]::text[])
    FROM regexp_matches(' ' || nay_tirar_valores(p_texto) || ' ',
                        '[^0-9.,]([0-9]{3,5})[^0-9.,]', 'g') AS m;
$fn$;
