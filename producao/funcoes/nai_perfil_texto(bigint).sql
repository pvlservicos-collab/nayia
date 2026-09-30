CREATE OR REPLACE FUNCTION public.nai_perfil_texto(p_contato bigint)
 RETURNS text
 LANGUAGE sql
 STABLE
AS $function$
  SELECT CASE WHEN p.id IS NULL THEN NULL ELSE
    'PERFIL DO CLIENTE DESTE PEDIDO (o que o corretor já disse): '
    || concat_ws(' · ',
         CASE p.negocio WHEN 'venda' THEN 'venda' WHEN 'locacao' THEN 'locação' END,
         nai_rotulo_do_tipo(p.tipo),
         CASE WHEN p.teto IS NOT NULL THEN 'até R$ ' || replace(to_char(p.teto, 'FM999,999,990'), ',', '.') END,
         CASE WHEN p.bairros IS NOT NULL THEN 'bairros: ' || p.bairros END,
         CASE WHEN p.quartos IS NOT NULL THEN 'quartos: ' || p.quartos END,
         CASE WHEN p.mobilia IS NOT NULL THEN 'mobília: ' || p.mobilia END,
         CASE WHEN (p.exige->>'elevador') = 'true' THEN 'só serve com elevador'
              WHEN (p.exige->>'elevador') = 'false' THEN 'pode ser sem elevador' END)
    || '. Use estes dados ao chamar buscar_por_perfil em vez de perguntar de novo. Se ele pedir outro imóvel com outro bairro ou outro valor, é um pedido novo.'
  END
    FROM (SELECT * FROM nai_perfil_ativo(p_contato)) p
   WHERE p.negocio IS NOT NULL OR p.tipo IS NOT NULL OR p.teto IS NOT NULL OR p.bairros IS NOT NULL
      OR p.quartos IS NOT NULL OR p.mobilia IS NOT NULL OR p.exige <> '{}'::jsonb;
$function$;
