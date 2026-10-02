SELECT
  'no ' || c.nome || ' tenho ' || c.total || CASE WHEN c.total = 1 THEN ' imóvel: ' ELSE ' imóveis: ' END
  || CASE WHEN c.venda > 0 THEN c.venda || ' pra venda (' || CASE WHEN c.venda = 1 THEN replace(to_char(c.vmin,'FM999,999,990'),',','.') ELSE 'de ' || replace(to_char(c.vmin,'FM999,999,990'),',','.') || ' a ' || replace(to_char(c.vmax,'FM999,999,990'),',','.') END || ')' ELSE '' END
  || CASE WHEN c.venda > 0 AND c.locacao > 0 THEN ' e ' ELSE '' END
  || CASE WHEN c.locacao > 0 THEN c.locacao || ' pra locação (' || CASE WHEN c.locacao = 1 THEN replace(to_char(c.lmin,'FM999,999,990'),',','.') ELSE 'de ' || replace(to_char(c.lmin,'FM999,999,990'),',','.') || ' a ' || replace(to_char(c.lmax,'FM999,999,990'),',','.') END || ')' ELSE '' END
  || CASE WHEN c.venda > 0 AND c.locacao > 0 THEN '. é venda ou locação?' ELSE '' END
  AS texto_pronto,
  'ATENCAO: esta faixa de valor e apenas informativa e NAO serve para concluir se existe ou nao existe imovel. Assim que o corretor informar quartos ou valor, chame listar_no_condominio, mesmo que o valor dele pareca fora desta faixa -- a busca usa margem maior. Se a pergunta dele for se TEM ou NAO TEM naquele condominio, use disponibilidade_no_condominio, que responde isso de forma final. O que voce NAO pode e concluir que nao tem olhando so esta faixa de valor.' AS instrucao_para_voce
FROM (
  SELECT i.condominio_nome AS nome,
         count(*) AS total,
         count(*) FILTER (WHERE COALESCE(i.valor_venda,0) > 0) AS venda,
         count(*) FILTER (WHERE COALESCE(i.valor_aluguel,0) > 0) AS locacao,
         min(i.valor_venda) FILTER (WHERE COALESCE(i.valor_venda,0) > 0) AS vmin,
         max(i.valor_venda) FILTER (WHERE COALESCE(i.valor_venda,0) > 0) AS vmax,
         min(i.valor_aluguel) FILTER (WHERE COALESCE(i.valor_aluguel,0) > 0) AS lmin,
         max(i.valor_aluguel) FILTER (WHERE COALESCE(i.valor_aluguel,0) > 0) AS lmax
  FROM imoveis i
  WHERE i.condominio_nome IN (SELECT nome FROM nay_cond($1))
    AND i.disponivel = true
    AND COALESCE(i.bloqueado,false) = false
    AND COALESCE(i.e_parceiro,false) = false
  GROUP BY i.condominio_nome
) c;
