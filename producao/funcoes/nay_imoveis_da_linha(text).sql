CREATE OR REPLACE FUNCTION public.nay_imoveis_da_linha(p_linha text)
 RETURNS TABLE(codigo text, faixa integer, negocio text, no_mercado boolean)
 LANGUAGE plpgsql
 STABLE
AS $function$
DECLARE
  v_cod   text := nay_codigo_da_linha(p_linha);
  v_valor numeric;
BEGIN
  -- ATALHO PELO CÓDIGO, e ele é a razão de esta função ter virado plpgsql.
  --
  -- MEDIDO em 28/09: uma chamada custa ~2 segundos, e quase tudo é
  -- `nay_condominios_candidatos` comparando o nome contra os 387 condomínios
  -- em cinco faixas. A colagem dele tem 24 linhas -- eram 48 segundos só de
  -- casamento, antes de mandar qualquer coisa.
  --
  -- Com o código na linha não há nome a adivinhar: é igualdade. Quando ele
  -- resolve, o funil inteiro é PULADO. O formato novo ficou mais rápido que
  -- o antigo, não mais lento.
  --
  -- DUAS FAIXAS:
  --   -1  o código bate E o valor da linha bate o do negócio
  --    0  o código bate e o valor não bate (ou a linha não traz valor)
  --
  -- A segunda não é luxo: desde 28/09 a lista relê os preços no site antes de
  -- sair, então ele pode colar uma lista de ontem cujo valor já mudou. Sem
  -- ela, o código certo na mão daria "não achei".
  IF v_cod IS NOT NULL THEN
    SELECT pp.valor INTO v_valor FROM nay_partes_da_linha(p_linha) pp;
    RETURN QUERY
      SELECT i.codigo::text,
             CASE WHEN v_valor IS NOT NULL AND v_valor =
                       CASE WHEN n.negocio = 'locacao' THEN coalesce(i.valor_aluguel,0)
                            ELSE coalesce(i.valor_venda,0) END
                  THEN -1 ELSE 0 END,
             n.negocio,
             nay_esta_no_mercado(i.disponivel, i.bloqueado, i.publicado_no_site)
        FROM imoveis i
        CROSS JOIN (VALUES ('locacao'),('venda')) AS n(negocio)
       WHERE i.codigo::text = v_cod
         AND (CASE WHEN n.negocio = 'locacao' THEN coalesce(i.valor_aluguel,0)
                   ELSE coalesce(i.valor_venda,0) END) > 0
       -- Com os dois negócios, o que bate o valor ganha; sem valor que bata,
       -- voltam os dois e quem pergunta é o chamador.
       ORDER BY 2, 3;
    IF FOUND THEN RETURN; END IF;
    -- Código que NÃO EXISTE na tabela não atrapalha: cai no funil de sempre.
  END IF;

  RETURN QUERY
  WITH p AS (SELECT * FROM nay_partes_da_linha(p_linha)),
  neg AS (SELECT * FROM (VALUES ('locacao'),('venda')) AS n(negocio)),
  por_nome AS (
    SELECT i.codigo::text AS cod, c.faixa AS faixa_nome, i.tipo, i.condominio_nome,
           i.quartos, i.suites, i.area_util, i.valor_aluguel, i.valor_venda,
           i.disponivel, i.bloqueado, i.publicado_no_site
      FROM p CROSS JOIN LATERAL nay_condominios_candidatos(p.nome) c
      JOIN imoveis i ON i.condominio_nome = c.nome
    UNION ALL
    SELECT i.codigo::text, 0, i.tipo, i.condominio_nome,
           i.quartos, i.suites, i.area_util, i.valor_aluguel, i.valor_venda,
           i.disponivel, i.bloqueado, i.publicado_no_site
      FROM p JOIN imoveis i
        ON nay_condominio_de_verdade(i.tipo, i.condominio_nome) IS NULL
       AND nay_normalizar_lugar(btrim(coalesce(i.tipo,'') || ' ' || coalesce(i.bairro,'')), true)
         = nay_normalizar_lugar(p.nome, true)
  ),
  com_negocio AS (
    SELECT c.*, n.negocio
      FROM por_nome c CROSS JOIN neg n
     WHERE (n.negocio = 'locacao' AND coalesce(c.valor_aluguel,0) > 0)
        OR (n.negocio = 'venda'   AND coalesce(c.valor_venda,0)   > 0)
  ),
  exata AS (
    SELECT c.cod, 0 AS faixa, c.negocio,
           nay_esta_no_mercado(c.disponivel, c.bloqueado, c.publicado_no_site) AS no_mercado
      FROM com_negocio c
     WHERE nay_normalizar_lugar(nay_linha_sem_codigo(nay_linha_da_lista(c.cod,
             nay_categoria_do_imovel(c.tipo, c.condominio_nome), c.negocio)))
         = nay_normalizar_lugar(nay_linha_sem_codigo(p_linha))
  ),
  por_atributo AS (
    SELECT c.cod, c.faixa_nome + 1 AS faixa, c.negocio,
           nay_esta_no_mercado(c.disponivel, c.bloqueado, c.publicado_no_site) AS no_mercado
      FROM com_negocio c CROSS JOIN p
     WHERE (p.quartos IS NULL OR coalesce(c.quartos,0)   = p.quartos)
       AND (p.suites  IS NULL OR coalesce(c.suites,0)    = p.suites)
       AND (p.area    IS NULL OR coalesce(c.area_util,0) = p.area)
       AND (p.valor   IS NULL
            OR (c.negocio = 'locacao' AND coalesce(c.valor_aluguel,0) = p.valor)
            OR (c.negocio = 'venda'   AND coalesce(c.valor_venda,0)   = p.valor))
  ),
  tudo AS (SELECT * FROM exata UNION ALL SELECT * FROM por_atributo),
  por_codigo AS (SELECT t.cod, min(t.faixa) AS faixa FROM tudo t GROUP BY t.cod),
  melhor AS (SELECT min(pc.faixa) AS faixa FROM por_codigo pc)
  SELECT DISTINCT ON (pc.cod) pc.cod, pc.faixa, t.negocio, t.no_mercado
    FROM por_codigo pc
    JOIN melhor m ON pc.faixa = m.faixa
    JOIN tudo t ON t.cod = pc.cod AND t.faixa = pc.faixa
   ORDER BY pc.cod, t.negocio;
END;
$function$;
