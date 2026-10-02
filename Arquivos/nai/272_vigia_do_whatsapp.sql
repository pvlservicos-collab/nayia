-- 272 (02/10/2026): O VIGIA DO WHATSAPP REENVIA O QUE FICOU PRESO.
--
-- Pedro, 02/10: "quando um número desconectar, o outro número manda lá no nosso grupo um aviso
-- claro avisando que a Nay caiu, e limpa a fila que ficou e reenvia a fila de forma mais lenta,
-- para a Nay não cair."
--
-- O WhatsApp da Parceria ficou desconectado da Z-API das 14:45 às 16:00 de 02/10. A Z-API
-- continuou aceitando os envios (a caixa marcou "enviado") e, na volta, soltou 68 mensagens em
-- dois minutos.
--
-- Quem vigia é um script fora do banco (scripts/servidor/vigia_whatsapp.py, no cron da VPS1): ele
-- tira da fila da Z-API o que ficou preso, guarda, e manda de novo devagar quando o número volta.
-- NENHUMA função da caixa muda. O banco só precisa de duas coisas:
--
--   nai_whatsapp_reenviado  a mensagem saiu de novo com OUTRO id. A caixa passa a conhecer o id
--                           novo, senão o eco dela seria lido como "o Tel escreveu" e a citação
--                           do card não acharia o imóvel.
--   nai_whatsapp_da_fila    o que era a mensagem, para o vigia remontar um item da fila que ele
--                           não soube ler.
BEGIN;
SET LOCAL lock_timeout = '3s';

CREATE OR REPLACE FUNCTION public.nai_whatsapp_reenviado(p_antigos text[], p_novo text, p_resposta jsonb DEFAULT '{}'::jsonb)
 RETURNS text
 LANGUAGE plpgsql
AS $function$
DECLARE
  r      record;
  v_onde text := 'fora_da_caixa';
BEGIN
  IF nullif(btrim(coalesce(p_novo, '')), '') IS NULL OR coalesce(array_length(p_antigos, 1), 0) = 0 THEN
    RETURN 'sem_id';
  END IF;

  FOR r IN
    SELECT s.id, s.message_id, s.telefone_final, s.texto, s.imagem_url
      FROM nai_saida s
     WHERE s.estado = 'enviado' AND s.criado_em > now() - interval '4 days'
       AND (s.message_id = ANY (p_antigos) OR s.resposta->>'zaapId' = ANY (p_antigos)
            OR s.resposta->>'messageId' = ANY (p_antigos))
  LOOP
    UPDATE nai_saida
       SET message_id = p_novo, enviado_em = now(),
           resposta = coalesce(resposta, '{}'::jsonb) || coalesce(p_resposta, '{}'::jsonb)
                      || jsonb_build_object('reenviado_em', now(), 'id_antigo', r.message_id)
     WHERE id = r.id;
    INSERT INTO mensagem_saida (message_id, telefone, texto)
         VALUES (p_novo, r.telefone_final, coalesce(r.texto, r.imagem_url))
    ON CONFLICT (message_id) DO NOTHING;
    UPDATE envios SET message_id = p_novo, enviado_em = now() WHERE message_id = r.message_id;
    v_onde := 'nai_saida';
  END LOOP;

  -- a caixa do núcleo novo (nay-core)
  UPDATE core_saida
     SET message_id = p_novo, enviado_em = now(),
         resposta = coalesce(resposta, '{}'::jsonb) || coalesce(p_resposta, '{}'::jsonb)
                    || jsonb_build_object('reenviado_em', now(), 'id_antigo', message_id)
   WHERE estado = 'enviado' AND criado_em > now() - interval '4 days' AND message_id = ANY (p_antigos);
  IF FOUND AND v_onde = 'fora_da_caixa' THEN v_onde := 'core_saida'; END IF;

  RETURN v_onde;
END;
$function$;

COMMENT ON FUNCTION public.nai_whatsapp_reenviado(text[], text, jsonb) IS
  '272: o vigia do WhatsApp mandou de novo uma mensagem que ficou presa na fila da Z-API; troca o id antigo pelo novo na caixa.';

CREATE OR REPLACE FUNCTION public.nai_whatsapp_da_fila(p_ids text[])
 RETURNS jsonb
 LANGUAGE sql
 STABLE
AS $function$
  SELECT jsonb_build_object('tipo', s.tipo, 'telefone', s.telefone_final,
                            'texto', coalesce(s.resposta->>'texto_final', s.texto), 'imagem', s.imagem_url)
    FROM nai_saida s
   WHERE s.criado_em > now() - interval '4 days'
     AND (s.message_id = ANY (p_ids) OR s.resposta->>'zaapId' = ANY (p_ids) OR s.resposta->>'messageId' = ANY (p_ids))
   ORDER BY s.id DESC
   LIMIT 1;
$function$;

COMMENT ON FUNCTION public.nai_whatsapp_da_fila(text[]) IS
  '272: o que era a mensagem da caixa com este id (o vigia do WhatsApp usa para remontar um item da fila da Z-API).';

COMMIT;
