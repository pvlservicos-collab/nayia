CREATE OR REPLACE FUNCTION public.captacao_mensagem_do_python()
 RETURNS trigger
 LANGUAGE plpgsql
AS $function$
BEGIN
  IF NEW.direcao = 'recebida' AND NEW.status = 'Recebido' AND captacao_e_do_python(NEW.telefone) THEN
    NEW.status := 'Recebido py';
  END IF;
  RETURN NEW;
END
$function$;
