CREATE OR REPLACE FUNCTION public.nai_saida_tel_so_perguntas()
 RETURNS trigger
 LANGUAGE plpgsql
 SET search_path TO 'public'
AS $function$
BEGIN
  IF NEW.papel_destino = 'tel' AND NEW.estado = 'pendente'
     AND coalesce(nai_cfg('tel_so_perguntas', 'nao'), 'nao') = 'sim'
     AND coalesce(NEW.motivo, '') NOT IN ('pergunta_fila', 'aviso_saida_pergunta', 'secretaria_pergunta') THEN
    NEW.estado := 'bloqueado';
    NEW.bloqueio := 'o Tel só recebe perguntas (482)';
  END IF;
  RETURN NEW;
EXCEPTION WHEN OTHERS THEN
  RAISE WARNING 'nai_saida_tel_so_perguntas: %', SQLERRM;
  RETURN NEW;
END
$function$;
