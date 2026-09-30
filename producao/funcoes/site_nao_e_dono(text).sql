CREATE OR REPLACE FUNCTION public.site_nao_e_dono(p_nome text)
 RETURNS boolean
 LANGUAGE sql
 IMMUTABLE
AS $function$
  SELECT coalesce(p_nome, '') ~* '(corretor|corretora|parceir|broker|assessoria|imobili[aá]ri|im[oó]veis|ltda|eireli|construtor|empreendiment|imob ?easy|adm imob|secretari|tratar com)';
$function$;
