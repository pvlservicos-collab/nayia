CREATE OR REPLACE FUNCTION public.nay_descricao_segura(p_texto text)
 RETURNS text
 LANGUAGE sql
 STABLE
AS $function$
  SELECT NULLIF(btrim(regexp_replace(
    CASE WHEN coalesce((SELECT valor FROM config WHERE chave='unidade_nivel'),
                       'apartamento') = 'tudo'
         THEN regexp_replace(x, '\m(torre|bloco|bl|tr)\M\.?\s*[0-9a-z]{1,2}\M',
                             'no condomínio', 'gi')
         ELSE x END,
    '\s+', ' ', 'g')), '')
  FROM (SELECT btrim(regexp_replace(coalesce(p_texto,''),
      -- "apto 801", "apart. 601", "ap 401", "unidade 51" -- mas nunca
      -- "apto 3 QTS" nem "apartamento 2 quartos", que descrevem o tipo.
      '\m(ap|apto|apart|apartamento|unidade|un|porta|casa|sobrado|lote|quadra)\M\.?\s*(n[o°º]?\.?)?\s*'
      || '([0-9]{2,5}[a-z]?)(?!\s*(quarto|qto|dorm|suite|ste|vaga|banheiro|m2|m²|'
      || 'metros|mil|reais|andar|piso|carro|qts|d\M|q\M))',
      -- `\1` devolve o SUBSTANTIVO casado, nao a palavra "apartamento":
      -- some só o número. Antes, "Linda casa 45" virava "Linda
      -- apartamento", que além de errado entregava o tipo trocado.
      '\1', 'gi')) AS x) s;
$function$;
