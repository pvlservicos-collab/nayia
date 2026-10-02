CREATE OR REPLACE FUNCTION public.nai_texto_confirmar_visita(p_visita bigint)
 RETURNS text
 LANGUAGE sql
 STABLE
AS $function$
  SELECT '🏠 *Só para confirmar a solicitação de visita*' || E'\n\n'
      || 'Visita ao imóvel:' || E'\n\n'
      || '🔑 Código do imóvel: #' || v.codigo || E'\n'
      || '📅 Data: ' || to_char(v.quando AT TIME ZONE 'America/Manaus', 'DD/MM') || ' (' || nai_dia_da_semana(v.quando) || ')' || E'\n'
      || '🕐 Horário: ' || to_char(v.quando AT TIME ZONE 'America/Manaus', 'HH24"h"MI') || E'\n\n'
      || 'Por favor, confirme se os dados estão corretos para que eu possa entrar em contato com o proprietário.'
    FROM nai_visita v WHERE v.id = p_visita;
$function$;
