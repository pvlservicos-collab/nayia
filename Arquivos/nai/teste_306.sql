-- dentro do ensaio (ROLLBACK no fim). Nada disto sai nem fica.
-- Um corretor de verdade que o núcleo atendeu nos últimos dias, sem marca e sem visita.
CREATE TEMP TABLE _t306 ON COMMIT DROP AS
SELECT k.id AS contato, k.chave, k.telefone
  FROM nai_contato k
 WHERE k.chave ~ '^55' AND k.humano_assumiu_em IS NULL
   AND k.id IN (SELECT t.contato_id FROM nai_core_turno c JOIN nai_turno t ON t.id = c.turno_id
                 WHERE c.criado_em > now() - interval '4 days')
   AND NOT nai_tel_com_a_conversa(k.id) AND nai_com_a_rayssa(k.id, 'corretor') IS NULL
   AND NOT EXISTS (SELECT 1 FROM nai_visita v WHERE v.corretor_id = ANY (coalesce(nai_contato_irmaos(k.id), ARRAY[k.id]))
                      AND v.estado NOT IN ('encerrada', 'cancelada', 'expirada'))
 ORDER BY k.id DESC LIMIT 1;

-- 1. a mensagem que fala de visita vai para a Nay nova
SELECT x.texto, nai_core_atende(p.contato, x.texto) AS a_nucleo_atende_esperado_t, r ->> 'motivo' AS a_motivo_esperado_core_atende
  FROM _t306 p,
       (VALUES ('quero agendar uma visita amanhã às 10h'), ('se ele desejar agendar a visita eu já marco contigo, tá bom?'),
               ('pode remarcar a visita para sexta?')) x(texto),
       LATERAL nai_abrir_turno(p.telefone, NULL, x.texto, NULL, '{}'::bigint[]) r;

-- 2. corretor com visita aberta cuja janela JÁ PASSOU: volta para a Nay nova
SELECT right(c.chave, 4) AS fim, v.estado, to_char(v.quando AT TIME ZONE 'America/Manaus', 'DD/MM HH24:MI') AS visita_em,
       nai_com_a_rayssa(c.id, 'corretor') AS b_com_a_rayssa_esperado_vazio,
       nai_core_atende(c.id, 'bom dia, tem casa no Tarumã?') AS b_nucleo_atende_esperado_t
  FROM nai_visita v JOIN nai_contato c ON c.id = v.corretor_id
 WHERE v.estado = 'com_rayssa' AND NOT nai_visita_com_a_rayssa(v.estado, v.quando)
   AND NOT EXISTS (SELECT 1 FROM nai_visita v2 WHERE v2.corretor_id = v.corretor_id AND nai_visita_com_a_rayssa(v2.estado, v2.quando))
   AND NOT nai_e_da_equipe_contato(c.id) AND c.chave <> ALL (nai_chaves_teste())
 ORDER BY v.atualizado_em DESC LIMIT 3;

-- 3. corretor com a visita DENTRO da janela: continua com a Rayssa, ninguém responde pelo WhatsApp
SELECT right(c.chave, 4) AS fim, nai_com_a_rayssa(c.id, 'corretor') AS c_motivo_da_rayssa,
       (nai_abrir_turno(c.telefone, NULL, 'A visita poderá ser às 16?', NULL, '{}'::bigint[])) ->> 'motivo' AS c_porta_esperado_visita_com_a_rayssa
  FROM nai_visita v JOIN nai_contato c ON c.id = v.corretor_id
 WHERE nai_visita_com_a_rayssa(v.estado, v.quando) AND NOT nai_tel_com_a_conversa(c.id)
 ORDER BY v.atualizado_em DESC LIMIT 1;

-- 4. mensagem com foto: o turno vai para a Nay nova
CREATE TEMP TABLE _m306 ON COMMIT DROP AS
WITH nova AS (
  INSERT INTO mensagens (telefone, direcao, origem, texto, status, message_id, criada_em, fluxo, midia_url)
  SELECT telefone, 'recebida', 'imagem', 'esse aqui tá disponível?', 'Processando', 'TESTE306FOTO', now(), 'nai',
         'https://exemplo.invalid/teste306.jpg' FROM _t306
  RETURNING id)
SELECT id FROM nova;
SELECT r ->> 'ok' AS d_ok, r ->> 'motivo' AS d_motivo_esperado_core_atende
  FROM _t306 p, LATERAL nai_abrir_turno(p.telefone, NULL, 'esse aqui tá disponível?', NULL, ARRAY(SELECT id FROM _m306)) r;

-- 5. o que não muda: a equipe (os comandos do Tel) continua no caminho antigo
SELECT count(*) AS e_contatos_da_equipe, bool_or(nai_core_atende(c.id, 'visitas')) AS e_algum_iria_para_o_nucleo_esperado_f
  FROM nai_contato c WHERE nai_e_da_equipe_contato(c.id);
