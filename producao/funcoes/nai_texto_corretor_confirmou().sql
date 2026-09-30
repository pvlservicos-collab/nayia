CREATE OR REPLACE FUNCTION public.nai_texto_corretor_confirmou()
 RETURNS text
 LANGUAGE sql
 STABLE
AS $function$
  SELECT CASE WHEN nai_cfg('visita_com_a_rayssa', 'sim') = 'sim'
    THEN 'Certo! Anotei a sua visita. A partir de agora quem cuida dela com você é a '
         || nai_cfg('aprovador_visita_nome', 'Rayssa') || ', da nossa equipe, e ela te chama por aqui.'
    ELSE 'Certo! Vou ver esse horário com o proprietário e já te retorno.' END;
$function$;
