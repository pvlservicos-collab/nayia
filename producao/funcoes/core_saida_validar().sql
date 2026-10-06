CREATE OR REPLACE FUNCTION public.core_saida_validar()
 RETURNS trigger
 LANGUAGE plpgsql
AS $function$
DECLARE
  v_cods int[];
BEGIN
  IF TG_OP = 'UPDATE' THEN
    IF OLD.estado = 'bloqueado' AND OLD.bloqueio LIKE 'imovel de parceria%' THEN
      NEW.estado   := 'bloqueado';
      NEW.bloqueio := OLD.bloqueio;
    END IF;
    RETURN NEW;
  END IF;

  IF NEW.papel_destino = 'tel' THEN
    RETURN NEW;
  END IF;

  v_cods := ARRAY[]::int[];
  IF NEW.codigo IS NOT NULL THEN
    v_cods := v_cods || NEW.codigo;
  END IF;
  IF NEW.tipo = 'texto' AND NEW.texto IS NOT NULL THEN
    v_cods := v_cods || coalesce(
      (SELECT array_agg(m[1]::int)
         FROM regexp_matches(NEW.texto, '(?:C[óo]digo:\s*|#)(\d{3,5})\M', 'gi') AS m),
      ARRAY[]::int[]);
  END IF;

  IF cardinality(v_cods) > 0
     AND EXISTS (SELECT 1 FROM imoveis i
                  WHERE i.codigo = ANY (v_cods) AND coalesce(i.e_parceiro, false)) THEN
    NEW.estado   := 'bloqueado';
    NEW.bloqueio := 'imovel de parceria: nunca enviado (299; codigos '
                    || array_to_string(v_cods, ',') || ')';
  END IF;
  RETURN NEW;
END;
$function$;
