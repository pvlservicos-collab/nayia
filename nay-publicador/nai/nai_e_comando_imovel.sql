CREATE OR REPLACE FUNCTION public.nai_e_comando_imovel(p text)
 RETURNS boolean
 LANGUAGE sql
 IMMUTABLE
AS $function$
  SELECT coalesce(p, '') ~*
    ('^\s*(@?nay[\s,:;.!-]*)?(alugad[oa]|alugou|aluguei|vendid[oa]|vendeu|vendi|'
     || 'indispon[ií]vel|dispon[ií]vel|disponibiliza|liberar?|voltou)\s+[^\n]*\d{3,5}');
$function$
;
