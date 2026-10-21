-- teste da 458 (roda dentro do ensaio, antes do ROLLBACK)
SELECT count(*) AS candidatos, count(*) FILTER (WHERE ok) AS vao, count(*) FILTER (WHERE NOT ok) AS ficam FROM cnm_imoveis();
SELECT f AS motivo, count(*) FROM cnm_imoveis(), jsonb_array_elements_text(falta) f WHERE NOT ok GROUP BY 1 ORDER BY 2 DESC;
SELECT imovel->>'tipo' AS tipo, imovel->>'finalidade' AS fin, count(*) FROM cnm_imoveis() WHERE ok GROUP BY 1, 2 ORDER BY 3 DESC;
SELECT codigo, imovel->>'titulo' AS titulo, imovel->>'valor' AS valor, imovel->>'transacao2' AS t2,
       jsonb_array_length(imovel->'fotos') AS fotos, imovel->'area_comum' AS comum, imovel->'area_privativa' AS priv,
       length(imovel->>'descritivo') AS desc_len
  FROM cnm_imoveis() WHERE ok ORDER BY codigo LIMIT 4;
-- o que do nosso cadastro não achou nome no portal (para ampliar os apelidos)
SELECT t AS sem_par, count(*) FROM imoveis i, unnest(i.caracteristicas) t
 WHERE i.codigo IN (SELECT codigo FROM cnm_imoveis() WHERE ok)
   AND cardinality(cnm_areas(ARRAY[t], 'privativa')) = 0 AND cardinality(cnm_areas(ARRAY[t], 'comum')) = 0
 GROUP BY 1 ORDER BY 2 DESC LIMIT 15;
-- leads: sem senha guardada só passa o User-Agent do portal; o mesmo id não duplica
SELECT cnm_lead_receber('{"id":"T1","name":"Maria","phone":"(92) 99999-0000","createdAt":"2025-11-06 14:30:00","ad":{"reference":"9045","value":850000.00,"purpose":"Venda"}}'::jsonb, 'a@b.c', 'x', 'chavesnamao-leads-api') AS primeiro;
SELECT cnm_lead_receber('{"id":"T1"}'::jsonb, 'a@b.c', 'x', 'chavesnamao-leads-api') AS repetido;
SELECT cnm_lead_receber('{"id":"T2"}'::jsonb, 'a@b.c', 'x', 'curl/8') AS sem_agente;
UPDATE privado.cnm_config SET valor = 'imob@x.com' WHERE chave = 'lead_email';
UPDATE privado.cnm_config SET valor = 'tok' WHERE chave = 'lead_token';
SELECT cnm_lead_receber('{"id":"T3"}'::jsonb, 'IMOB@x.com', 'tok', '') AS com_senha_certa;
SELECT cnm_lead_receber('{"id":"T4"}'::jsonb, 'imob@x.com', 'errado', 'chavesnamao-leads-api') AS senha_errada;
SELECT lead_id, vezes, autenticado, telefone, codigo, valor, criado_no_portal FROM privado.cnm_lead ORDER BY lead_id;
