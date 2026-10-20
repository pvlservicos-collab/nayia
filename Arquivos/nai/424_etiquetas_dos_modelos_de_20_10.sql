-- 424: etiquetas dos 30 modelos mandados à Meta em 20/10 (cadastro_imobeasy_31-40, ainda_alugado_01-10, outro_imovel_01-10),
-- no mesmo padrão da 423 (aba WhatsApp › Mensagens, whats_modelo_nota). Só acrescenta.
BEGIN;
INSERT INTO whats_modelo_nota (nome, idioma, etiquetas, atualizado_por)
SELECT v.nome, 'pt_BR', v.etiquetas::text[], 'Claude (424, 20/10)' FROM (VALUES
  ('cadastro_imobeasy_31', ARRAY['corretor · cadastro parceiro','em revisão · enviado 20/10']),
  ('cadastro_imobeasy_32', ARRAY['corretor · cadastro parceiro','em revisão · enviado 20/10']),
  ('cadastro_imobeasy_33', ARRAY['corretor · cadastro parceiro','em revisão · enviado 20/10']),
  ('cadastro_imobeasy_34', ARRAY['corretor · cadastro parceiro','em revisão · enviado 20/10']),
  ('cadastro_imobeasy_35', ARRAY['corretor · cadastro parceiro','em revisão · enviado 20/10']),
  ('cadastro_imobeasy_36', ARRAY['corretor · cadastro parceiro','em revisão · enviado 20/10']),
  ('cadastro_imobeasy_37', ARRAY['corretor · cadastro parceiro','em revisão · enviado 20/10']),
  ('cadastro_imobeasy_38', ARRAY['corretor · cadastro parceiro','em revisão · enviado 20/10']),
  ('cadastro_imobeasy_39', ARRAY['corretor · cadastro parceiro','em revisão · enviado 20/10']),
  ('cadastro_imobeasy_40', ARRAY['corretor · cadastro parceiro','em revisão · enviado 20/10']),
  ('ainda_alugado_01', ARRAY['dono · ainda alugado?','em revisão · enviado 20/10']),
  ('ainda_alugado_02', ARRAY['dono · ainda alugado?','em revisão · enviado 20/10']),
  ('ainda_alugado_03', ARRAY['dono · ainda alugado?','em revisão · enviado 20/10']),
  ('ainda_alugado_04', ARRAY['dono · ainda alugado?','em revisão · enviado 20/10']),
  ('ainda_alugado_05', ARRAY['dono · ainda alugado?','em revisão · enviado 20/10']),
  ('ainda_alugado_06', ARRAY['dono · ainda alugado?','em revisão · enviado 20/10']),
  ('ainda_alugado_07', ARRAY['dono · ainda alugado?','em revisão · enviado 20/10']),
  ('ainda_alugado_08', ARRAY['dono · ainda alugado?','em revisão · enviado 20/10']),
  ('ainda_alugado_09', ARRAY['dono · ainda alugado?','em revisão · enviado 20/10']),
  ('ainda_alugado_10', ARRAY['dono · ainda alugado?','em revisão · enviado 20/10']),
  ('outro_imovel_01', ARRAY['dono · tem outro imóvel?','em revisão · enviado 20/10']),
  ('outro_imovel_02', ARRAY['dono · tem outro imóvel?','em revisão · enviado 20/10']),
  ('outro_imovel_03', ARRAY['dono · tem outro imóvel?','em revisão · enviado 20/10']),
  ('outro_imovel_04', ARRAY['dono · tem outro imóvel?','em revisão · enviado 20/10']),
  ('outro_imovel_05', ARRAY['dono · tem outro imóvel?','em revisão · enviado 20/10']),
  ('outro_imovel_06', ARRAY['dono · tem outro imóvel?','em revisão · enviado 20/10']),
  ('outro_imovel_07', ARRAY['dono · tem outro imóvel?','em revisão · enviado 20/10']),
  ('outro_imovel_08', ARRAY['dono · tem outro imóvel?','em revisão · enviado 20/10']),
  ('outro_imovel_09', ARRAY['dono · tem outro imóvel?','em revisão · enviado 20/10']),
  ('outro_imovel_10', ARRAY['dono · tem outro imóvel?','em revisão · enviado 20/10'])
) AS v(nome, etiquetas)
ON CONFLICT (nome, idioma) DO UPDATE SET
  etiquetas = (SELECT coalesce(array_agg(DISTINCT e ORDER BY e), '{}') FROM unnest(whats_modelo_nota.etiquetas || EXCLUDED.etiquetas) e),
  atualizado_por = EXCLUDED.atualizado_por, atualizado_em = now();
COMMIT;
