CREATE OR REPLACE FUNCTION public.nai_saida_imutavel()
 RETURNS trigger
 LANGUAGE plpgsql
AS $function$
BEGIN
  IF NEW.contato_id <> OLD.contato_id OR NEW.chave_destino <> OLD.chave_destino
     OR NEW.papel_destino <> OLD.papel_destino
     OR NEW.imagem_url IS DISTINCT FROM OLD.imagem_url OR NEW.codigo IS DISTINCT FROM OLD.codigo THEN
    RAISE EXCEPTION 'NAI saida: destino e conteudo de uma mensagem enfileirada nao mudam';
  END IF;
  RETURN NEW;
END;
$function$;
