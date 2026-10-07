CREATE OR REPLACE FUNCTION public.nai_core_atende(p_contato bigint, p_texto text)
 RETURNS boolean
 LANGUAGE sql
 STABLE
AS $function$
  SELECT CASE
    WHEN lower(coalesce(public.nai_cfg('core_atende', 'nao'), 'nao')) <> 'sim' THEN false
    -- 270: a equipe (Tel, Pedro, Rayssa, acompanhante) continua com a Nay velha
    WHEN public.nai_e_da_equipe_contato(p_contato) THEN false
    -- visita é do sistema velho: a mensagem fala de visita...
    WHEN public.nay_sem_acento(lower(coalesce(p_texto, '')))
         ~ '\m(visita|visitas|visitar|visitacao|agendar|agendamento|agenda|reagendar|remarcar|desmarcar)\M' AND NOT public.nai_pergunta_se_da_para_visitar(p_texto)
         -- 295: citar a visita de passagem num PEDIDO DE IMÓVEL não é marcar visita. "Estou com um cliente
         -- procurando apartamento na Ponta Negra até cinco mil ... ela pode visitar ... pode me passar a descrição
         -- e as fotos?" (Bros, 05/10) ficou com a Nay velha, que respondeu num bloco só e prometeu fotos sem
         -- mandar. Sem dia, hora nem "agendar", e pedindo imóvel, foto ou informação: é do núcleo.
         AND NOT (public.nay_sem_acento(lower(coalesce(p_texto, '')))
                    !~ '\m(agendar|agendamento|agenda|reagendar|remarcar|desmarcar|marcar|hoje|amanha|segunda|terca|quarta|quinta|sexta|sabado|domingo)\M|\d{1,2}\s*(h|hs|horas)\M|\d{1,2}:\d{2}|\d{1,2}/\d{1,2}'
                  AND public.nay_sem_acento(lower(coalesce(p_texto, '')))
                    ~ '\m(fotos?|descricao|informacoes|me (manda|envia|passa)|pode me (mandar|enviar|passar)|procurando|procuro|tem (algum|alguma|apartamento|apto|casa))\M')
         THEN false
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
