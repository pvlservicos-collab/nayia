CREATE OR REPLACE FUNCTION public.nai_linha_acesso_motoboy(v nai_visita)
 RETURNS text
 LANGUAGE sql
 STABLE
AS $function$
  SELECT CASE v.acesso
    WHEN 'chave_conosco' THEN 'A chave está com a gente.'
    WHEN 'buscar_chave' THEN 'A chave fica com o proprietário' || coalesce(': ' || v.acesso_detalhe, '') || '. Precisa pegar antes e devolver depois.'
    WHEN 'fechadura' THEN 'É fechadura eletrônica: te mando a senha ' || nai_cfg_int('aviso_motoboy_min', 30) || ' minutos antes.'
    WHEN 'proprietario_acompanha' THEN 'O proprietário vai estar lá para abrir.'
    ELSE 'O acesso ainda vou confirmar com o Tel.' END;
$function$;
