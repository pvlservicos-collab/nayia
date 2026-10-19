-- 411: a etapa do cliente da OLX vale para QUALQUER conversa do número de captação (18/10/2026)
--
-- Pedro: "corrige nesse mesmo card: as etapas não atualizam". O card da Captação (CRM) salva a etapa por
-- crm_olx_cliente_etapa, que só fazia UPDATE em privado.olx_lead_whatsapp: quem não entrou pela Nay do WhatsApp (nem
-- pelo anúncio da OLX, nem como orgânico) não tinha linha, a função devolvia nada e o CRM dizia "não é cliente da OLX".
-- Agora, sem linha, ela CRIA uma (origem 'manual', etapa escolhida): a lista e o card passam a mostrar a etapa, e a
-- Nay do WhatsApp, se a pessoa escrever, segue a regra da etapa (as de equipe — proprietarios, fechamento, finalizado —
-- ela não atende). O telefone fica no formato da tabela: só dígitos, sem o 55.
BEGIN;
SET LOCAL lock_timeout = '3s';
-- a origem 'manual' (a linha que o CRM cria): a Nay do WhatsApp trata como qualquer outra; a tag "Orgânico" do CRM
-- continua só para origem 'organico'
ALTER TABLE privado.olx_lead_whatsapp DROP CONSTRAINT IF EXISTS olx_lead_whatsapp_origem_check;
ALTER TABLE privado.olx_lead_whatsapp ADD CONSTRAINT olx_lead_whatsapp_origem_check CHECK (origem IN ('olx', 'organico', 'manual'));
CREATE OR REPLACE FUNCTION public.crm_olx_cliente_etapa(p_telefone text, p_etapa text)
RETURNS boolean
LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public', 'privado' AS $function$
DECLARE v_tel text; v_n int;
BEGIN
  IF p_etapa NOT IN ('filtrar', 'feito_busca', 'imoveis_enviados', 'visita', 'proprietarios', 'fechamento', 'finalizado') THEN
    RETURN false;
  END IF;
  v_tel := regexp_replace(coalesce(p_telefone, ''), '\D', '', 'g');
  IF length(v_tel) < 8 THEN RETURN false; END IF;
  UPDATE privado.olx_lead_whatsapp SET etapa = p_etapa, etapa_em = now(), atualizado_em = now()
   WHERE right(telefone, 8) = right(v_tel, 8);
  GET DIAGNOSTICS v_n = ROW_COUNT;
  IF v_n > 0 THEN RETURN true; END IF;
  IF length(v_tel) IN (12, 13) AND left(v_tel, 2) = '55' THEN v_tel := substr(v_tel, 3); END IF;
  INSERT INTO privado.olx_lead_whatsapp (telefone, etapa, etapa_em, origem)
  VALUES (v_tel, p_etapa, now(), 'manual');
  RETURN true;
END
$function$;
COMMIT;
