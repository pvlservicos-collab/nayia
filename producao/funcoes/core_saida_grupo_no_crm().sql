CREATE OR REPLACE FUNCTION public.core_saida_grupo_no_crm()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'privado'
AS $function$
DECLARE
  v_quem text;
BEGIN
  IF NEW.papel_destino = 'grupo' AND NEW.estado = 'pendente' AND NEW.tipo = 'texto' THEN
    v_quem := substring(NEW.texto from '^(.{1,80}?) \(\d{10,15}\)');
    PERFORM nay_aviso_equipe('nay-core', 'escalada',
                             coalesce(v_quem || ' precisa da equipe (Parceria)', 'Nay Parceria: precisa da equipe'),
                             NEW.texto, substring(NEW.texto from '\((\d{10,15})\)'));
    NEW.estado   := 'bloqueado';
    NEW.bloqueio := 'aviso à equipe: foi às Notificações do CRM (508)';
  END IF;
  RETURN NEW;
END;
$function$;
