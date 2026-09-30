CREATE OR REPLACE FUNCTION public.nai_esperando_valor(p_contato bigint)
 RETURNS boolean
 LANGUAGE sql
 STABLE
AS $function$
  SELECT EXISTS (
    SELECT 1 FROM nai_saida s
     WHERE s.contato_id = p_contato AND s.tipo = 'texto'
       AND s.criado_em > now() - interval '2 hours'
       AND s.texto ~* '(faixa de pre|qual (o )?valor|ate quanto|teto de valor|at[eéÉ] que valor)'
       AND s.id = (SELECT max(s2.id) FROM nai_saida s2
                    WHERE s2.contato_id = p_contato AND s2.tipo = 'texto'));
$function$
;
