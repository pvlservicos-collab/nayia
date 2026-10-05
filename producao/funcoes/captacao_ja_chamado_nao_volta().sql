CREATE OR REPLACE FUNCTION public.captacao_ja_chamado_nao_volta()
 RETURNS trigger
 LANGUAGE plpgsql
AS $function$
BEGIN
  IF NEW.status IN ('novo', 'erro') AND OLD.status IS DISTINCT FROM NEW.status
     AND EXISTS (SELECT 1 FROM captacao_mensagens m
                  WHERE m.lead_id = NEW.id AND m.direcao = 'enviada'
                    AND coalesce(m.status, '') <> 'Falhou') THEN
    -- quem já estava num status de "chamado" fica onde estava; quem vinha de 'reservado' ganha o seu
    NEW.status := CASE WHEN OLD.status IN ('enviado', 'respondendo', 'concluido', 'sem_whatsapp') THEN OLD.status
                       WHEN EXISTS (SELECT 1 FROM captacao_mensagens m
                                     WHERE m.lead_id = NEW.id AND m.direcao = 'recebida')
                       THEN 'respondendo' ELSE 'enviado' END;
  END IF;
  RETURN NEW;
END $function$;
