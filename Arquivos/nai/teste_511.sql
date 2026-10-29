-- teste da 511 (roda dentro da transação do ensaio, antes do ROLLBACK)

-- 1. a citação do pedido de busca no grupo: o da Cláudia (sem texto ainda: o rótulo da busca) e um com texto
SELECT quem, texto FROM crm_mensagem_citada(ARRAY['3EB0CD4CAB5CC7BD1EAE8D']);
UPDATE privado.busca_cliente
   SET grupos = grupos || '[{"grupo": "x-group", "nome": "Grupo do teste 511", "em": "2026-10-28T10:15-04:00",
                             "mid": "TESTE511MID", "teste": false, "texto": "✅ PRECISO DE AP P/ VENDA\n- bairros: Flores"}]'::jsonb
 WHERE id = 13;
SET ROLE nay_disparo;
SELECT quem, texto FROM crm_mensagem_citada(ARRAY['TESTE511MID', 'NAOEXISTE511']);
RESET ROLE;

-- 2. "Nay voltar a atender": a pergunta que veio depois da nossa última mensagem fica por ler
INSERT INTO privado.olx_lead_whatsapp (telefone, origem, etapa, assumido_em, humano_em, parada_motivo)
VALUES ('9299990511', 'organico', 'filtrar', now() - interval '1 day', now() - interval '5 hours', 'teste 511');
INSERT INTO captacao_mensagens (telefone, direcao, origem, texto, status) VALUES
  ('559299990511', 'recebida', 'texto', 'oi (já respondida)', 'Processando');
INSERT INTO captacao_mensagens (telefone, direcao, origem, texto, status) VALUES
  ('559299990511', 'enviada', 'resposta', 'Encontrei uma opção', 'Enviado');
INSERT INTO captacao_mensagens (telefone, direcao, origem, texto, status) VALUES
  ('559299990511', 'recebida', 'texto', 'Tem fotos ?', 'Processando');
SELECT * FROM crm_captacao_etapa_manual('5592999990511', 'todos', 'teste 511');
SELECT o.humano_em IS NULL AS solta,
       o.ultima_lida = (SELECT id FROM captacao_mensagens WHERE telefone = '559299990511' AND texto = 'oi (já respondida)') AS leu_so_a_respondida,
       o.ultima_lida < (SELECT id FROM captacao_mensagens WHERE telefone = '559299990511' AND texto = 'Tem fotos ?') AS tem_fotos_por_ler
  FROM privado.olx_lead_whatsapp o WHERE o.telefone = '9299990511';

-- 3. a nota: não vira notificação, vem na lista das notas
SELECT nay_aviso_equipe('nay-olx', 'nota', 'Anúncio da OLX', 'Anúncio: https://am.olx.com.br/x', '559293500979') > 0 AS gravou;
SELECT count(*) AS nota_nas_notificacoes FROM crm_avisos_da_equipe(0) WHERE tipo = 'nota';
SET ROLE nay_disparo;
SELECT titulo, texto, telefone FROM crm_notas_da_nay(1) ORDER BY id DESC LIMIT 1;
RESET ROLE;

-- 4. as duas inteligências
SELECT assunto, aplicada_em, left(regra, 60) regra FROM nay_inteligencia_geral WHERE criada_por = 'migração 511' ORDER BY id;
