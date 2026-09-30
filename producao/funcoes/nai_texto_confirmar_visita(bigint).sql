CREATE OR REPLACE FUNCTION public.nai_texto_confirmar_visita(p_visita bigint)
 RETURNS text
 LANGUAGE sql
 STABLE
AS $function$
  SELECT '🏠 *Confirmação de visita*' || E'\n\n'
      || 'Sua visita ao imóvel foi agendada.' || E'\n\n'
      || '🔑 Código do imóvel: #' || v.codigo || E'\n'
      || '📅 Data: ' || to_char(v.quando AT TIME ZONE 'America/Manaus', 'DD/MM') || ' (' || nai_dia_da_semana(v.quando) || ')' || E'\n'
      || '🕐 Horário: ' || to_char(v.quando AT TIME ZONE 'America/Manaus', 'HH24"h"MI') || E'\n\n'
      || 'Por favor, confirme se os dados estão corretos.'
    FROM nai_visita v WHERE v.id = p_visita;
$function$;
