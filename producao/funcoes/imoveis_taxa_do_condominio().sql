CREATE OR REPLACE FUNCTION public.imoveis_taxa_do_condominio()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE l record; v_nome text := lower(btrim(coalesce(NEW.condominio_nome, '')));
BEGIN
  -- 469 (Pedro, 22/10): a taxa é a do condomínio para aqueles quartos; o que vier escrito no imóvel não vale mais
  IF NEW.quartos IS NULL OR coalesce(NEW.status, '') = 'Excluído' THEN RETURN NEW; END IF;
  SELECT (t->>'condominio')::numeric AS condominio, (t->>'iptu')::numeric AS iptu INTO l
    FROM condominio_ficha f LEFT JOIN condominios c ON c.id = f.condominio_id,
         jsonb_array_elements(f.taxas) WITH ORDINALITY x(t, o)
   WHERE t->>'quartos' = NEW.quartos::text AND t->>'condominio' IS NOT NULL
     AND (f.condominio_id = NEW.condo_id
          OR (NEW.condo_id IS NULL AND v_nome <> ''
              AND (v_nome IN (lower(btrim(f.nome)), lower(btrim(c.nome)))
                   OR v_nome IN (SELECT lower(btrim(x)) FROM unnest(f.nomes_no_imovel) x))))
   ORDER BY (f.condominio_id = NEW.condo_id) DESC NULLS LAST, f.id, o
   LIMIT 1;
  IF l.condominio IS NOT NULL AND NEW.taxa_condominio IS DISTINCT FROM l.condominio THEN
    NEW.taxa_condominio := l.condominio;
    NEW.taxa_condominio_em := now();   -- o carimbo é UPDATE OF taxa_condominio e não vê o que este gatilho escreve
  END IF;
  IF l.iptu IS NOT NULL THEN
    NEW.iptu := l.iptu;
  END IF;
  RETURN NEW;
END $function$;
