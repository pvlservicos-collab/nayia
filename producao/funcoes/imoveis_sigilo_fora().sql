CREATE OR REPLACE FUNCTION public.imoveis_sigilo_fora()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'privado'
AS $function$
DECLARE s record;
BEGIN
  IF NEW.observacao IS DISTINCT FROM (CASE WHEN TG_OP = 'UPDATE' THEN OLD.observacao END)
     AND nay_e_registro_interno(NEW.observacao) THEN
    SELECT * INTO s FROM nay_separar_sigilo(NEW.observacao, true);
    PERFORM privado.uso_interno_somar(NEW.codigo, 'Tirado da observação do card (504): ' || s.interno);
    NEW.observacao := s.publico;
  END IF;
  IF NEW.descricao IS DISTINCT FROM (CASE WHEN TG_OP = 'UPDATE' THEN OLD.descricao END)
     AND nay_e_sigilo(NEW.descricao) THEN
    SELECT * INTO s FROM nay_separar_sigilo(NEW.descricao, false);
    PERFORM privado.uso_interno_somar(NEW.codigo, 'Tirado da descrição (504): ' || s.interno);
    NEW.descricao := s.publico;
  END IF;
  RETURN NEW;
END $function$;
