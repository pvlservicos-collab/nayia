CREATE OR REPLACE FUNCTION public.nai_assunto_sensivel(p_texto text)
 RETURNS text
 LANGUAGE sql
 IMMUTABLE
AS $function$
  -- O que NÃO se responde de cabeça: só com a linha da ficha, ou o Tel.
  SELECT CASE
    WHEN q ~ 'fgts' THEN 'fgts'
    WHEN q ~ '(financ|a vista|avista|forma de pagamento|\mpagamento|\mparcel|carta de credito|consorcio)' THEN 'pagamento'
    WHEN q ~ '(permuta|\mtroca\M|aceita (um |uma )?(carro|veiculo|terreno|imovel|apartamento|casa) (como|na|no|de) )' THEN 'permuta'
    WHEN q ~ '(fiador|caucao|garantia|seguro.?fianca|titulo de capitaliza)' THEN 'garantia'
    WHEN q ~ '(escritura|documenta|averba|quitad|inventario|matricula|habite.?se|regulariz|financiad[oa] pelo)' THEN 'documentacao'
    WHEN q ~ '(\mpets?\M|animal|animais|cachorro|\mgatos?\M|\mcao\M)' THEN 'pet'
  END
  FROM (SELECT lower(unaccent(coalesce(p_texto, ''))) AS q) x;
$function$;
