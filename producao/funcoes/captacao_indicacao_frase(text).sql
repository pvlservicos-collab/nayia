CREATE OR REPLACE FUNCTION public.captacao_indicacao_frase(p_telefone text)
 RETURNS text
 LANGUAGE sql
 STABLE
AS $function$
  WITH l AS (
    SELECT c.tratamento, nay_primeiro_nome(c.nome) AS n, c.codigo, coalesce(c.quer_vender, false) AS quer_vender
      FROM captacao_leads c WHERE c.telefone_chave = nay_fone_chave(p_telefone) LIMIT 1
  ), d AS (
    SELECT l.tratamento,
           -- nome todo em maiúscula ou minúscula vira "Maria"; o que já veio certo fica como está
           CASE WHEN l.n = upper(l.n) OR l.n = lower(l.n) THEN initcap(l.n) ELSE l.n END AS nome,
           (l.quer_vender OR EXISTS (SELECT 1 FROM imoveis i WHERE i.codigo::text = l.codigo
                                        AND coalesce(i.valor_venda, 0) > 0 AND coalesce(i.valor_aluguel, 0) = 0)) AS de_venda
      FROM l
  )
  SELECT coalesce((
    SELECT CASE WHEN d.tratamento IN ('Sr.', 'Sra.') THEN d.tratamento || coalesce(' ' || d.nome, '') || ', estamos'
                WHEN d.nome IS NOT NULL THEN d.nome || ', estamos'
                ELSE 'Estamos' END
           || ' com uma demanda alta de clientes querendo '
           || CASE WHEN d.de_venda THEN 'comprar imóveis' ELSE 'imóveis para locação' END
           || ' nesse final de ano, '
           || CASE d.tratamento WHEN 'Sra.' THEN 'a Sra.' WHEN 'Sr.' THEN 'o Sr.' ELSE 'você' END
           || ' teria alguém para indicar que queira '
           || CASE WHEN d.de_venda THEN 'vender ou alugar?' ELSE 'alugar ou vender?' END
      FROM d),
    'Estamos com uma demanda alta de clientes querendo imóveis para locação nesse final de ano, você teria alguém '
    || 'para indicar que queira alugar ou vender?');
$function$;
