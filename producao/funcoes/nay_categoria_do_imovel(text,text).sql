CREATE OR REPLACE FUNCTION public.nay_categoria_do_imovel(p_tipo text, p_condominio text)
 RETURNS text
 LANGUAGE sql
 IMMUTABLE
AS $function$
  WITH c AS (SELECT nay_condominio_de_verdade(p_tipo, p_condominio) AS nome)
  SELECT CASE
    WHEN coalesce(p_tipo,'') ~* 'sala|loja|conjunto comercial|andar'
      -- Só a que está em condomínio: decisão do Tel. Sala solta na rua não
      -- entra na lista de salas comerciais.
      THEN CASE WHEN (SELECT nome FROM c) IS NOT NULL
                THEN 'sala' ELSE NULL END
    WHEN coalesce(p_tipo,'') ~* 'casa|sobrado'
      THEN CASE WHEN (SELECT nome FROM c) IS NOT NULL
                THEN 'casa_condominio' ELSE 'casa_via_publica' END
    WHEN coalesce(p_tipo,'') ~* 'apartamento|cobertura|flat|kitnet|kit'
      -- "Apartamento em Via Pública" existe no cadastro e NÃO é o mesmo
      -- produto: o Tel pede apartamento pensando em condomínio.
      THEN CASE WHEN (SELECT nome FROM c) IS NOT NULL
                THEN 'apartamento' ELSE 'apartamento_via_publica' END
    WHEN coalesce(p_tipo,'') ~* 'lote|terreno' THEN 'lote'
    ELSE NULL
  END FROM c;
$function$;
