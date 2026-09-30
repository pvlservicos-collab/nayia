CREATE OR REPLACE FUNCTION public.nai_ferramenta_de_imovel(p_nome text)
 RETURNS boolean
 LANGUAGE sql
 IMMUTABLE
AS $function$
  SELECT lower(btrim(coalesce(p_nome,''))) IN (
    'imovel_por_codigo', 'buscar_por_perfil', 'listar_no_condominio',
    'disponibilidade_no_condominio', 'resumo_do_condominio',
    'imovel_do_disparo', 'o_que_sei_do_imovel');
$function$
;
