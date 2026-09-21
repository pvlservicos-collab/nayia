-- =========================================================
-- ATLAS EYE CRM — SEED DATA
-- =========================================================
-- IMPORTANTE: Antes de executar este script, obtenha o UUID
-- do seu usuário no Supabase:
--   SELECT id FROM auth.users LIMIT 1;
--
-- Substitua TODAS as ocorrências de 'YOUR_AUTH_USER_ID' pelo UUID real.
-- =========================================================

-- Limpar dados existentes (em ordem reversa de dependências)
DELETE FROM lead_activities;
DELETE FROM lead_stage_history;
DELETE FROM lead_tags;
DELETE FROM lead_ai_insights;
DELETE FROM leads;
DELETE FROM tags;
DELETE FROM pipeline_stages;
DELETE FROM pipelines;
DELETE FROM organization_members;
DELETE FROM organization_roles;
DELETE FROM profiles;
DELETE FROM organizations;
DELETE FROM tiers;

-- =========================================================
-- 1) TIER
-- =========================================================
INSERT INTO tiers (id, name, max_users, can_use_custom_fields, permissions) VALUES
  ('a0000000-0000-0000-0000-000000000001', 'Pro', 50, true, '{"all": true}'::jsonb);

-- =========================================================
-- 2) ORGANIZATION
-- =========================================================
INSERT INTO organizations (id, name, tier_id, timezone) VALUES
  ('b0000000-0000-0000-0000-000000000001', 'Atlas Eye Demo', 'a0000000-0000-0000-0000-000000000001', 'America/Sao_Paulo');

-- =========================================================
-- 3) PROFILE (vinculado ao auth.users)
-- =========================================================
-- ⚠️ SUBSTITUIR 'YOUR_AUTH_USER_ID' pelo UUID real do auth.users
INSERT INTO profiles (id, full_name, avatar_url, timezone) VALUES
  ('c935d868-e9a8-40b4-99cf-7b618e193a1b', 'Venancio Admin', NULL, 'America/Sao_Paulo')
ON CONFLICT (id) DO UPDATE SET full_name = EXCLUDED.full_name;

-- =========================================================
-- 4) ORGANIZATION ROLE
-- =========================================================
INSERT INTO organization_roles (id, organization_id, name, permissions) VALUES
  ('c0000000-0000-0000-0000-000000000001', 'b0000000-0000-0000-0000-000000000001', 'admin', '{"all": true}'::jsonb);

-- =========================================================
-- 5) ORGANIZATION MEMBER
-- =========================================================
INSERT INTO organization_members (id, organization_id, user_id, role_id, status) VALUES
  ('d0000000-0000-0000-0000-000000000001', 'b0000000-0000-0000-0000-000000000001', 'c935d868-e9a8-40b4-99cf-7b618e193a1b', 'c0000000-0000-0000-0000-000000000001', 'active');

-- =========================================================
-- 6) PIPELINE
-- =========================================================
INSERT INTO pipelines (id, organization_id, name) VALUES
  ('e0000000-0000-0000-0000-000000000001', 'b0000000-0000-0000-0000-000000000001', 'Pipeline Principal');

-- =========================================================
-- 7) PIPELINE STAGES (4 estágios, rank crescente)
-- =========================================================
INSERT INTO pipeline_stages (id, organization_id, pipeline_id, name, rank) VALUES
  ('f0000000-0000-0000-0000-000000000001', 'b0000000-0000-0000-0000-000000000001', 'e0000000-0000-0000-0000-000000000001', 'Lead Capturado', 1.000000),
  ('f0000000-0000-0000-0000-000000000002', 'b0000000-0000-0000-0000-000000000001', 'e0000000-0000-0000-0000-000000000001', 'Qualificação IA', 2.000000),
  ('f0000000-0000-0000-0000-000000000003', 'b0000000-0000-0000-0000-000000000001', 'e0000000-0000-0000-0000-000000000001', 'Agendamento Demo', 3.000000),
  ('f0000000-0000-0000-0000-000000000004', 'b0000000-0000-0000-0000-000000000001', 'e0000000-0000-0000-0000-000000000001', 'Negociação', 4.000000);

-- =========================================================
-- 8) TAGS
-- =========================================================
INSERT INTO tags (id, organization_id, name, color) VALUES
  ('aa000000-0000-0000-0000-000000000001', 'b0000000-0000-0000-0000-000000000001', 'WhatsApp', '#22C55E'),
  ('aa000000-0000-0000-0000-000000000002', 'b0000000-0000-0000-0000-000000000001', 'Facebook', '#3B82F6'),
  ('aa000000-0000-0000-0000-000000000003', 'b0000000-0000-0000-0000-000000000001', 'Google Ads', '#F59E0B');

-- =========================================================
-- 9) LEADS (4 leads em estágios diferentes)
-- =========================================================
INSERT INTO leads (id, organization_id, stage_id, owner_member_id, title, email, phone, ai_interest_level, ai_next_action_short, created_at) VALUES
  -- João Silva → Qualificação IA, alto interesse
  ('bb000000-0000-0000-0000-000000000001', 'b0000000-0000-0000-0000-000000000001', 'f0000000-0000-0000-0000-000000000002', 'd0000000-0000-0000-0000-000000000001',
   'João Silva', 'joao.silva@email.com', '+5511999001001', 'high', 'Agendar demonstração do produto',
   now() - interval '5 days'),

  -- Maria Oliveira → Lead Capturado, médio interesse
  ('bb000000-0000-0000-0000-000000000002', 'b0000000-0000-0000-0000-000000000001', 'f0000000-0000-0000-0000-000000000001', 'd0000000-0000-0000-0000-000000000001',
   'Maria Oliveira', 'maria.oliveira@email.com', '+5511999002002', 'medium', 'Enviar material informativo',
   now() - interval '3 days'),

  -- Carlos Mendes → Agendamento Demo, alto interesse
  ('bb000000-0000-0000-0000-000000000003', 'b0000000-0000-0000-0000-000000000001', 'f0000000-0000-0000-0000-000000000003', 'd0000000-0000-0000-0000-000000000001',
   'Carlos Mendes', 'carlos.mendes@empresa.com', '+5511999003003', 'high', 'Confirmar horário da demo',
   now() - interval '7 days'),

  -- Fernanda Lima → Negociação, baixo interesse
  ('bb000000-0000-0000-0000-000000000004', 'b0000000-0000-0000-0000-000000000001', 'f0000000-0000-0000-0000-000000000004', 'd0000000-0000-0000-0000-000000000001',
   'Fernanda Lima', 'fernanda.lima@corp.com', '+5511999004004', 'low', 'Follow-up sobre proposta',
   now() - interval '10 days');

-- =========================================================
-- 10) LEAD TAGS
-- =========================================================
INSERT INTO lead_tags (organization_id, lead_id, tag_id) VALUES
  -- João → WhatsApp
  ('b0000000-0000-0000-0000-000000000001', 'bb000000-0000-0000-0000-000000000001', 'aa000000-0000-0000-0000-000000000001'),
  -- Maria → Facebook
  ('b0000000-0000-0000-0000-000000000001', 'bb000000-0000-0000-0000-000000000002', 'aa000000-0000-0000-0000-000000000002'),
  -- Carlos → Google Ads
  ('b0000000-0000-0000-0000-000000000001', 'bb000000-0000-0000-0000-000000000003', 'aa000000-0000-0000-0000-000000000003'),
  -- Fernanda → WhatsApp
  ('b0000000-0000-0000-0000-000000000001', 'bb000000-0000-0000-0000-000000000004', 'aa000000-0000-0000-0000-000000000001');

-- =========================================================
-- 11) LEAD ACTIVITIES — João Silva (conversa completa com IA)
-- =========================================================

-- Dia 1: Lead chega via WhatsApp
INSERT INTO lead_activities (id, organization_id, lead_id, actor_member_id, type, content, metadata, created_at) VALUES
  -- Mensagem inbound do lead
  ('cc000000-0000-0000-0000-000000000001', 'b0000000-0000-0000-0000-000000000001', 'bb000000-0000-0000-0000-000000000001', 'd0000000-0000-0000-0000-000000000001',
   'whatsapp', 'Olá! Vi o anúncio de vocês no Instagram. Queria saber mais sobre o produto.',
   '{"direction": "inbound", "sender_name": "João Silva"}'::jsonb,
   now() - interval '5 days' + interval '9 hours'),

  -- Resposta automática do Agente IA
  ('cc000000-0000-0000-0000-000000000002', 'b0000000-0000-0000-0000-000000000001', 'bb000000-0000-0000-0000-000000000001', 'd0000000-0000-0000-0000-000000000001',
   'system', 'Olá João! 👋 Que bom que você se interessou! Nosso produto Atlas Eye é uma plataforma de CRM com inteligência artificial que automatiza o acompanhamento dos seus leads. Posso te contar mais sobre as funcionalidades?',
   '{"source": "ai", "model": "atlas-agent-v1"}'::jsonb,
   now() - interval '5 days' + interval '9 hours' + interval '15 seconds'),

  -- Lead responde
  ('cc000000-0000-0000-0000-000000000003', 'b0000000-0000-0000-0000-000000000001', 'bb000000-0000-0000-0000-000000000001', 'd0000000-0000-0000-0000-000000000001',
   'whatsapp', 'Sim! Principalmente a parte de automação. Vocês integram com WhatsApp Business?',
   '{"direction": "inbound", "sender_name": "João Silva"}'::jsonb,
   now() - interval '5 days' + interval '9 hours' + interval '3 minutes'),

  -- IA responde
  ('cc000000-0000-0000-0000-000000000004', 'b0000000-0000-0000-0000-000000000001', 'bb000000-0000-0000-0000-000000000001', 'd0000000-0000-0000-0000-000000000001',
   'system', 'Sim, temos integração nativa com WhatsApp Business API! Você consegue receber e responder mensagens diretamente pela plataforma, com respostas automáticas configuráveis. Quer que eu agende uma demonstração para você ver ao vivo?',
   '{"source": "ai", "model": "atlas-agent-v1"}'::jsonb,
   now() - interval '5 days' + interval '9 hours' + interval '3 minutes' + interval '20 seconds'),

  -- Lead confirma interesse
  ('cc000000-0000-0000-0000-000000000005', 'b0000000-0000-0000-0000-000000000001', 'bb000000-0000-0000-0000-000000000001', 'd0000000-0000-0000-0000-000000000001',
   'whatsapp', 'Seria ótimo! Pode ser na quinta-feira à tarde?',
   '{"direction": "inbound", "sender_name": "João Silva"}'::jsonb,
   now() - interval '5 days' + interval '9 hours' + interval '8 minutes'),

  -- Usuário humano intervém
  ('cc000000-0000-0000-0000-000000000006', 'b0000000-0000-0000-0000-000000000001', 'bb000000-0000-0000-0000-000000000001', 'd0000000-0000-0000-0000-000000000001',
   'whatsapp', 'Oi João! Aqui é o Venancio da equipe comercial. Vi que você tem interesse na demo. Quinta às 15h funciona pra você? Vou te enviar o link da reunião.',
   '{"direction": "outbound"}'::jsonb,
   now() - interval '4 days' + interval '10 hours');

-- =========================================================
-- 12) LEAD ACTIVITIES — Maria Oliveira (conversa inicial)
-- =========================================================
INSERT INTO lead_activities (id, organization_id, lead_id, actor_member_id, type, content, metadata, created_at) VALUES
  -- Mensagem inbound
  ('cc000000-0000-0000-0000-000000000007', 'b0000000-0000-0000-0000-000000000001', 'bb000000-0000-0000-0000-000000000002', 'd0000000-0000-0000-0000-000000000001',
   'whatsapp', 'Boa tarde! Recebi uma indicação sobre o sistema de vocês. Como funciona?',
   '{"direction": "inbound", "sender_name": "Maria Oliveira"}'::jsonb,
   now() - interval '3 days' + interval '14 hours'),

  -- IA responde
  ('cc000000-0000-0000-0000-000000000008', 'b0000000-0000-0000-0000-000000000001', 'bb000000-0000-0000-0000-000000000002', 'd0000000-0000-0000-0000-000000000001',
   'system', 'Boa tarde Maria! Obrigado pelo interesse! O Atlas Eye é um CRM inteligente que usa IA para qualificar leads automaticamente, priorizar oportunidades e sugerir próximos passos. Qual é o tamanho da sua equipe comercial?',
   '{"source": "ai", "model": "atlas-agent-v1"}'::jsonb,
   now() - interval '3 days' + interval '14 hours' + interval '10 seconds');

-- =========================================================
-- 13) LEAD ACTIVITIES — Carlos Mendes (nota + ligação)
-- =========================================================
INSERT INTO lead_activities (id, organization_id, lead_id, actor_member_id, type, content, metadata, created_at) VALUES
  ('cc000000-0000-0000-0000-000000000009', 'b0000000-0000-0000-0000-000000000001', 'bb000000-0000-0000-0000-000000000003', 'd0000000-0000-0000-0000-000000000001',
   'whatsapp', 'Olá, gostaria de agendar uma demonstração do produto.',
   '{"direction": "inbound", "sender_name": "Carlos Mendes"}'::jsonb,
   now() - interval '7 days' + interval '11 hours'),

  ('cc000000-0000-0000-0000-000000000010', 'b0000000-0000-0000-0000-000000000001', 'bb000000-0000-0000-0000-000000000003', 'd0000000-0000-0000-0000-000000000001',
   'system', 'Olá Carlos! Claro, ficaremos felizes em fazer uma demo. Qual horário seria melhor para você esta semana?',
   '{"source": "ai", "model": "atlas-agent-v1"}'::jsonb,
   now() - interval '7 days' + interval '11 hours' + interval '12 seconds'),

  ('cc000000-0000-0000-0000-000000000011', 'b0000000-0000-0000-0000-000000000001', 'bb000000-0000-0000-0000-000000000003', 'd0000000-0000-0000-0000-000000000001',
   'note', 'Lead veio via Google Ads, campanha "CRM 2025". Empresa de médio porte, ~30 vendedores. Alta prioridade.',
   '{}'::jsonb,
   now() - interval '6 days' + interval '9 hours'),

  ('cc000000-0000-0000-0000-000000000012', 'b0000000-0000-0000-0000-000000000001', 'bb000000-0000-0000-0000-000000000003', 'd0000000-0000-0000-0000-000000000001',
   'call', 'Ligação de 12 minutos. Carlos confirmou interesse, demo agendada para sexta às 10h.',
   '{"duration_seconds": 720}'::jsonb,
   now() - interval '5 days' + interval '15 hours');

-- =========================================================
-- 14) LEAD STAGE HISTORY
-- =========================================================
INSERT INTO lead_stage_history (id, organization_id, lead_id, from_stage_id, to_stage_id, changed_by_member_id, changed_at) VALUES
  -- João: Capturado → Qualificação IA
  ('dd000000-0000-0000-0000-000000000001', 'b0000000-0000-0000-0000-000000000001', 'bb000000-0000-0000-0000-000000000001',
   NULL, 'f0000000-0000-0000-0000-000000000001', 'd0000000-0000-0000-0000-000000000001',
   now() - interval '5 days' + interval '9 hours'),
  ('dd000000-0000-0000-0000-000000000002', 'b0000000-0000-0000-0000-000000000001', 'bb000000-0000-0000-0000-000000000001',
   'f0000000-0000-0000-0000-000000000001', 'f0000000-0000-0000-0000-000000000002', 'd0000000-0000-0000-0000-000000000001',
   now() - interval '4 days' + interval '10 hours'),

  -- Maria: Capturado (criação)
  ('dd000000-0000-0000-0000-000000000003', 'b0000000-0000-0000-0000-000000000001', 'bb000000-0000-0000-0000-000000000002',
   NULL, 'f0000000-0000-0000-0000-000000000001', 'd0000000-0000-0000-0000-000000000001',
   now() - interval '3 days' + interval '14 hours'),

  -- Carlos: Capturado → Qualificação → Agendamento Demo
  ('dd000000-0000-0000-0000-000000000004', 'b0000000-0000-0000-0000-000000000001', 'bb000000-0000-0000-0000-000000000003',
   NULL, 'f0000000-0000-0000-0000-000000000001', 'd0000000-0000-0000-0000-000000000001',
   now() - interval '7 days' + interval '11 hours'),
  ('dd000000-0000-0000-0000-000000000005', 'b0000000-0000-0000-0000-000000000001', 'bb000000-0000-0000-0000-000000000003',
   'f0000000-0000-0000-0000-000000000001', 'f0000000-0000-0000-0000-000000000002', 'd0000000-0000-0000-0000-000000000001',
   now() - interval '6 days' + interval '9 hours'),
  ('dd000000-0000-0000-0000-000000000006', 'b0000000-0000-0000-0000-000000000001', 'bb000000-0000-0000-0000-000000000003',
   'f0000000-0000-0000-0000-000000000002', 'f0000000-0000-0000-0000-000000000003', 'd0000000-0000-0000-0000-000000000001',
   now() - interval '5 days' + interval '15 hours'),

  -- Fernanda: Capturado → Qualificação → Agendamento → Negociação
  ('dd000000-0000-0000-0000-000000000007', 'b0000000-0000-0000-0000-000000000001', 'bb000000-0000-0000-0000-000000000004',
   NULL, 'f0000000-0000-0000-0000-000000000001', 'd0000000-0000-0000-0000-000000000001',
   now() - interval '10 days'),
  ('dd000000-0000-0000-0000-000000000008', 'b0000000-0000-0000-0000-000000000001', 'bb000000-0000-0000-0000-000000000004',
   'f0000000-0000-0000-0000-000000000001', 'f0000000-0000-0000-0000-000000000002', 'd0000000-0000-0000-0000-000000000001',
   now() - interval '8 days'),
  ('dd000000-0000-0000-0000-000000000009', 'b0000000-0000-0000-0000-000000000001', 'bb000000-0000-0000-0000-000000000004',
   'f0000000-0000-0000-0000-000000000002', 'f0000000-0000-0000-0000-000000000003', 'd0000000-0000-0000-0000-000000000001',
   now() - interval '6 days'),
  ('dd000000-0000-0000-0000-000000000010', 'b0000000-0000-0000-0000-000000000001', 'bb000000-0000-0000-0000-000000000004',
   'f0000000-0000-0000-0000-000000000003', 'f0000000-0000-0000-0000-000000000004', 'd0000000-0000-0000-0000-000000000001',
   now() - interval '4 days');

-- =========================================================
-- 15) UPDATE LEADS — last_activity denormalization
-- =========================================================
UPDATE leads SET
  last_activity_at = now() - interval '4 days' + interval '10 hours',
  last_activity_type = 'whatsapp',
  last_activity_by_member_id = 'd0000000-0000-0000-0000-000000000001'
WHERE id = 'bb000000-0000-0000-0000-000000000001';

UPDATE leads SET
  last_activity_at = now() - interval '3 days' + interval '14 hours' + interval '10 seconds',
  last_activity_type = 'system',
  last_activity_by_member_id = 'd0000000-0000-0000-0000-000000000001'
WHERE id = 'bb000000-0000-0000-0000-000000000002';

UPDATE leads SET
  last_activity_at = now() - interval '5 days' + interval '15 hours',
  last_activity_type = 'call',
  last_activity_by_member_id = 'd0000000-0000-0000-0000-000000000001'
WHERE id = 'bb000000-0000-0000-0000-000000000003';

UPDATE leads SET
  last_activity_at = now() - interval '4 days',
  last_activity_type = 'whatsapp',
  last_activity_by_member_id = 'd0000000-0000-0000-0000-000000000001'
WHERE id = 'bb000000-0000-0000-0000-000000000004';

-- =========================================================
-- DONE! 🎉
-- Dados inseridos:
--   1 tier, 1 org, 1 profile, 1 role, 1 member
--   1 pipeline com 4 estágios
--   3 tags (WhatsApp, Facebook, Google Ads)
--   4 leads com tags, atividades e histórico de estágios
--   12 atividades (whatsapp, system/AI, note, call)
--   10 registros de histórico de movimentação
-- =========================================================
