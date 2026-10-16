-- 387: a mensagem de quem conversa com a NAY DO WHATSAPP DA OLX não vai para a Nay dos proprietários nem para o n8n
--
-- 16/10/2026, no primeiro teste da Nay do WhatsApp (385) no número do Pedro (96 99171-2835): esse número também é o
-- lead de teste da Nay de captação dos proprietários (captacao_config.python_telefones, lead 835). A resposta dele no
-- 8595-6408 viraria 'Recebido py' e a Nay dos proprietários responderia junto, pela Parceria.
-- Agora, na entrada (gatilho captacao_mensagem_do_python), a mensagem recebida de um telefone que está em conversa com a
-- Nay do WhatsApp da OLX (privado.olx_lead_whatsapp: aberta, não finalizada, sem a equipe) ganha o status 'Recebido olx':
-- o n8n só reserva 'Recebido' e o nay-captacao só 'Recebido py', então nenhum dos dois pega. A Nay do WhatsApp lê pelo
-- telefone, sem olhar o status. Quando a equipe assume (humano_em), volta a ser como antes.
-- Backup: /root/backups-funcoes/captacao_mensagem_do_python-2026-10-16-antes-387.sql
BEGIN;
SET LOCAL lock_timeout = '3s';

CREATE OR REPLACE FUNCTION public.captacao_mensagem_do_python()
 RETURNS trigger
 LANGUAGE plpgsql
AS $function$
BEGIN
  IF NEW.direcao = 'recebida' AND NEW.status = 'Recebido' THEN
    -- 387: quem está com a Nay do WhatsApp da OLX é dela
    IF EXISTS (SELECT 1 FROM privado.olx_lead_whatsapp o
                WHERE right(o.telefone, 8) = right(regexp_replace(coalesce(NEW.telefone, ''), '\D', '', 'g'), 8)
                  AND o.assumido_em IS NOT NULL AND o.etapa <> 'finalizado' AND o.humano_em IS NULL) THEN
      NEW.status := 'Recebido olx';
    ELSIF captacao_e_do_python(NEW.telefone) THEN
      NEW.status := 'Recebido py';
    END IF;
  END IF;
  RETURN NEW;
END
$function$;

COMMIT;
