SELECT count(*) AS visitas, count(*) FILTER (WHERE proprietario_telefone IS NOT NULL) AS com_dono,
       count(*) FILTER (WHERE corretor_telefone IS NOT NULL) AS com_corretor
  FROM crm_visitas_pessoas((SELECT array_agg(id) FROM nai_visita WHERE quando > now() - interval '3 days'));
SELECT id, right(corretor_telefone, 4) AS corretor, right(proprietario_telefone, 4) AS dono, cardinality(proprietario_chaves) AS chaves
  FROM crm_visitas_pessoas((SELECT array_agg(id) FROM nai_visita WHERE quando > now() - interval '3 days')) ORDER BY id DESC LIMIT 5;
