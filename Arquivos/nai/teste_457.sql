-- teste da 457: o tempo da fila nova e a conferência final (60 dias e corretor) por conjunto
\timing on
SELECT count(*) AS na_fila FROM captacao_py_fila_do_disparo();
SELECT f AS primeiro FROM captacao_py_fila_do_disparo() f LIMIT 1;
\timing off
WITH fila AS (SELECT f.id FROM captacao_py_fila_do_disparo() f(id)),
corretor AS (SELECT nay_fone_chave(nay_fone_com_ddi(c.telefone)) AS chave FROM corretores c WHERE coalesce(c.telefone, '') <> ''
             UNION SELECT nay_fone_chave(nay_fone_com_ddi(p.telefone)) FROM proprietarios_export p WHERE coalesce(p.corretor, '') ~* 'parceir')
SELECT count(*) FILTER (WHERE EXISTS (SELECT 1 FROM privado.falou_conosco x WHERE x.chave = l.telefone_chave AND x.ultima_em > now() - interval '60 days')) AS falou60,
       count(*) FILTER (WHERE EXISTS (SELECT 1 FROM corretor k WHERE k.chave = l.telefone_chave)) AS corretor
  FROM fila JOIN captacao_leads l ON l.id = fila.id;
