-- 605: a função continua respondendo para uma amostra de telefones (a igualdade com a antiga foi conferida no ensaio de 04/11)
SELECT count(*) AS linhas, count(*) FILTER (WHERE equipe) AS equipe, count(*) FILTER (WHERE proprietario) AS donos
  FROM crm_parceria_marcas((SELECT array_agg(t) FROM (SELECT DISTINCT telefone t FROM nai_contato WHERE telefone ~ '^[0-9]{12,13}$' ORDER BY 1 LIMIT 650) x));
