CREATE OR REPLACE FUNCTION public.imovel_conhecimento_sigilo_fora()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'privado'
AS $function$
BEGIN
  IF nay_e_sigilo(coalesce(NEW.assunto, '') || ' ' || coalesce(NEW.texto, '')) THEN
    PERFORM privado.uso_interno_somar(NULLIF(regexp_replace(NEW.codigo, '\D', '', 'g'), '')::int,
              'Da memória da Nay (504) — ' || NEW.assunto || ': ' || NEW.texto || coalesce(' (' || NEW.quem_contou || ')', ''));
    RETURN NULL;
  END IF;
  NEW.texto := regexp_replace(NEW.texto, '((propriet|procurador)[a-zà-ú]*)\s*\([^)]*\)', '\1', 'gi');
  RETURN NEW;
END $function$;
