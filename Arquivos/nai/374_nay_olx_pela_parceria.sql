-- 374: a Nay proprietários da OLX conversa pelo WhatsApp da PARCERIA (Z-API, 92 9445-3618), não pelo número oficial
--
-- Pedro, 15/10/2026: "que modelos, maluco? Essa Nay vai responder no WhatsApp Parceria". Na 370 ela abria a conversa
-- por modelo da Meta no número oficial (e os modelos ficaram dias em análise). Na Z-API não há modelo nem janela.
--
-- O CAMINHO, agora:
--   · SAÍDA: o serviço nay-captacao põe a mensagem em nai_saida (papel 'entrega', motivo 'olx_proprietario') e o
--     nay-enviador-manual entrega pela Z-API da Parceria -- o mesmo caminho da Mensagem de negociação (372).
--   · ENTRADA: a mensagem do dono chega na Parceria e passa por nai_abrir_turno. Logo depois do "o Tel assumiu" (que
--     continua valendo: gente assumiu o chat na Parceria, ela cala), se o número é de um dono da OLX com canal
--     'parceria', a mensagem vai para captacao_mensagens ('Recebido py') e a Nay dos corretores NÃO responde
--     (motivo 'olx_proprietario'). O serviço nay-captacao pega da fila e responde.
--   · captacao_leads.canal = 'parceria' marca quem conversa por ali. Hoje só o lead de teste do Pedro (835).

BEGIN;

CREATE OR REPLACE FUNCTION public.captacao_olx_da_parceria(p_tel text, p_contato bigint DEFAULT NULL)
 RETURNS bigint
 LANGUAGE sql
 STABLE
AS $function$
  -- o lead da Nay proprietários da OLX que conversa pela Parceria com este número (ou com um irmão dele: @lid)
  SELECT l.id FROM captacao_leads l JOIN captacao_olx o ON o.lead_id = l.id
   WHERE l.canal = 'parceria' AND NOT coalesce(l.opt_out, false)
     AND o.atualizado_em > now() - interval '30 days'
     AND (nay_fone_chave(l.telefone) = nay_fone_chave(p_tel)
          OR nay_fone_chave(l.telefone) IN (SELECT nay_fone_chave(c.telefone) FROM nai_contato c
                                             WHERE c.id = ANY (coalesce(nai_contato_irmaos(p_contato), ARRAY[p_contato]))))
   ORDER BY l.id LIMIT 1
$function$;
COMMENT ON FUNCTION public.captacao_olx_da_parceria(text, bigint) IS
  '374: o dono da OLX que conversa com a Nay proprietários da OLX pela Parceria (a NAI não atende esse número).';

DO $$
DECLARE v text; a text;
BEGIN
  v := pg_get_functiondef('public.nai_abrir_turno(text,text,text,text,bigint[])'::regprocedure);
  a := E'    RETURN jsonb_build_object(''ok'', false, ''motivo'', ''tel_assumiu'', ''contato_id'', v_contato);\n  END IF;\n';
  IF position(a IN v) = 0 THEN RAISE EXCEPTION 'nai_abrir_turno mudou: não achei o fim do bloco tel_assumiu'; END IF;
  IF position('olx_proprietario' IN v) > 0 THEN RAISE EXCEPTION 'a 374 já está aplicada'; END IF;
  v := replace(v, a, a || $bloco$
  -- 374 (Pedro, 15/10/2026): O DONO DA OLX NA PARCERIA. Quem conversa com a Nay proprietários da OLX pela Parceria
  -- não é corretor: a mensagem vai para a fila dela (captacao_mensagens, 'Recebido py', o serviço nay-captacao
  -- responde) e a NAI não atende. Depois do "o Tel assumiu", de propósito: gente no chat cala as duas.
  DECLARE v_olx bigint := captacao_olx_da_parceria(p_tel, v_contato);
  BEGIN
    IF v_olx IS NOT NULL THEN
      INSERT INTO captacao_mensagens (lead_id, telefone, direcao, origem, texto, status, criada_em)
      SELECT v_olx, l.telefone, 'recebida', 'texto', coalesce(p_texto, ''), 'Recebido py', now() - interval '20 seconds'
        FROM captacao_leads l WHERE l.id = v_olx AND btrim(coalesce(p_texto, '')) <> '';
      UPDATE captacao_leads SET status = CASE WHEN status IN ('enviado', 'reservado', 'erro') THEN 'respondendo' ELSE status END,
             respondeu_em = coalesce(respondeu_em, now()), atualizado_em = now()
       WHERE id = v_olx;
      RETURN jsonb_build_object('ok', false, 'motivo', 'olx_proprietario', 'contato_id', v_contato, 'lead_captacao', v_olx);
    END IF;
  END;
$bloco$);
  EXECUTE v;
END $$;

-- A TRAVA DE "REPETIDA" (mesmo texto à mesma pessoa em 10 min) não vale para ela: a conversa é um roteiro, e o
-- "Certo." de cada pergunta sairia barrado da segunda vez em diante. As travas dela são as do serviço (SILENCIO,
-- roteiro no banco, gente assumiu).
DO $$
DECLARE v text; a text := 'coalesce(r.motivo, '''') <> ''depois_das_fotos''';
BEGIN
  v := pg_get_functiondef('public.nai_liberar_saida(bigint,boolean)'::regprocedure);
  IF position(a IN v) = 0 THEN RAISE EXCEPTION 'nai_liberar_saida mudou: não achei a exceção do depois_das_fotos'; END IF;
  v := replace(v, a, 'coalesce(r.motivo, '''') NOT IN (''depois_das_fotos'', ''olx_proprietario'')');
  EXECUTE v;
END $$;

-- o lead de teste do Pedro passa a conversar pela Parceria; a abertura sai de novo (pela Z-API, sem modelo)
UPDATE captacao_leads SET canal = 'parceria', atualizado_em = now() WHERE id = 835;
UPDATE captacao_olx SET aberto_em = NULL, abertura_tentada_em = NULL, respostas = '{}'::jsonb, atualizado_em = now()
 WHERE lead_id = 835;

COMMIT;
