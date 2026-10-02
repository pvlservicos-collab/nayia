CREATE OR REPLACE FUNCTION public.nai_core_atende(p_contato bigint, p_texto text)
 RETURNS boolean
 LANGUAGE sql
 STABLE
AS $function$
  SELECT CASE
    WHEN lower(coalesce(public.nai_cfg('core_atende', 'nao'), 'nao')) <> 'sim' THEN false
    -- visita é do sistema velho: a mensagem fala de visita...
    WHEN public.nay_sem_acento(lower(coalesce(p_texto, '')))
         ~ '\m(visita|visitas|visitar|visitacao|agendar|agendamento|agenda|reagendar|remarcar|desmarcar)\M' THEN false
    -- ...ou ele tem visita em andamento (ou acabou de acontecer: o resultado dela vem em seguida)
    WHEN EXISTS (SELECT 1 FROM public.nai_visita v
                  WHERE v.corretor_id = ANY (coalesce(public.nai_contato_irmaos(p_contato), ARRAY[p_contato]))
                    AND v.estado NOT IN ('encerrada', 'cancelada', 'expirada')
                    AND (v.estado <> 'realizada' OR v.atualizado_em > now() - interval '3 days')) THEN false
    -- ficha de cadastro de imóvel aberta com a secretária
    WHEN EXISTS (SELECT 1 FROM public.nai_imovel_novo n
                  WHERE n.contato_id = ANY (coalesce(public.nai_contato_irmaos(p_contato), ARRAY[p_contato]))
                    AND n.situacao = 'colhendo' AND n.criado_em > now() - interval '24 hours') THEN false
    -- canário: com a lista preenchida, só quem está nela
    WHEN btrim(coalesce(public.nai_cfg('core_atende_so', ''), '')) <> '' THEN
      (SELECT c.chave FROM public.nai_contato c WHERE c.id = p_contato)
        = ANY (string_to_array(replace(public.nai_cfg('core_atende_so', ''), ' ', ''), ','))
    -- os contatos de teste (espelho da bateria) continuam no velho
    WHEN (SELECT c.chave FROM public.nai_contato c WHERE c.id = p_contato) = ANY (public.nai_chaves_teste()) THEN false
    ELSE true
  END;
$function$;
