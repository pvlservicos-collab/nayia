CREATE OR REPLACE FUNCTION public.nai_retomada_texto(p_contato bigint)
 RETURNS text
 LANGUAGE sql
 STABLE
AS $function$
  SELECT E'(informação de sistema) CONTEXTO DA CONVERSA ATÉ AQUI (revisão de '
         || to_char(r.criado_em AT TIME ZONE 'America/Manaus', 'DD/MM') || ', etapa ' || r.etapa || '): '
         || coalesce(r.resumo, '')
         || coalesce(E'\nSe ELE voltar a esse assunto: ' || nullif(r.proximo_passo, ''), '')
         || E'\nIsto é só para você saber onde ele parou. NÃO mande card, foto nem lista de imóvel sem ele pedir '
         || E'NESTA mensagem; se ele só cumprimentar ou agradecer, responda isso e pergunte como pode ajudar.\n'
    FROM nai_retomada_resumo r
   WHERE r.contato_id = ANY (coalesce(nai_contato_irmaos(p_contato), ARRAY[p_contato])) AND r.valido_ate > now()
   ORDER BY r.criado_em DESC LIMIT 1;
$function$;
