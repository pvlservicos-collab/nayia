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
