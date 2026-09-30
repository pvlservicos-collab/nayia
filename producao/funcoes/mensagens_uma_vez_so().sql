CREATE OR REPLACE FUNCTION public.mensagens_uma_vez_so()
 RETURNS trigger
 LANGUAGE plpgsql
AS $function$
DECLARE
  v_primeira bigint;
BEGIN
  IF NEW.message_id IS NULL OR NEW.message_id !~ '^[0-9A-F]{16,40}$' THEN
    RETURN NEW;
  END IF;

  -- 147: O ECO DO QUE SAIU, UMA VEZ POR FLUXO. A Z-API reavisa a mesma
  -- mensagem enviada ate 10 vezes, ate 38 min depois (medido em 28/09: 2.768
  -- copias a mais em 3 dias). Cada fluxo guarda uma copia -- o painel de
  -- envios le a do fluxo 'nai' -- e as repetidas nem entram. Os dois fluxos ja
  -- param o eco logo depois de gravar, entao nada deixa de rodar.
  IF NEW.direcao = 'enviada' THEN
    PERFORM pg_advisory_xact_lock(hashtext('eco:' || coalesce(NEW.fluxo, '-') || ':' || NEW.message_id));
    IF EXISTS (SELECT 1 FROM mensagens m
                WHERE m.message_id = NEW.message_id AND m.direcao = 'enviada'
                  AND m.fluxo IS NOT DISTINCT FROM NEW.fluxo
                  AND m.criada_em > now() - interval '2 days') THEN
      RETURN NULL;
    END IF;
    RETURN NEW;
  END IF;
  IF NEW.direcao IS DISTINCT FROM 'recebida' THEN
    RETURN NEW;
  END IF;

  -- Duas cópias chegando juntas: a segunda espera a primeira gravar, e só
  -- então olha. Sem isso as duas olhariam ao mesmo tempo e passariam.
  PERFORM pg_advisory_xact_lock(hashtext('mensagem:' || NEW.message_id));

  SELECT m.id INTO v_primeira
    FROM mensagens m
   WHERE m.message_id = NEW.message_id
     AND m.direcao = 'recebida'
     AND m.criada_em > now() - interval '2 days'
   ORDER BY m.id
   LIMIT 1;

  IF v_primeira IS NULL THEN
    RETURN NEW;
  END IF;

  INSERT INTO mensagem_repetida (message_id, telefone, fluxo, origem, primeira_id)
  VALUES (NEW.message_id, NEW.telefone, coalesce(NEW.fluxo, 'antigo'), NEW.origem, v_primeira);
  RETURN NULL;
END;
$function$;
