CREATE OR REPLACE FUNCTION public.nay_tirar_valores(p_texto text)
 RETURNS text
 LANGUAGE sql
 IMMUTABLE
AS $function$
  -- Cada linha é uma forma que aparece de verdade nas mensagens. Ordem
  -- importa: as mais específicas primeiro, senão a genérica come metade.
  -- Por último, a pontuação: vírgula/ponto que NÃO precede dígito é
  -- pontuação, não separador decimal. Sem isto "me manda o 3500, 3210 e
  -- 2943" perdia o 3500, porque a extração exige não-vírgula depois do
  -- número -- guarda que existe para não partir "4.000" ao meio.
  SELECT regexp_replace(
         regexp_replace(regexp_replace(regexp_replace(regexp_replace(
         regexp_replace(regexp_replace(regexp_replace(
    regexp_replace(regexp_replace(
    regexp_replace(regexp_replace(
    regexp_replace(lower(coalesce(p_texto,'')),
    -- FAIXA INVERTIDA (121): "opcoes e 3500 E de 5000". O "de" antes do
    -- segundo numero e o que marca preco -- "me manda o 5718 e o 5722"
    -- tem "e o", nao "e de", e continua sendo codigo.
    '[0-9][0-9.,]*[ \t]*(a|e)[ \t]+de[ \t]+[0-9][0-9.,]*', ' ', 'g'),
    -- DOCUMENTO NAO E CODIGO (83): "CRECI 4321", "creci: 4321", "CPF 529.982.247-25".
    '\m(creci|cpf|rg|cnpj|cnh|matricula|matrícula|protocolo)\M[^0-9]{0,15}[0-9][0-9./-]*', ' ', 'g'),
    -- e TELEFONE: "[telefone …5964]", "[telefone …5964]", "98144-5964", "9 8144-5964"
    '(\(?[0-9]{2}\)?[ \t]*)?9?[ \t]?[0-9]{4}[ \t]?-[ \t]?[0-9]{4}\M', ' ', 'g'),
    -- ANO EM DATA nao e codigo (78): "maio 2028", "maio de 2028", "marco/2027".
    '\m(janeiro|fevereiro|mar[cç]o|abril|maio|junho|julho|agosto|setembro|outubro|novembro|dezembro)\M[ \t]*(de[ \t]+|/[ \t]*)?(19|20)[0-9]{2}\M', ' ', 'g'),
    -- e data com barra: "05/2028", "10/05/2028", "10/05/28"
    '\m[0-9]{1,2}[ \t]*/[ \t]*([0-9]{1,2}[ \t]*/[ \t]*)?((19|20)[0-9]{2}|[0-9]{2})\M', ' ', 'g'),
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
$function$;
