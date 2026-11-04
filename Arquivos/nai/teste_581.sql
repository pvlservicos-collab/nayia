-- 581: o Moacy (...5300, dono parado da campanha, perguntado pela busca #59) passa; os outros casos ficam como eram
SELECT 'moacy agora entra' caso, busca_corretor_e('5592991315300') = true AS passou;
SELECT 'nosso número continua fora' caso,
       coalesce(bool_and(NOT busca_corretor_e('55' || n)), true) AS passou FROM unnest(busca_nossos_numeros()) n;
SELECT 'cliente da Nay Leads continua fora' caso,
       NOT busca_corretor_e((SELECT telefone FROM privado.olx_lead_whatsapp ORDER BY id DESC LIMIT 1)) AS passou;
SELECT 'dono com a captação ativa e não perguntado continua fora' caso,
       coalesce(bool_and(NOT busca_corretor_e(l.telefone)), true) AS passou
  FROM (SELECT telefone FROM captacao_leads WHERE humano_assumiu_em IS NULL ORDER BY id DESC LIMIT 50) l;
SELECT 'quantos mudam de fora para dentro' caso, count(*) AS n
  FROM privado.busca_contato c
 WHERE c.em > now() - interval '7 days'
   AND EXISTS (SELECT 1 FROM captacao_leads l WHERE right(regexp_replace(coalesce(l.telefone, ''), '\D', '', 'g'), 8) = c.telefone8
                                               AND l.humano_assumiu_em IS NOT NULL);
