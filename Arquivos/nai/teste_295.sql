SELECT nai_core_atende((SELECT id FROM nai_contato WHERE chave NOT IN (SELECT unnest(nai_chaves_teste())) AND NOT nai_e_da_equipe_contato(id) AND NOT EXISTS (SELECT 1 FROM nai_visita v WHERE v.corretor_id = nai_contato.id) ORDER BY id DESC LIMIT 1), x.t) AS core, left(x.t, 70) AS texto
  FROM (VALUES ('Estou com um cliente procurando apartamento para locação Ponta Negra até cinco mil. Ela pode visitar. Você pode me passar a descrição e as fotos?'),
               ('quero agendar uma visita no 5717'), ('posso visitar amanhã às 10h? me manda as fotos'), ('quero visitar o 5717'),
               ('tem apartamento no aleixo?')) x(t);
SELECT codigo, nai_resposta_da_base(codigo, 'qual o andar? tem escada?') AS resposta
  FROM imoveis WHERE coalesce(andar, '') ~ '^[1-4]$' ORDER BY codigo DESC LIMIT 4;
