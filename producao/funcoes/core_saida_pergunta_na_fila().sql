CREATE OR REPLACE FUNCTION public.core_saida_pergunta_na_fila()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
BEGIN
  IF NEW.papel_destino = 'tel' AND NEW.motivo = 'aviso_tel' AND NEW.estado = 'pendente'
     AND NEW.texto LIKE 'Tel, o corretor %' AND NEW.texto LIKE '%Para eu entregar a resposta a ele: DEVOLVER%'
     AND pergunta_fila_ligada() THEN
    NEW.estado := 'bloqueado';
    NEW.bloqueio := 'vai pela fila de perguntas no PV do Tel (391)';
  END IF;
  RETURN NEW;
EXCEPTION WHEN OTHERS THEN
  RAISE WARNING 'core_saida_pergunta_na_fila: %', SQLERRM;
  RETURN NEW;
END
$function$;
