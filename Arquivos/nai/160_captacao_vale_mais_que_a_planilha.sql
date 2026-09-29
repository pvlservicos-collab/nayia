-- =====================================================================
-- 160 — A RESPOSTA DO DONO NA CAPTAÇÃO VALE MAIS QUE A PLANILHA (28/09/2026)
--
-- Pedro: "a ordem de atualização caso tenha conflito é captação > site antigo
-- (a planilha completa) > novo"; e, vendo a lista: "aplica todos até a data a
-- não ser que o Tel tenha mudado em uma data posterior, filtra por data".
--
-- O FILTRO POR DATA, medido antes de escrever:
--   * nenhuma mensagem do Tel citando estes códigos depois da resposta do dono;
--   * nos 19 abaixo, o admin antigo dizia a MESMA situação em 07/09
--     (imoveis_admin_snapshot) e na planilha de 26/09 -- ou seja, ninguém mexeu
--     no site antigo depois da resposta do dono (09 a 17/09);
--   * o 293 FICA DE FORA: o dono disse alugado em 15/09 e em 16/09 ele foi
--     recadastrado à venda no site antigo (mudança posterior);
--   * o 2182 não existe no catálogo (nada a fazer).
--
-- O que muda:
--   14 que o dono disse VENDIDO e o site dizia Alugado  -> Vendido
--   505, 2215, 2266 (Arquivado), dono disse alugado     -> Alugado
--   1778 e 2133, dono disse DISPONÍVEL                   -> Disponível, no site e na Nay
-- Nenhum dispara aviso de saída (o gatilho só age quando `disponivel` cai).
--
-- A TRAVA: 1778 e 2133 não estão no .com, e a leitura diária do site antigo
-- despublica o que não acha lá. `travado` (coluna que existia sem uso) passa a
-- dizer "decidido à mão ou pela captação: o site antigo não publica nem tira do
-- ar" -- sincronizar_catalogo.py respeita desde hoje, e a rota de edição do
-- admin novo trava o que alguém muda à mão (por isso o GRANT abaixo).
--
-- Rodar com -v ensaio=1 para desfazer no fim.
-- =====================================================================
\set ON_ERROR_STOP on
BEGIN;
SET LOCAL lock_timeout = '3s';

GRANT UPDATE (travado, travado_motivo, travado_em) ON imoveis TO nay_site_escrita;

CREATE TEMP TABLE captacao_aplicar (codigo int, de text, para text, dono_em text) ON COMMIT DROP;
INSERT INTO captacao_aplicar VALUES
  (193, 'Alugado', 'Vendido', '09/09'), (1179, 'Alugado', 'Vendido', '09/09'), (1281, 'Alugado', 'Vendido', '15/09'),
  (1696, 'Alugado', 'Vendido', '09/09'), (1827, 'Alugado', 'Vendido', '11/09'), (1902, 'Alugado', 'Vendido', '09/09'),
  (2052, 'Alugado', 'Vendido', '11/09'), (2095, 'Alugado', 'Vendido', '11/09'), (2127, 'Alugado', 'Vendido', '11/09'),
  (2146, 'Alugado', 'Vendido', '14/09'), (2353, 'Alugado', 'Vendido', '12/09'), (2503, 'Alugado', 'Vendido', '17/09'),
  (2626, 'Alugado', 'Vendido', '15/09'), (3147, 'Alugado', 'Vendido', '15/09'),
  (505, 'Arquivado', 'Alugado', '14/09'), (2215, 'Arquivado', 'Alugado', '10/09'), (2266, 'Arquivado', 'Alugado', '11/09'),
  (1778, 'Alugado', 'Disponível', '14/09'), (2133, 'Alugado', 'Disponível', '12/09');

UPDATE imoveis i
   SET status = a.para,
       disponivel = (a.para = 'Disponível'),
       publicado_no_site = (a.para = 'Disponível' AND NOT coalesce(i.e_parceiro, false)),
       travado = CASE WHEN a.para = 'Disponível' THEN true ELSE i.travado END,
       travado_motivo = CASE WHEN a.para = 'Disponível' THEN 'captação: o dono disse disponível em ' || a.dono_em ELSE i.travado_motivo END,
       travado_em = CASE WHEN a.para = 'Disponível' THEN now() ELSE i.travado_em END
  FROM captacao_aplicar a
 WHERE a.codigo = i.codigo AND i.status = a.de;   -- só se ninguém mexeu desde a medição

\echo '== aplicado'
SELECT a.codigo, a.de, a.para, i.status AS agora, i.disponivel, i.publicado_no_site, i.travado
  FROM captacao_aplicar a JOIN imoveis i USING (codigo) ORDER BY a.para, a.codigo;
SELECT count(*) FILTER (WHERE i.status = a.para) AS aplicados, count(*) AS esperados FROM captacao_aplicar a JOIN imoveis i USING (codigo);
\echo '== fila de aviso (tem que continuar vazia para estes)'
SELECT count(*) AS avisos_novos FROM aviso_de_saida s JOIN captacao_aplicar a ON a.codigo::text = s.codigo WHERE s.avisado_em IS NULL;
\echo '== oferta da Nay (nossos)'
SELECT count(*) FROM imoveis WHERE nay_esta_no_mercado(disponivel, bloqueado, publicado_no_site) AND NOT coalesce(e_parceiro, false);

\if :{?ensaio}
  \echo '>>> ENSAIO: desfazendo tudo'
  ROLLBACK;
\else
  COMMIT;
\endif
