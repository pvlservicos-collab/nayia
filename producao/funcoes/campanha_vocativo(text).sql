CREATE OR REPLACE FUNCTION public.campanha_vocativo(p_nome text)
 RETURNS text
 LANGUAGE sql
 STABLE
 SET search_path TO 'public'
AS $function$
  SELECT CASE WHEN v IS NULL OR lower(unaccent(v)) ~ '^(construtora|incorporadora|imobiliaria|empreendimentos?|ltda|me|imob|sr|sra|dr|dra)$'
              THEN NULL ELSE v END
    FROM (SELECT nay_vocativo_dono(btrim(regexp_replace(
                   CASE WHEN p_nome ~* '^\s*(construtora|incorporadora|imobili[aá]ria|empreendimentos?)\M' AND position(' - ' IN p_nome) > 0
                        THEN split_part(p_nome, ' - ', 2) ELSE p_nome END,
                   '^\s*(sr|sra|dr|dra)\.?\s+', '', 'i'))) AS v) x
$function$;
