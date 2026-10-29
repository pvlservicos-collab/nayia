CREATE OR REPLACE FUNCTION public.pergunta_fila_avisar_no_crm()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'privado'
AS $function$
BEGIN
  PERFORM nay_aviso_equipe('respostas-tel', 'duvida', 'Dúvida nova para o Tel',
    coalesce(nullif(btrim(NEW.cliente), '') || ' (' || CASE WHEN NEW.linha = 'captacao' THEN 'Leads' ELSE 'Parceria' END || ')',
             CASE WHEN NEW.linha = 'captacao' THEN 'Leads' ELSE 'Parceria' END)
    || coalesce(', #' || NEW.codigo, '') || ': ' || left(btrim(NEW.pergunta), 400)
    || E'\nResponda em Respostas Tel, no alto do CRM.', NEW.chave);
  RETURN NEW;
EXCEPTION WHEN OTHERS THEN
  RETURN NEW;          -- o aviso nunca impede a dúvida de entrar na fila
END $function$;
