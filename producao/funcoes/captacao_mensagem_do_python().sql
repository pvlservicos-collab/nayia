CREATE OR REPLACE FUNCTION public.captacao_mensagem_do_python()
 RETURNS trigger
 LANGUAGE plpgsql
AS $function$
BEGIN
  IF NEW.direcao = 'recebida' AND NEW.status = 'Recebido' THEN
    -- 387: quem está com a Nay do WhatsApp da OLX é dela; 389: e quem ela está consultando sobre uma visita
    IF EXISTS (SELECT 1 FROM privado.olx_lead_whatsapp o
                WHERE right(o.telefone, 8) = right(regexp_replace(coalesce(NEW.telefone, ''), '\D', '', 'g'), 8)
                  AND o.assumido_em IS NOT NULL AND o.etapa <> 'finalizado' AND o.humano_em IS NULL)
       OR EXISTS (SELECT 1 FROM privado.olx_visita_consulta c
                   WHERE c.estado = 'esperando'
                     AND right(c.telefone, 8) = right(regexp_replace(coalesce(NEW.telefone, ''), '\D', '', 'g'), 8)) THEN
      NEW.status := 'Recebido olx';
    ELSIF captacao_e_do_python(NEW.telefone) THEN
      NEW.status := 'Recebido py';
    END IF;
  END IF;
  RETURN NEW;
END
$function$;
