CREATE OR REPLACE FUNCTION public.core_saida_tel_so_perguntas()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
BEGIN
  -- tudo que a Nay nova manda ao Tel (aviso_tel) é aviso: a pergunta ao corretor já foi para a fila (391) e não passa aqui
  IF NEW.papel_destino = 'tel' AND NEW.estado = 'pendente'
     AND coalesce(nai_cfg('tel_so_perguntas', 'nao'), 'nao') = 'sim' THEN
    NEW.estado := 'bloqueado';
    NEW.bloqueio := 'o Tel só recebe perguntas (482)';
  END IF;
  RETURN NEW;
EXCEPTION WHEN OTHERS THEN
  RAISE WARNING 'core_saida_tel_so_perguntas: %', SQLERRM;
  RETURN NEW;
END
$function$;
