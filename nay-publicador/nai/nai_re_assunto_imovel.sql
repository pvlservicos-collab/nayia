CREATE OR REPLACE FUNCTION public.nai_re_assunto_imovel()
 RETURNS text
 LANGUAGE sql
 IMMUTABLE
AS $function$
  SELECT '(mobiliad|quarto|su[ií]te|banheir|vaga|garagem|\mm2\M|metro|[áa]rea|andar|nascente|poente|valor|pre[çc]o|aluguel|loca[çc][ãa]o|condom[ií]nio|iptu|taxa|dispon[ií]vel|\mpet\M|animal|piscina|academia|portaria|endere[çc]o|bairro|aceita|financ|c[óo]digo)';
$function$
;
