CREATE OR REPLACE FUNCTION public.imoveis_taxa_do_condominio()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE l record;
BEGIN
  IF coalesce(NEW.quartos, 0) <= 0 OR coalesce(NEW.status, '') = 'Excluído' THEN RETURN NEW; END IF;
  IF TG_OP = 'UPDATE' AND NEW.condo_id IS NOT DISTINCT FROM OLD.condo_id AND NEW.quartos IS NOT DISTINCT FROM OLD.quartos
     AND NEW.condominio_nome IS NOT DISTINCT FROM OLD.condominio_nome AND NEW.taxa_condominio IS NOT NULL THEN
    RETURN NEW;
  END IF;
  SELECT (t->>'condominio')::numeric AS condominio, (t->>'iptu')::numeric AS iptu INTO l
    FROM condominio_ficha f LEFT JOIN condominios c ON c.id = f.condominio_id,
         jsonb_array_elements(f.taxas) WITH ORDINALITY x(t, o)
   WHERE t->>'quartos' = NEW.quartos::text
     AND (f.condominio_id = NEW.condo_id
          OR (NEW.condo_id IS NULL AND lower(btrim(coalesce(NEW.condominio_nome, ''))) <> ''
              AND lower(btrim(NEW.condominio_nome)) IN (lower(btrim(f.nome)), lower(btrim(c.nome)))))
   ORDER BY (f.condominio_id = NEW.condo_id) DESC NULLS LAST, o
   LIMIT 1;
  IF l.condominio IS NOT NULL AND NEW.taxa_condominio IS DISTINCT FROM l.condominio THEN
    NEW.taxa_condominio := l.condominio;
    NEW.taxa_condominio_em := now();
  END IF;
  IF l.iptu IS NOT NULL THEN
    NEW.iptu := l.iptu;
  END IF;
  RETURN NEW;
END $function$;
