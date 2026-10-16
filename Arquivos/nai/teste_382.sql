-- teste da 382 (dentro da ensaio, termina em ROLLBACK: nada sai)
-- as recusas
SELECT 'lista vazia' AS caso, site_captacao_grupos_enviar_varios(1572, '{}', 'oi', true, false, 'ensaio')->>'erro' AS deu
UNION ALL SELECT 'onze imóveis', site_captacao_grupos_enviar_varios(1572, '{1,2,3,4,5,6,7,8,9,10,11}', 'oi', true, false, 'ensaio')->>'erro'
UNION ALL SELECT 'nem card nem foto', site_captacao_grupos_enviar_varios(1572, '{3605}', 'oi', false, false, 'ensaio')->>'erro'
UNION ALL SELECT 'só de parceiro', site_captacao_grupos_enviar_varios(1572, '{3037}', 'oi', true, false, 'ensaio')->>'erro'
UNION ALL SELECT 'código que não existe', site_captacao_grupos_enviar_varios(1572, '{99999}', 'oi', true, false, 'ensaio')->>'erro';

-- o envio de verdade (na ensaio): dois que casaram + um de parceiro + um repetido na lista, card e fotos
SELECT jsonb_pretty(site_captacao_grupos_enviar_varios(1572, '{3605,3841,3037,3605}', 'Oi, vi sua solicitação no grupo, separei estes:', true, true, 'ensaio')) AS envio;
SELECT s.ordem, s.tipo, s.motivo, s.codigo, s.estado, left(coalesce(s.texto, s.imagem_url), 60) AS o_que
  FROM nai_saida s WHERE s.turno_id = (SELECT max(id) FROM nai_turno) ORDER BY s.id;
SELECT pedido_id, codigo, com_card, left(resumo, 80) AS resumo FROM privado.grupo_pedido_oferta WHERE quem = 'ensaio';
SELECT DISTINCT estado FROM privado.grupo_pedido WHERE id IN (1570, 1571, 1572);

-- de novo, logo depois: o intervalo entre envios ao mesmo corretor segura
SELECT site_captacao_grupos_enviar_varios(1572, '{5757}', '', true, false, 'ensaio')->>'erro' AS segundo_envio;
