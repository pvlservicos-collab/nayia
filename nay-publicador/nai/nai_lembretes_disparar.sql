CREATE OR REPLACE FUNCTION public.nai_lembretes_disparar()
 RETURNS integer
 LANGUAGE plpgsql
AS $function$
DECLARE
  l nai_lembrete;
  n int := 0;
BEGIN
  FOR l IN SELECT * FROM nai_lembrete WHERE estado = 'agendado' AND quando <= now() ORDER BY quando FOR UPDATE SKIP LOCKED LOOP
    PERFORM nai_enfileirar_texto(NULL, NULL, l.contato_id, 'equipe', '⏰ Lembrete: ' || l.texto, 'lembrete', 1);
    UPDATE nai_lembrete SET estado = 'enviado', enviado_em = now() WHERE id = l.id;
    n := n + 1;
  END LOOP;
  RETURN n;
END;
$function$
;
