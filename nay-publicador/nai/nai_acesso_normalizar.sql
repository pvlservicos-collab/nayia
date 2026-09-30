CREATE OR REPLACE FUNCTION public.nai_acesso_normalizar(p text)
 RETURNS text
 LANGUAGE sql
 IMMUTABLE
AS $function$
  SELECT CASE
    WHEN x ~ '(fechadura|senha|eletr)' THEN 'fechadura'
    WHEN x ~ '(acompanh|eu abro|ele abre|ela abre|estar la|estarei|proprietario abre|dono abre|abrir)' THEN 'proprietario_acompanha'
    WHEN x ~ '(pegar|buscar|retirar|pega a chave|busca a chave|comigo|com o proprietario|portaria)' THEN 'buscar_chave'
    WHEN x ~ '(chave.*(conosco|com voces|com a gente|imobiliaria|easy|escritorio)|chave_conosco)' THEN 'chave_conosco'
    WHEN x IN ('chave_conosco', 'buscar_chave', 'fechadura', 'proprietario_acompanha') THEN x
    ELSE NULL END
  FROM (SELECT lower(translate(coalesce(p, ''), 'áàâãéêíóôõúç', 'aaaaeeiooouc')) AS x) t;
$function$
;
