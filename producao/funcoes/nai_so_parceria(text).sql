CREATE OR REPLACE FUNCTION public.nai_so_parceria(p text)
 RETURNS boolean
 LANGUAGE sql
 IMMUTABLE
AS $function$
  SELECT length(btrim(regexp_replace(regexp_replace(lower(unaccent(coalesce(p, ''))),
           '(\m(aceit\w*|faz|fazem|fazemos|fazendo|faco|gostaria|estar|faria|fariam|trabalh\w*|vamos|bora|rola|topa|tem|teem|disponive\w*|para|pra|com|essa|a|de|fazer|voce|voces|vc|vcs|sou|corretora?|eu|nay|nayara|oi|ola|bom|boa|dia|tarde|noite|tudo|bem|amiga|amigo|por|favor|nos|imoveis|seus|suas|de|locacao|locacoes|alugueis|sim|ai|aqui|tambem|tbm|ja|estou|la|no|easy)\M|parcerias?)', ' ', 'g'),
           '[^[:alpha:]]', '', 'g'))) < 3;
$function$;
