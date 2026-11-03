CREATE OR REPLACE FUNCTION public.link_organico_do_lead()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'privado'
AS $function$
DECLARE
  v_cod text;
  v_txt text;
BEGIN
  IF NEW.direcao <> 'recebida' OR coalesce(NEW.texto, '') !~* 'vim d' THEN
    RETURN NULL;
  END IF;
  v_txt := ' ' || link_organico_normal(NEW.texto) || ' ';
  SELECT l.codigo INTO v_cod FROM privado.link_organico l
   WHERE position(' ' || link_organico_normal(l.marca) || ' ' IN v_txt) > 0
   ORDER BY length(l.marca) DESC LIMIT 1;
  IF v_cod IS NOT NULL AND length(regexp_replace(coalesce(NEW.telefone, ''), '\D', '', 'g')) >= 8 THEN
    INSERT INTO privado.link_organico_lead (telefone8, codigo, telefone, primeira_em, mensagem)
    VALUES (right(regexp_replace(NEW.telefone, '\D', '', 'g'), 8), v_cod, NEW.telefone, coalesce(NEW.criada_em, now()),
            left(NEW.texto, 300))
    ON CONFLICT DO NOTHING;
  END IF;
  RETURN NULL;
EXCEPTION WHEN OTHERS THEN
  RAISE WARNING 'link_organico_do_lead: %', SQLERRM;     -- a mensagem nunca cai por causa disto
  RETURN NULL;
END
$function$;
