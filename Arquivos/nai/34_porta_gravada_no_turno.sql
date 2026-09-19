-- =====================================================================
-- NAI -- 34: a decisão da porta fica GRAVADA no turno (Tel, 15/09/2026)
--
-- O painel nao abria: `/api/nai/fila` devolvia 500 com "permission denied for
-- table nai_contato", e o botao de pausa ficava com o texto "..." porque o JS
-- morria antes de escreve-lo. Foi assim que ele nao achou o botao.
--
-- A CAUSA, e ela era pior que o erro: `vw_nai_porta` chamava `nai_deve_atender`
-- para cada linha -- e essa funcao ESCREVE. Ela e quem libera uma conversa
-- antiga quando a pessoa pede foto ou pede imoveis. Com o GRANT que faltava,
-- ABRIR O PAINEL teria LIBERADO conversas sozinho, sem ninguem ter pedido nada.
-- Dar a permissao teria "consertado" a tela e criado um estrago silencioso.
--
-- O certo e nao recalcular: a decisao e tomada uma vez, quando a mensagem
-- chega, e fica gravada no turno. O painel LE o que aconteceu de verdade, em
-- vez de simular de novo o que teria acontecido.
-- =====================================================================

ALTER TABLE nai_turno ADD COLUMN IF NOT EXISTS porta text;
COMMENT ON COLUMN nai_turno.porta IS
  'O que a porta decidiu para esta mensagem, no momento em que ela chegou (Tel, 15/09).';

-- A view perde a coluna `telefone` (o painel nao precisa do numero de ninguem)
-- e ganha `porta`; trocar colunas exige recriar, CREATE OR REPLACE nao aceita.
-- E view, nao dado: recriar nao perde nada.
DROP VIEW IF EXISTS vw_nai_porta;

-- A view passa a LER a coluna. Nenhuma funcao e chamada aqui: a tela nao muda
-- nada no banco, so mostra.
CREATE OR REPLACE VIEW vw_nai_porta AS
SELECT
  t.id,
  t.criado_em                                   AS quando,
  coalesce(k.nome_completo, k.nome_whatsapp,
           nai_fone_fmt(k.telefone))            AS quem,
  left(t.texto, 120)                            AS ele_disse,
  t.porta,
  k.liberado_em IS NOT NULL                     AS ja_liberada,
  k.humano_assumiu_em IS NOT NULL               AS com_o_tel
FROM nai_turno t
JOIN nai_contato k ON k.id = t.contato_id
WHERE t.papel = 'corretor'
  AND t.criado_em > now() - interval '48 hours'
ORDER BY t.id DESC;

COMMENT ON VIEW vw_nai_porta IS
  'Quem escreveu nas ultimas 48h e o que a porta decidiu -- lido do turno, nao recalculado.';

-- A role do painel le as colunas que a view precisa, e SO essas. Nada de
-- UPDATE: o painel nao libera nem pausa conversa nenhuma por engano.
GRANT SELECT (id, chave, telefone, nome_completo, nome_whatsapp,
              liberado_em, humano_assumiu_em) ON nai_contato TO nay_site_nai;
GRANT SELECT (id, contato_id, papel, texto, codigo, criado_em, porta) ON nai_turno TO nay_site_nai;
GRANT SELECT ON vw_nai_porta TO nay_site_nai;
