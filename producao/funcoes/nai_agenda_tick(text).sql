CREATE OR REPLACE FUNCTION public.nai_agenda_tick(p_quem text DEFAULT 'n8n'::text)
 RETURNS integer
 LANGUAGE plpgsql
AS $function$
BEGIN
  -- 550: só o dono da agenda roda (o nó "Agenda da NAI" do n8n chama sem argumento)
  IF coalesce(nullif(btrim(nai_cfg('agenda_de', 'n8n')), ''), 'n8n') <> p_quem THEN
    RETURN 0;
  END IF;
  RETURN nai_agenda_tick_rodar();
END
$function$;
