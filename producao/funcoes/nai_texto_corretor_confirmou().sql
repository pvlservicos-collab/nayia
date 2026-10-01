CREATE OR REPLACE FUNCTION public.nai_texto_corretor_confirmou()
 RETURNS text
 LANGUAGE sql
 STABLE
AS $function$
  -- 255: sem nome de colega. O corretor fala com a Nay, e a Nay é uma só --
  -- quem cuida da visita por dentro é assunto nosso, não dele.
  SELECT CASE WHEN nai_cfg('visita_com_a_rayssa', 'sim') = 'sim'
    THEN 'Certo! Anotei a sua visita. Qualquer novidade sobre ela eu te aviso por aqui.'
    ELSE 'Certo! Vou ver esse horário com o proprietário e já te retorno.' END;
$function$;
