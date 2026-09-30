CREATE OR REPLACE FUNCTION public.captacao_ficha_aviso(p_lead_id bigint)
 RETURNS text
 LANGUAGE sql
 STABLE
AS $function$
  SELECT 'FICHA DO IMÓVEL ABERTA -- '
      || CASE c.tipo WHEN 'novo' THEN 'o OUTRO imóvel que ele ofereceu (qual = outro)'
                     ELSE 'o imóvel da campanha, que está disponível (qual = este)' END
      || CASE WHEN c.dados ? '_perguntou'
              THEN '. a última pergunta que você fez foi sobre ' || CASE c.dados->>'_perguntou'
                     WHEN 'local'   THEN 'o tipo e o local do imóvel'
                     WHEN 'negocio' THEN 'se ele quer alugar ou vender'
                     WHEN 'comodos' THEN 'quartos, suítes, banheiros e vagas'
                     WHEN 'area'    THEN 'a área'
                     WHEN 'valor'   THEN 'o valor'
                     WHEN 'taxas'   THEN 'condomínio, IPTU e o que o aluguel inclui'
                     WHEN 'mobilia' THEN 'a mobília'
                     WHEN 'fotos'   THEN 'as fotos'
                     ELSE c.dados->>'_perguntou' END
                   || '. se a mensagem dele responde isso -- mesmo que seja "não sei" --, chame guardar_ficha com o que ele disse'
                   || ' e siga a instrução que ela devolver. se ele falar de outra coisa, siga as regras de sempre: a ficha continua aberta.'
              ELSE '. chame guardar_ficha com o que ele disser do imóvel e siga a instrução que ela devolver.' END
    FROM captacao_cadastro c
    JOIN captacao_leads l ON l.id = c.lead_id
   WHERE c.lead_id = p_lead_id AND c.estado = 'coletando'
     AND (c.tipo = 'novo' OR l.situacao = 'disponivel')
   ORDER BY c.atualizado_em DESC, c.id DESC
   LIMIT 1
$function$;
