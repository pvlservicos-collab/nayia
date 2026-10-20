CREATE OR REPLACE FUNCTION public.condominio_taxa_aos_imoveis_tg()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
BEGIN
  IF TG_OP = 'INSERT' OR NEW.taxas IS DISTINCT FROM OLD.taxas OR NEW.condominio_id IS DISTINCT FROM OLD.condominio_id
     OR NEW.nome IS DISTINCT FROM OLD.nome OR NEW.nomes_no_imovel IS DISTINCT FROM OLD.nomes_no_imovel THEN
    PERFORM condominio_taxa_aos_imoveis(NEW.id);
  END IF;
  RETURN NULL;
END $function$;
