CREATE OR REPLACE FUNCTION public.pergunta_fila_da_pendencia()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
BEGIN
  -- 462: a dúvida da Parceria vai ao agente de revisão (painel dos agentes), não ao PV do Tel
  IF coalesce(nai_cfg('duvida_vai_ao_agente', 'nao'), 'nao') = 'sim' THEN
    RETURN NEW;
  END IF;
  IF pergunta_fila_ligada() THEN
    PERFORM pergunta_fila_entrar('parceria', NEW.chave, NULL, NEW.codigo, NULL, NEW.pergunta, 'core_pendencia', NEW.id,
                                 array_to_string(array_remove(NEW.faltou, 'assunto nao reconhecido'), ', '));
  END IF;
  RETURN NEW;
EXCEPTION WHEN OTHERS THEN
  RAISE WARNING 'pergunta_fila_da_pendencia: %', SQLERRM;     -- a Nay nova nunca cai por causa da fila
  RETURN NEW;
END
$function$;
