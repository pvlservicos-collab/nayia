CREATE OR REPLACE FUNCTION public.nai_estado_por_extenso(p_estado text, p_aguardando text)
 RETURNS text
 LANGUAGE sql
 IMMUTABLE
AS $function$
  SELECT CASE p_estado
           WHEN 'confirmada'              THEN 'confirmada'
           WHEN 'coletando'               THEN 'montando o pedido'
           WHEN 'aguardando_proprietario' THEN 'esperando o proprietário'
           WHEN 'negociando'              THEN 'negociando o horário'
           WHEN 'aguardando_acesso'       THEN 'esperando saber como entra'
           WHEN 'aguardando_motoboy'      THEN 'esperando o ' || nai_acompanhante() || ''
           WHEN 'com_tel'                 THEN 'parada com o Tel'
           ELSE p_estado
         END;
$function$
;
