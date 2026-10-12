CREATE OR REPLACE FUNCTION public.nai_imovel_novo_pergunta(p_falta text)
 RETURNS text
 LANGUAGE sql
 IMMUTABLE
AS $function$
  SELECT CASE p_falta
    WHEN 'lugar'     THEN 'Qual o nome do condomínio ou do prédio?'
    WHEN 'bairro'    THEN 'Em que bairro ele fica?'
    WHEN 'tamanho'   THEN 'Qual o tamanho dele, em m²?'
    WHEN 'comodos'   THEN 'Quantos quartos? Algum deles é suíte?'
    WHEN 'banheiros' THEN 'Quantos banheiros?'
    WHEN 'vagas'     THEN 'Quantas vagas de garagem?'
    WHEN 'mobilia'   THEN 'É mobiliado, com modulados e ar, só climatizado ou sem móveis?'
    WHEN 'preco'     THEN 'E o valor? É para venda ou para locação?'
    WHEN 'fotos'     THEN 'Agora me manda as fotos, por favor.'
  END;
$function$;
