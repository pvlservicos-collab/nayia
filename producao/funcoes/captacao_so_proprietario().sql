CREATE OR REPLACE FUNCTION public.captacao_so_proprietario()
 RETURNS trigger
 LANGUAGE plpgsql
AS $function$
DECLARE
  v_motivo text := captacao_fora_da_campanha(OLD.id);
BEGIN
  IF v_motivo IS NULL THEN
    RETURN NEW;
  END IF;
  -- não reserva: marca como conversa de gente (a mesma marca que tira o lead do disparo, do lembrete e da IA) e
  -- devolve NULL, que cancela a reserva. O fluxo recebe zero linhas e não manda nada.
  UPDATE captacao_leads
     SET humano_assumiu_em = coalesce(humano_assumiu_em, now()),
         humano_motivo = coalesce(humano_motivo, left('fora da captação: ' || v_motivo, 200)),
         atualizado_em = now()
   WHERE id = OLD.id;
  RETURN NULL;
END $function$;
