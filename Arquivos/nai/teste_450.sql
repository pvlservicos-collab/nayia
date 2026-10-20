-- teste da 450: roda dentro da transação do ensaio (antes do ROLLBACK). Corretor = o telefone de teste do Pedro.
\echo '--- ontem às 10h: agenda (antes recusava)'
SELECT ok, mensagem, visita FROM crm_visita_agendar((SELECT codigo FROM imoveis WHERE status = 'Disponível' ORDER BY codigo LIMIT 1),
       '5596991712835', 'Pedro teste', ((now() AT TIME ZONE 'America/Manaus')::date - 1 + time '10:00') AT TIME ZONE 'America/Manaus', 60, 'ensaio 450');
\echo '--- o fechamento do dia encerra a de ontem, sem excluir (esperado encerrada, excluida_em vazio)'
SELECT nai_visitas_fechar_dia_passado() IS NOT NULL AS rodou;
SELECT id, estado, motivo, excluida_em FROM nai_visita WHERE criada_no_crm_por = 'ensaio 450' ORDER BY id;
\echo '--- amanhã às 10h, mesmo corretor e outro imóvel; e depois hoje 1 hora atrás no MESMO imóvel de amanhã'
SELECT ok, mensagem FROM crm_visita_agendar((SELECT codigo FROM imoveis WHERE status = 'Disponível' ORDER BY codigo OFFSET 1 LIMIT 1),
       '5596991712835', 'Pedro teste', ((now() AT TIME ZONE 'America/Manaus')::date + 1 + time '10:00') AT TIME ZONE 'America/Manaus', 60, 'ensaio 450');
SELECT ok, mensagem FROM crm_visita_agendar((SELECT codigo FROM imoveis WHERE status = 'Disponível' ORDER BY codigo OFFSET 1 LIMIT 1),
       '5596991712835', 'Pedro teste', now() - interval '1 hour', 60, 'ensaio 450');
\echo '--- esperado: a de amanhã aberta (com_rayssa) e o registro de 1 hora atrás encerrado'
SELECT id, codigo, to_char(quando AT TIME ZONE 'America/Manaus', 'DD/MM HH24:MI') AS quando, estado, motivo
  FROM nai_visita WHERE criada_no_crm_por = 'ensaio 450' ORDER BY id;
