CREATE OR REPLACE FUNCTION public.nai_e_sim_curto(p text)
 RETURNS boolean
 LANGUAGE sql
 IMMUTABLE
AS $function$
  SELECT lower(unaccent(btrim(coalesce(p, '')))) ~
    ('^(sim|s|isso|isso mesmo|isso ai|correto|certo|certinho|confirmo|confirmado|confirmada|pode|pode ser|pode sim|ok|okay|beleza|blz|'
     || 'perfeito|exato|ta certo|esta certo|tudo certo|sim,? (esta|ta) (certo|correto)|sim,? pode|sim,? isso|sim,? correto|'
     || 'sim,? confirmo|sim,? confirmado|sim,? perfeito)[\s.!,👍]*$');
$function$
;
