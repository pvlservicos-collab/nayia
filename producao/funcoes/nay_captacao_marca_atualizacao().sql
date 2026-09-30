CREATE OR REPLACE FUNCTION public.nay_captacao_marca_atualizacao()
 RETURNS trigger
 LANGUAGE plpgsql
AS $function$
BEGIN
  NEW.atualizado_em := now();
  RETURN NEW;
END $function$;
