CREATE OR REPLACE FUNCTION public.imovel_ficha_sigilo_fora()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'privado'
AS $function$
DECLARE s record;
BEGIN
  IF nay_e_registro_interno(NEW.card) THEN NEW.card := (nay_separar_sigilo(NEW.card, true)).publico; END IF;
  IF nay_e_sigilo(NEW.descricao) THEN NEW.descricao := (nay_separar_sigilo(NEW.descricao, false)).publico; END IF;
  IF nay_e_sigilo(NEW.observacoes) THEN
    SELECT * INTO s FROM nay_separar_sigilo(NEW.observacoes, false);
    PERFORM privado.uso_interno_somar(NEW.codigo, 'Tirado das observações do anúncio do site antigo (504): ' || s.interno);
    NEW.observacoes := s.publico;
  END IF;
  RETURN NEW;
END $function$;
