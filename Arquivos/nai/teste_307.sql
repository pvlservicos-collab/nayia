-- dentro do ensaio (ROLLBACK no fim).
-- 1. a corretora com a visita em `confirmando`: o "sim" dela continua indo para quem perguntou (a velha)
SELECT right(c.chave, 4) AS fim, v.id AS visita, v.estado,
       nai_core_atende(c.id, 'Sim') AS a_nucleo_atende_esperado_f,
       (nai_abrir_turno(c.telefone, NULL, 'Sim', NULL, '{}'::bigint[])) ->> 'motivo' AS a_motivo_nao_e_core_atende
  FROM nai_visita v JOIN nai_contato c ON c.id = v.corretor_id
 WHERE v.estado = 'confirmando' AND v.atualizado_em > now() - interval '24 hours';

-- 2. confirmação antiga (mais de 24 h) não segura ninguém
UPDATE nai_visita SET atualizado_em = now() - interval '25 hours' WHERE estado = 'confirmando';
SELECT count(*) AS b_corretores_com_confirmacao_velha,
       bool_and(nai_core_atende(v.corretor_id, 'Sim')) AS b_nucleo_atende_esperado_t
  FROM nai_visita v WHERE v.estado = 'confirmando';

-- 3. quem não tem visita em confirmação segue para o núcleo, falando de visita ou não
SELECT nai_core_atende(k.id, 'quero agendar uma visita amanhã às 10h') AS c_visita_nucleo_esperado_t,
       nai_core_atende(k.id, 'bom dia') AS c_comum_nucleo_esperado_t
  FROM nai_contato k
 WHERE k.chave ~ '^55' AND k.humano_assumiu_em IS NULL
   AND k.id IN (SELECT t.contato_id FROM nai_core_turno c JOIN nai_turno t ON t.id = c.turno_id
                 WHERE c.criado_em > now() - interval '4 days')
   AND NOT EXISTS (SELECT 1 FROM nai_visita v WHERE v.corretor_id = k.id AND v.estado = 'confirmando')
 ORDER BY k.id DESC LIMIT 1;
