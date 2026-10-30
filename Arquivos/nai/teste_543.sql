-- teste da 543: a assinatura (md5) da resposta de crm_parceria_marcas para 600 contatos recentes da Nay tem de ser a
-- mesma antes e depois da migração (rodar com `nay q` antes e com `nay ensaio 543 teste_543.sql`). Os telefones vêm do
-- banco na hora: nenhum número fica neste arquivo. Em 30/10 deu a mesma assinatura e 356 -> 77 ms para um contato.
WITH fones AS (
  SELECT array_agg(telefone ORDER BY id DESC) AS f
    FROM (SELECT id, telefone FROM nai_contato WHERE telefone ~ '^[0-9]{12,13}$' ORDER BY id DESC LIMIT 600) x),
a AS (SELECT clock_timestamp() AS t0),
r AS (SELECT md5(string_agg(t::text, '|' ORDER BY t.telefone)) AS h, count(*) AS n FROM fones, crm_parceria_marcas(fones.f) t)
SELECT r.h, r.n, round(extract(epoch FROM clock_timestamp() - a.t0) * 1000) AS ms FROM a, r;
