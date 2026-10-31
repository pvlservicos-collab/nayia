CREATE OR REPLACE FUNCTION public.core_saida_tel_so_perguntas()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE v_m text[];
BEGIN
  -- tudo que a Nay nova manda ao Tel (aviso_tel) é aviso: a pergunta ao corretor já foi para a fila (391) e não passa aqui
  IF NEW.papel_destino = 'tel' AND NEW.estado = 'pendente'
     AND coalesce(nai_cfg('tel_so_perguntas', 'nao'), 'nao') = 'sim' THEN
    NEW.estado := 'bloqueado';
    NEW.bloqueio := 'o Tel só recebe perguntas (482)';
    -- 547: o aviso de MÍDIA ("Tel, o corretor X (55...) mandou 1 imagem(ns)") não tinha outro caminho: vai ao CRM
    v_m := regexp_match(coalesce(NEW.texto, ''), '^Tel, o corretor (.{1,80}?) \((\d{10,15})\) mandou \d+ ');
    IF v_m IS NOT NULL THEN
      PERFORM nay_aviso_equipe('nay-core', 'midia', v_m[1] || ' mandou mídia (Parceria)', NEW.texto, v_m[2]);
      NEW.bloqueio := 'o Tel só recebe perguntas (482); a mídia foi às Notificações do CRM (547)';
    END IF;
  END IF;
  RETURN NEW;
EXCEPTION WHEN OTHERS THEN
  RAISE WARNING 'core_saida_tel_so_perguntas: %', SQLERRM;
  RETURN NEW;
END
$function$;
