CREATE OR REPLACE FUNCTION public.nay_e_sigilo(p_texto text)
 RETURNS boolean
 LANGUAGE sql
 IMMUTABLE
AS $function$
  SELECT coalesce(p_texto, '') ~* (
       'comiss[aã]o|comiss[oõ]es|honor[aá]rio|corretagem|taxa da imobili[aá]ria|\ml[ií]quid[oa]s?\M'
    || '|na m[aã]o d[aeo]|margem (de |para )?(negocia|desconto|manobra)|\mo menor valor|valor m[ií]nimo'
    || '|n[aã]o (baixa|faz desconto|aceita(m)? proposta)|negoci[aá]vel at[eé]|chega a (r\$ ?)?[0-9]|aceita descontar'
    || '|(n[aã]o (d[aá]|faz|tem)|sem) (contrato de )?exclusividade|n[aã]o autoriz|n[aã]o (publiqu|anunci|divulg)'
    || '|\mcreci\M|chave do an[uú]ncio|c[oó]digo do an[uú]ncio|consulte o corretor|\mimobili[aá]rias?\M'
    || '|corretora? \w+ (é|e) (o |a )?respons[aá]vel')
$function$;
