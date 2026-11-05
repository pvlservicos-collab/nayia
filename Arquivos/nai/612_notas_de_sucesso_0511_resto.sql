-- 612 (Pedro, 05/11/2026): as notas do resto das conversas de 05/11 (até ~10:54 de Manaus), das duas
-- Nays (Leads 8595 = captacao, Parceria 9445 = parceria). Lidas pelo CRM em crm_sucesso_das_conversas (610), só para Pedro e Tel.
BEGIN;
INSERT INTO privado.nay_nota_conversa (fone8, linha, dia, nota, resumo, erros) VALUES
  ('82694225', 'captacao', DATE '2026-11-05', 95, 'Saymon (agência de sites) ofereceu serviço; Nay perguntou se buscava imóvel e depois passou à equipe. Certo, só o ''Obrigado'' no masculino.', '["''Obrigado'' no masculino (leve)"]'::jsonb),
  ('84004575', 'parceria', DATE '2026-11-05', 50, 'Radar mandou o 331 (Residencial Tarumã) a pedido de Paradise 3q venda; Nonato corrigiu às 09:41 e a Nay ficou muda até a desculpa da equipe às 10:53.', '["card do radar com imóvel que não serve ao pedido (Paradise x Residencial Tarumã)", "ficou muda depois do ''É no Paradise'' (70 min, só a equipe respondeu)"]'::jsonb),
  ('92175868', 'parceria', DATE '2026-11-05', 15, 'Malu pediu visita hoje 15:30 no Tapajós (2462 e 9043). Nay repetiu a pergunta do horário 3x, não marcou as duas visitas e no fim pediu dia e hora de novo.', '["errou a visita: ''pode confirmar as 2 opções'' virou card do 9043; nenhuma visita registrada", "repetiu ''Qual horário da tarde...'' três vezes (áudio dizia que ela ia perguntar ao cliente)", "pediu dia e horário já informados (hoje 15:30)", "''Combinado, fico no aguardo'' quando ela disse que a cliente queria as opções", "''Sim, está disponível'' fora de contexto"]'::jsonb),
  ('91918383', 'parceria', DATE '2026-11-05', 75, 'Gilson cobrou o contrato da Iracynne (proporcional vencido); Nay respondeu ''fico no aguardo'' e só no ''urgente'' escalou com ''Bom dia, já te respondo''.', '["respondeu ''Combinado, fico no aguardo'' a uma cobrança de contrato (não entendeu)", "saudação ''Bom dia'' depois de já ter respondido (leve)"]'::jsonb),
  ('84454760', 'parceria', DATE '2026-11-05', 100, 'Erick disse que os códigos 3450 e 9018 não aparecem no sistema; Nay disse que já responde e escalou à equipe. Correto.', '[]'::jsonb),
  ('93259568', 'parceria', DATE '2026-11-05', 95, 'Radar: pedido casa 3q locação até 3.500; Nay mandou o 5709 (casa Aleixo 3q R$ 2.900). Serve. O texto do card saiu no meio das fotos.', '["card do imóvel saiu no meio das fotos, não antes (leve)"]'::jsonb),
  ('82595361', 'parceria', DATE '2026-11-05', 95, 'Follow-up; Steffanie citou o card do 5733 e perguntou se está disponível: Nay confirmou certo. Ao ''já tenho as fotos'' respondeu como se ela pedisse mais.', '["respondeu ao ''já tenho as fotos'' como se ela pedisse mais fotos (leve)"]'::jsonb),
  ('91116721', 'parceria', DATE '2026-11-05', 95, 'Follow-up ''Oi Corretora''; ela pediu casa 3-4q financiável em vários bairros e a Nay perguntou o valor, que faltava. Certo.', '["follow-up com nome estranho ''Oi Corretora'' (leve)"]'::jsonb),
  ('91787287', 'parceria', DATE '2026-11-05', 100, 'Follow-up; Nancy pediu casa até 2,8 mi mobiliada em condomínio e a Nay perguntou a região, que faltava. Certo.', '[]'::jsonb),
  ('81143449', 'parceria', DATE '2026-11-05', 100, 'Equipe cobrou horário da visita; Andreza disse ''já confirmo'' e a Nay respondeu ''Combinado, fico no aguardo''. Certo.', '[]'::jsonb),
  ('81013553', 'parceria', DATE '2026-11-05', 100, 'Follow-up à Elizabeth (interesse + o que procura); sem resposta. Correto.', '[]'::jsonb),
  ('81034148', 'parceria', DATE '2026-11-05', 100, 'Follow-up ao Junior; sem resposta. Correto.', '[]'::jsonb),
  ('81208037', 'parceria', DATE '2026-11-05', 100, 'Follow-up ao Cleobery; sem resposta. Correto.', '[]'::jsonb),
  ('81312985', 'parceria', DATE '2026-11-05', 100, 'Follow-up ao Ray; sem resposta. Correto.', '[]'::jsonb),
  ('82117845', 'parceria', DATE '2026-11-05', 100, 'Follow-up ao Leosan; sem resposta. Correto.', '[]'::jsonb),
  ('86034966', 'parceria', DATE '2026-11-05', 100, 'Follow-up ao Leonan; sem resposta. Correto.', '[]'::jsonb),
  ('86049936', 'parceria', DATE '2026-11-05', 100, 'Follow-up ao Daniel; sem resposta. Correto.', '[]'::jsonb),
  ('91298622', 'parceria', DATE '2026-11-05', 95, 'Follow-up ''Oi Kr''; sem resposta.', '["nome estranho no follow-up: ''Kr'' (leve)"]'::jsonb),
  ('91440744', 'parceria', DATE '2026-11-05', 100, 'Follow-up ao Marcelo; sem resposta. Correto.', '[]'::jsonb),
  ('91600305', 'parceria', DATE '2026-11-05', 100, 'Follow-up ao Everton; sem resposta. Correto.', '[]'::jsonb),
  ('91988585', 'parceria', DATE '2026-11-05', 95, 'Follow-up ''Oi vasconcelosizaias''; sem resposta.', '["nome estranho no follow-up: ''vasconcelosizaias'' (leve)"]'::jsonb),
  ('92487906', 'parceria', DATE '2026-11-05', 100, 'Follow-up à Patricia; sem resposta. Correto.', '[]'::jsonb),
  ('94106117', 'parceria', DATE '2026-11-05', 100, 'Follow-up à Silvana; sem resposta. Correto.', '[]'::jsonb),
  ('95373878', 'parceria', DATE '2026-11-05', 95, 'Follow-up ''Oi corretor''; sem resposta.', '["nome estranho no follow-up: ''Oi corretor'' (leve)"]'::jsonb)
ON CONFLICT (fone8, linha, dia) DO UPDATE SET nota = EXCLUDED.nota, resumo = EXCLUDED.resumo, erros = EXCLUDED.erros, revisado_em = now();
SELECT linha, count(*), round(avg(nota)) media FROM privado.nay_nota_conversa WHERE dia = DATE '2026-11-05' GROUP BY 1;
COMMIT;
