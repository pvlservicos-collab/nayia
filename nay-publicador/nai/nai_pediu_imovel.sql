CREATE OR REPLACE FUNCTION public.nai_pediu_imovel(p_turno bigint)
 RETURNS boolean
 LANGUAGE sql
 STABLE
AS $function$
  -- NULL (Jev calado) devolve TRUE: sem resposta dele, nada muda em
  -- relacao a hoje. Este portao so aperta quando ha resposta.
  SELECT coalesce(nai_jev_pedido(p_turno), true);
$function$
;
