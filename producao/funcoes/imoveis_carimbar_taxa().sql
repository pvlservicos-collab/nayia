CREATE OR REPLACE FUNCTION public.imoveis_carimbar_taxa()
 RETURNS trigger
 LANGUAGE plpgsql
AS $function$
BEGIN
  -- `IS DISTINCT FROM` e não `<>`: com NULL de um lado o `<>` devolve NULL, a
  -- condição não é verdadeira e a primeira taxa de um imóvel -- que é
  -- exatamente NULL -> valor -- nunca seria carimbada. É a mesma armadilha de
  -- NULL que já derrubou portão neste projeto.
  IF TG_OP = 'INSERT' THEN
    IF NEW.taxa_condominio IS NOT NULL THEN
      NEW.taxa_condominio_em := now();
    END IF;
  ELSIF NEW.taxa_condominio IS DISTINCT FROM OLD.taxa_condominio THEN
    -- Taxa APAGADA perde o carimbo: sem valor não há linha no card, e deixar
    -- data velha pendurada num campo vazio só enganaria a próxima leitura.
    NEW.taxa_condominio_em := CASE WHEN NEW.taxa_condominio IS NULL
                                   THEN NULL ELSE now() END;
  END IF;
  RETURN NEW;
END;
$function$;
