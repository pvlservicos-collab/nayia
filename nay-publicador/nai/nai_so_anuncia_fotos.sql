CREATE OR REPLACE FUNCTION public.nai_so_anuncia_fotos(p text)
 RETURNS boolean
 LANGUAGE sql
 IMMUTABLE
AS $function$
  SELECT length(x) < 200
     AND x ~* '(foto|imagem|imagens)'
     AND x ~* '(vindo|segue|seguem|mand|envi|sendo|aqui|chegando|est[ãa]o|já|ja )'
     AND x !~* 'c[óo]digo:'
     AND x !~* '(quarto|vaga|valor|aluguel|condom|m2|bairro|dispon)'
  FROM (SELECT btrim(coalesce(p, '')) AS x) t;
$function$
;
