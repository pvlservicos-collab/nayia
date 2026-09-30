CREATE OR REPLACE FUNCTION public.nai_verdade_de_pagamento(p_codigo integer, p_afirmacao text)
 RETURNS text
 LANGUAGE sql
 STABLE
AS $function$
  -- 'confere' | 'contradiz' | 'sem_dado'
  SELECT CASE p_afirmacao
    WHEN 'so_a_vista'  THEN CASE WHEN fin ~* '^s' THEN 'contradiz' WHEN fin ~* '^n' THEN 'confere' ELSE 'sem_dado' END
    WHEN 'financia'    THEN CASE WHEN fin ~* '^s' THEN 'confere' WHEN fin ~* '^n' THEN 'contradiz' ELSE 'sem_dado' END
    WHEN 'permuta_sim' THEN CASE WHEN per ~* '^s' THEN 'confere' WHEN per ~* '^n' THEN 'contradiz' ELSE 'sem_dado' END
    WHEN 'permuta_nao' THEN CASE WHEN per ~* '^n' THEN 'confere' WHEN per ~* '^s' THEN 'contradiz' ELSE 'sem_dado' END
    WHEN 'fgts'        THEN CASE WHEN coalesce(nai_ficha_texto_livre(p_codigo), '') ~* 'fgts' THEN 'confere' ELSE 'sem_dado' END
  END
  FROM (SELECT nai_ficha_valor(p_codigo, 'aceita financiamento') AS fin,
               nai_ficha_valor(p_codigo, 'aceita permuta') AS per) x;
$function$
;
