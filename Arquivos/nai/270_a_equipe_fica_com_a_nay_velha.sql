-- 270 (02/10/2026): A EQUIPE FICA COM A NAY VELHA.
--
-- 14:45 de 02/10, com o núcleo novo ligado: a Rayssa mandou um contato para o
-- número da Parceria ("CUESTA (83) ..."). A porta abriu o turno como corretor
-- ("da equipe: sempre atendida") e, pela 269, entregou ao núcleo novo -- que não
-- atende equipe (papel fora do escopo) e ficou calado.
--
-- Quem é da equipe (nai_e_da_equipe_contato) continua aqui: envia imóvel pela
-- caixa, testa, manda comando. O núcleo novo só atende corretor de fora.
BEGIN;
SET LOCAL lock_timeout = '3s';

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

COMMIT;
