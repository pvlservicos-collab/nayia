CREATE OR REPLACE FUNCTION public.nai_mobilia_da_lista(p_codigo integer)
 RETURNS text
 LANGUAGE sql
 STABLE
AS $function$
  WITH i AS (
    SELECT im.*,
           lower(unaccent(concat_ws(' ', im.mobilia, array_to_string(im.caracteristicas, ' '),
                  im.descricao,
                  (SELECT f.descricao FROM imovel_ficha f WHERE f.codigo = im.codigo)))) AS tudo
      FROM imoveis im WHERE im.codigo = p_codigo),
  -- o nível: da coluna quando existe; do texto solto quando o cadastro é antigo
  n AS (
    SELECT coalesce(
             nay_mobilia_nivel(i.mobilia),
             CASE WHEN i.tudo ~ 'semi.?mobiliad' THEN 'semi'
                  WHEN i.tudo ~ '\mmobiliad'     THEN 'mobiliado' END) AS nivel
      FROM i),
  itens AS (
    SELECT string_agg(x.nome, ', ' ORDER BY x.o) AS lista,
           -- sem o ar: no nível "com modulados e AR" o rótulo já disse, e
           -- "com modulados e ar (ar-condicionado)" é eco bobo
           string_agg(x.nome, ', ' ORDER BY x.o) FILTER (WHERE x.o <> 11) AS lista_sem_ar
      FROM i, (VALUES (1, 'geladeira', 'geladeira'), (2, 'fogão', 'fogao|cooktop'),
                      (3, 'micro-ondas', 'micro.?ondas'),
                      (4, 'máquina de lavar', 'maquina de lavar|lava.?roupa'),
                      (5, 'cama', '\mcama'), (6, 'guarda-roupa', 'guarda.?roupa|roupeiro'),
                      (7, 'armários planejados', 'planejad'), (8, 'sofá', '\msofa'),
                      (9, 'mesa', '\mmesa'), (10, 'TV', '\mtv\M|televis'),
                      (11, 'ar-condicionado', 'ar.?condicionado|\mar\M|climatizad')) AS x(o, nome, rx)
     WHERE i.tudo ~ x.rx)
  -- a lista de itens só onde ela ajuda: dizer quais móveis existem num imóvel
  -- "sem móveis" seria contradição, e em "só climatizado" o único item seria
  -- justamente o ar que o rótulo já disse
  SELECT CASE n.nivel
           WHEN 'semi'      THEN 'Mobília: ' || nay_mobilia_rotulo('semi')
                                 || coalesce(' (' || itens.lista_sem_ar || ')', '')
           WHEN 'mobiliado' THEN 'Mobília: ' || nay_mobilia_rotulo('mobiliado')
                                 || coalesce(' (' || itens.lista || ')', '')
           WHEN 'climatizado' THEN 'Mobília: ' || nay_mobilia_rotulo('climatizado')
                                 || ' (ar-condicionado)'
           WHEN 'nada'      THEN 'Mobília: ' || nay_mobilia_rotulo('nada')
         END
    FROM n, itens;
$function$;
