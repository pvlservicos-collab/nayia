CREATE OR REPLACE FUNCTION public.imoveis_parceiro_pelo_captador()
 RETURNS trigger
 LANGUAGE plpgsql
AS $function$
BEGIN
  -- `administrado` e parceiro ao mesmo tempo viola chk_parceiro_nao_administrado:
  -- nesse caso nao mexe (e o humano quem resolve).
  IF NOT coalesce(NEW.administrado, false)
     AND (nai_captador_e_parceiro(NEW.captado_por)
          OR nai_captador_e_parceiro(coalesce(NEW.extras, '{}'::jsonb)->>'captado por')) THEN
    NEW.e_parceiro := true;
  END IF;
  RETURN NEW;
END;
$function$;
