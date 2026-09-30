CREATE OR REPLACE FUNCTION public.nai_pede_foto(p_texto text)
 RETURNS boolean
 LANGUAGE sql
 IMMUTABLE
AS $function$
  SELECT x ~ '(foto|fotos|imagem|imagens|fachada|video|fotografia)'
     AND x ~ '(\mtem\M|\mtens\M|teria|manda|mandar|envia|enviar|passa|passar|poderia|pode|queria|quero|gostaria|consegue|me ve|me mostra|mostra|tira)'
     AND x !~ '(ja (recebi|vi|tenho|peguei)|nao precis|dispensa)'
  FROM (SELECT lower(unaccent(coalesce(p_texto, ''))) AS x) t;
$function$;
