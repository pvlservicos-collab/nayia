CREATE OR REPLACE FUNCTION public.captacao_rede_da_situacao()
 RETURNS trigger
 LANGUAGE plpgsql
AS $function$
DECLARE v_sit text;
BEGIN
  IF NEW.direcao <> 'recebida' OR NEW.lead_id IS NULL THEN RETURN NEW; END IF;
  v_sit := captacao_situacao_dita(NEW.texto);
  IF v_sit IS NULL THEN RETURN NEW; END IF;

  UPDATE captacao_leads l
     SET situacao = v_sit,
         situacao_por = 'rede',
         -- A etapa so anda quando ela estava PARADA esperando isto. Se a
         -- conversa ja passou desse ponto, a rede grava o dado e nao mexe no
         -- rumo da conversa.
         etapa = CASE WHEN l.etapa = 'aguardando_situacao' AND v_sit = 'vendido'
                        THEN 'aguardando_outros'
                      WHEN l.etapa = 'aguardando_situacao' AND v_sit = 'alugado'
                        THEN 'aguardando_prazo'
                      ELSE l.etapa END,
         atualizado_em = now()
   WHERE l.id = NEW.lead_id
     AND l.situacao IS NULL;   -- o que a IA gravou nunca e sobrescrito
  RETURN NEW;
END;
$function$;
