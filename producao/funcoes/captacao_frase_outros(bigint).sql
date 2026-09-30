CREATE OR REPLACE FUNCTION public.captacao_frase_outros(p_lead bigint)
 RETURNS text
 LANGUAGE sql
 STABLE
AS $function$
  SELECT CASE coalesce(l.tratamento, '')
           WHEN 'Sra.' THEN 'Entendi, Sra. ' || coalesce(l.nome, '') ||
                            '. A Sra. tem outro imóvel que queira vender ou alugar?'
           WHEN 'Sr.'  THEN 'Entendi, Sr. ' || coalesce(l.nome, '') ||
                            '. O Sr. tem outro imóvel que queira vender ou alugar?'
           ELSE 'Entendi' || coalesce(', ' || l.nome, '') ||
                '. Você tem outro imóvel que queira vender ou alugar?'
         END
    FROM captacao_leads l WHERE l.id = p_lead;
$function$;
