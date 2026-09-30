CREATE OR REPLACE FUNCTION public.nai_mobilia_da_lista(p_codigo integer)
 RETURNS text
 LANGUAGE sql
 STABLE
AS $function$
  WITH i AS (SELECT im.*, lower(unaccent(concat_ws(' ', im.mobilia, array_to_string(im.caracteristicas, ' '), im.descricao,
                         (SELECT f.descricao FROM imovel_ficha f WHERE f.codigo = im.codigo)))) AS tudo
               FROM imoveis im WHERE im.codigo = p_codigo),
  itens AS (SELECT string_agg(x.nome, ', ' ORDER BY x.o) AS lista
              FROM i, (VALUES (1, 'geladeira', 'geladeira'), (2, 'fogão', 'fogao|cooktop'), (3, 'micro-ondas', 'micro.?ondas'),
                              (4, 'máquina de lavar', 'maquina de lavar|lava.?roupa'), (5, 'cama', '\mcama'),
                              (6, 'guarda-roupa', 'guarda.?roupa|roupeiro'), (7, 'armários planejados', 'planejad'),
                              (8, 'sofá', '\msofa'), (9, 'mesa', '\mmesa'), (10, 'TV', '\mtv\M|televis'),
                              (11, 'ar-condicionado', 'ar.?condicionado|\mar\M|climatizad')) AS x(o, nome, rx)
             WHERE i.tudo ~ x.rx)
  SELECT CASE
    WHEN lower(coalesce(i.mobilia, '')) ~ '^semi' OR (coalesce(i.mobilia, '') = '' AND i.tudo ~ 'semi.?mobiliad')
      THEN 'Semimobiliado: está 80% mobiliado' || coalesce(' (' || itens.lista || ')', '')
    WHEN lower(coalesce(i.mobilia, '')) ~ '^mobiliad' OR (coalesce(i.mobilia, '') = '' AND i.tudo ~ '\mmobiliad')
      THEN 'Mobiliado: sim' || coalesce(' (' || itens.lista || ')', '')
    WHEN lower(coalesce(i.mobilia, '')) ~ 'ar.condicionado' THEN 'Mobiliado: não, só com ar-condicionado'
    ELSE NULL END
    FROM i, itens;
$function$;
