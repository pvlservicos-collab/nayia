CREATE OR REPLACE FUNCTION public.nai_recusou(p text)
 RETURNS boolean
 LANGUAGE sql
 IMMUTABLE
AS $function$
  SELECT lower(unaccent(coalesce(p, ''))) ~
    ('(\mnao\s+(gostou|gostaram|curtiu|curtiram|quis|quiseram|quer|querem|tem\s+interesse|teve\s+interesse|se\s+interessou|serve|serviu|atende|atendeu|vai\s+querer|agradou|rolou)'
     || '|\msem\s+interesse|\mdesist\w*|\mdescart\w*|\mdispens\w*'
     || '|\mja\s+(alugou|fechou|achou|encontrou|comprou)|\mfechou\s+(com\s+)?outr|\mficou\s+com\s+outr'
     || '|\machou\s+(muito\s+)?car[oa]|\mmuito\s+car[oa]|\mfora\s+do\s+orcamento'
     || '|\mnao,?\s+obrigad|\mobrigad[oa],?\s+mas\s+nao|\mvou\s+passar\M|\mnao\s+vai\s+dar\M|\mrecus\w*)');
$function$;
