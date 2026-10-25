CREATE OR REPLACE FUNCTION public.nay_leads_linha_do_dono(p_tel text)
 RETURNS text
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  SELECT CASE WHEN nai_chave(p_tel) IS NOT NULL
                   AND EXISTS (SELECT 1 FROM mensagens m
                                WHERE m.direcao = 'recebida' AND nai_chave(m.telefone) = nai_chave(p_tel))
                   AND EXISTS (SELECT 1 FROM nai_contato c WHERE c.chave = nai_chave(p_tel))
              THEN 'parceria' ELSE 'captacao' END
$function$;
