CREATE OR REPLACE FUNCTION public.nai_imagens_do_envio(p_codigo integer)
 RETURNS TABLE(codigo integer, url text, e_colagem boolean)
 LANGUAGE sql
 STABLE
AS $function$
  -- SEM A COLAGEM AQUI (Tel, 14/09): "a foto metadinha e a foto que e mandada
  -- so na divulgacao dos grupos, e nao quando um corretor pede no pv; quando
  -- ele pede vao todas as fotos". A metadinha agora sai no disparo dos grupos,
  -- pelo publicador (`_fotos_para_grupo`) -- menos no grupo do Anunciar Easy,
  -- que leva todas.
  -- E SEM FOTO QUE JA E MOSAICO (Tel, 14/09): a capa do 4159 no site era uma
  -- montagem de 4 fotos, e ele viu isso como "a metadinha no pv". A foto
  -- marcada em `e_mosaico` (por marcar_mosaicos.py) nao sai no privado.
  SELECT x.codigo, x.url, x.e_colagem FROM (
    SELECT f.codigo, f.url, false AS e_colagem, 1 AS pos, coalesce(f.ordem, 999999) AS ordem, f.id
      FROM imovel_fotos f WHERE f.codigo = p_codigo AND f.e_mosaico IS NOT TRUE
  ) x
  WHERE coalesce(x.url, '') <> ''
  ORDER BY x.pos, x.ordem, x.id;
$function$
;
