CREATE OR REPLACE FUNCTION public.nay_enfileirar_aviso_de_saida()
 RETURNS trigger
 LANGUAGE plpgsql
AS $function$
BEGIN
  IF coalesce(OLD.disponivel, true) AND NOT coalesce(NEW.disponivel, true) THEN
    INSERT INTO aviso_de_saida (codigo, motivo, marcado_em, avisado_em, erro)
    VALUES (NEW.codigo::text, NEW.motivo_bloqueio, now(), NULL, NULL)
    ON CONFLICT (codigo) DO UPDATE
       SET motivo = excluded.motivo, marcado_em = now(),
           avisado_em = NULL, erro = NULL;
  END IF;
  RETURN NEW;
END;
$function$;
