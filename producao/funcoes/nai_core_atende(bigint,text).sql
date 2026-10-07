CREATE OR REPLACE FUNCTION public.nai_core_atende(p_contato bigint, p_texto text)
 RETURNS boolean
 LANGUAGE sql
 STABLE
AS $function$
  SELECT CASE
    WHEN lower(coalesce(public.nai_cfg('core_atende', 'nao'), 'nao')) <> 'sim' THEN false
    -- 270: a equipe (Tel, Pedro, Rayssa, acompanhante) continua com a Nay velha
    WHEN public.nai_e_da_equipe_contato(p_contato) THEN false
    -- 306: a visita é do núcleo. Ele pergunta o dia e a hora, confirma e, no "sim", a ponte
    -- nai_core_visita_confirmada (302) cria a visita com a Rayssa. Quem cala a Nay durante a visita
    -- é nai_com_a_rayssa, na porta; passou a janela, quem atende de novo é o núcleo.
    -- 307: a visita que o sistema velho já estava confirmando com ele (ou a pergunta de horário de um
    -- comando do Tel) termina com o velho: é ele quem espera esse "sim". Só `confirmando`, por 24 h.
    WHEN EXISTS (SELECT 1 FROM public.nai_visita v
                  WHERE v.corretor_id = ANY (coalesce(public.nai_contato_irmaos(p_contato), ARRAY[p_contato]))
                    AND v.estado = 'confirmando' AND v.atualizado_em > now() - interval '24 hours') THEN false
    -- ficha de cadastro de imóvel aberta com a secretária
    WHEN EXISTS (SELECT 1 FROM public.nai_imovel_novo n
                  WHERE n.contato_id = ANY (coalesce(public.nai_contato_irmaos(p_contato), ARRAY[p_contato]))
                    AND n.situacao = 'colhendo' AND n.criado_em > now() - interval '24 hours') THEN false
    -- canário: com a lista preenchida, só quem está nela
    -- 304: a instrução da equipe (CRM) é lida e executada pelo núcleo (nay-core, nay/instrucao/):
    -- o corretor com instrução valendo segue a regra de todo mundo
    WHEN btrim(coalesce(public.nai_cfg('core_atende_so', ''), '')) <> '' THEN
      (SELECT c.chave FROM public.nai_contato c WHERE c.id = p_contato)
        = ANY (string_to_array(replace(public.nai_cfg('core_atende_so', ''), ' ', ''), ','))
    -- os contatos de teste (espelho da bateria) continuam no velho
    WHEN (SELECT c.chave FROM public.nai_contato c WHERE c.id = p_contato) = ANY (public.nai_chaves_teste()) THEN false
    ELSE true
  END;
$function$;
