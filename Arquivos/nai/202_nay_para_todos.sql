-- 202 (Pedro, 30/09/2026): "minha ideia é que todos da aba Todos estejam com a Nay
-- ativada para responder ... por enquanto vou deixar ela errar para ir corrigindo,
-- então liga ela para todos os contatos".
-- A porta de 28/09 (regra_publico) deixava com o Tel toda conversa que existia antes
-- dela e não tinha sido "liberada". Aqui todo contato é liberado. Continuam valendo:
-- visita confirmada, fechamento, proprietário e escolha à mão (197/201: a Rayssa), o
-- Tel com a conversa (escalação, revisão 30/09, "mandou para o Tel" no CRM: aba Tel)
-- e o Tel escrevendo pelo celular (30 min). Backup das marcas em /root/backups-funcoes.
BEGIN;
UPDATE nai_contato SET liberado_em = now(), liberado_motivo = 'Pedro 30/09: a Nay para todos'
 WHERE liberado_em IS NULL;
COMMIT;
