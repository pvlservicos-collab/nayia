CREATE OR REPLACE FUNCTION public.captacao_honorarios_tipo(p_lead bigint)
 RETURNS text
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  -- o que ele respondeu à pergunta dos 6% (324): 'inclusos', 'liquido' ou NULL (não respondeu / não deu para saber)
  -- resposta que parece as duas coisas ("Sim $370 tira os 6 por cento") não decide: fica para gente
  SELECT CASE
           WHEN x.r ~ '(liquid|\+\s*6|em cima|por fora|descontad|tira os 6|so quero)'
                AND x.r ~ '(inclus|ja esta|\msim\M|^isso|com a corretagem)' THEN NULL
           WHEN x.r ~ '(liquid|\+\s*6|em cima|por fora|descontad|tira os 6|so quero)' THEN 'liquido'
           WHEN x.r ~ '(inclus|ja esta|\msim\M|^isso|com a corretagem)' THEN 'inclusos'
         END
    FROM (SELECT lower(unaccent(h.resposta)) AS r FROM privado.captacao_honorarios h
           WHERE h.lead_id = p_lead ORDER BY h.id DESC LIMIT 1) x;
$function$;
