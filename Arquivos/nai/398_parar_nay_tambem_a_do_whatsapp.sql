-- 398: o "Parar Nay" do card da Captação no CRM cala TAMBÉM a Nay do WhatsApp (clientes da OLX e orgânicos, 8595)
--
-- Pedro, 16/10/2026 21:2x: "não consigo parar a Nay ... veja se o botão de parar está funcionando". O botão chamava
-- crm_captacao_etapa_manual('com_o_tel'), que só calava a Nay da CAMPANHA (captacao_leads.humano_assumiu_em); para quem
-- é da Nay do WhatsApp (privado.olx_lead_whatsapp) respondia "não está na campanha, não havia nada para calar" e ela
-- continuava -- foi o caso de uma corretora tratada como lead orgânico.
-- Agora: 'com_o_tel' marca humano_em (a Nay sai da conversa); 'todos' solta: humano_em some, assumido_em vira agora (o
-- que a equipe escreveu antes não a cala de novo) e ultima_lida pula o que ficou para trás (ela responde a PRÓXIMA).
BEGIN;
SET LOCAL lock_timeout = '3s';
DO $do$
DECLARE d text;
BEGIN
  d := pg_get_functiondef('public.crm_captacao_etapa_manual(text,text,text)'::regprocedure);
  IF position('olx_lead_whatsapp' IN d) > 0 THEN RAISE NOTICE 'já remendada'; RETURN; END IF;
  d := replace(d,
    $a$    UPDATE captacao_leads SET humano_assumiu_em = NULL, humano_motivo = NULL
     WHERE right(telefone, 8) = right(v_dig, 8) AND humano_assumiu_em IS NOT NULL;
    RETURN QUERY SELECT true, 'Em Todos: a etapa volta a ser a que a campanha diz.';$a$,
    $b$    UPDATE captacao_leads SET humano_assumiu_em = NULL, humano_motivo = NULL
     WHERE right(telefone, 8) = right(v_dig, 8) AND humano_assumiu_em IS NOT NULL;
    -- 398: a Nay do WhatsApp (OLX/orgânico) volta e responde a PRÓXIMA mensagem
    UPDATE privado.olx_lead_whatsapp o
       SET humano_em = NULL, parada_motivo = NULL, assumido_em = now(), atualizado_em = now(),
           ultima_lida = greatest(o.ultima_lida, (SELECT coalesce(max(m.id), 0) FROM captacao_mensagens m
                                                    WHERE m.direcao = 'recebida'
                                                      AND right(regexp_replace(coalesce(m.telefone, ''), '\D', '', 'g'), 8) = right(v_dig, 8)))
     WHERE right(o.telefone, 8) = right(v_dig, 8) AND o.humano_em IS NOT NULL;
    GET DIAGNOSTICS v_n = ROW_COUNT;
    RETURN QUERY SELECT true, CASE WHEN v_n > 0 THEN 'Em Todos: a Nay volta a atender na próxima mensagem desta pessoa.'
                                   ELSE 'Em Todos: a etapa volta a ser a que a campanha diz.' END;$b$);
  d := replace(d,
    $a$     WHERE right(telefone, 8) = right(v_dig, 8);
    GET DIAGNOSTICS v_n = ROW_COUNT;$a$,
    $b$     WHERE right(telefone, 8) = right(v_dig, 8);
    GET DIAGNOSTICS v_n = ROW_COUNT;
    -- 398: e a Nay do WhatsApp (OLX/orgânico) sai da conversa
    UPDATE privado.olx_lead_whatsapp
       SET humano_em = coalesce(humano_em, now()), atualizado_em = now(),
           parada_motivo = coalesce(parada_motivo, left('CRM: ' || v_quem || ' parou a Nay', 200))
     WHERE right(telefone, 8) = right(v_dig, 8);
    v_n := v_n + (SELECT count(*) FROM privado.olx_lead_whatsapp WHERE right(telefone, 8) = right(v_dig, 8));$b$);
  IF (length(d) - length(replace(d, '398:', ''))) / 4 <> 2 THEN RAISE EXCEPTION 'as âncoras não bateram'; END IF;
  EXECUTE d;
END
$do$;
COMMIT;
