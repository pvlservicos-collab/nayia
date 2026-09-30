CREATE OR REPLACE FUNCTION public.nay_saidas_a_avisar(p_horas integer DEFAULT 6)
 RETURNS TABLE(codigo text, motivo text)
 LANGUAGE sql
 STABLE
AS $function$
  SELECT a.codigo, coalesce(a.motivo, 'alugado')
    FROM aviso_de_saida a
    JOIN imoveis i ON i.codigo::text = a.codigo
   WHERE a.avisado_em IS NULL
     AND a.marcado_em > now() - make_interval(hours => p_horas)
     AND NOT coalesce(i.disponivel, true)   -- voltou atrás: não avisa
   ORDER BY a.marcado_em;
$function$;
