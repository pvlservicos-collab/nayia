\set ON_ERROR_STOP on
SET statement_timeout = '20s';
BEGIN;
-- Teste da ficha da captação (164/165). Tudo numa transação desfeita no fim.
-- docker exec -i nay-postgres psql -U nay -d naydb -At < teste_165_ficha.sql
-- Usa o lead de teste 835 (proprietário fake 999001, imóvel 99001).
\set tel '5596991712835'
\echo '== A. DISPONIVEL: abre, responde, vazio usa a aberta, para, e NAO recomeça'
SELECT 'aviso antes   -> ' || coalesce(captacao_ficha_aviso(835), '(nenhum)');
SELECT '1 abre        -> ' || captacao_ficha(:'tel', 'este', '{"valor":"2800"}', false);
SELECT 'aviso         -> ' || coalesce(captacao_ficha_aviso(835), '(nenhum)');
SELECT '2 comodos     -> ' || captacao_ficha(:'tel', 'este', '{"quartos":"2","suites":"1","banheiros":"2","vagas":"1"}');
SELECT '3 qual vazio  -> ' || captacao_ficha(:'tel', '', '{"area":"uns 70 metros"}');
SELECT '4 parar       -> ' || captacao_ficha(:'tel', '', '{"parar":"sim"}');
SELECT '5 de novo     -> ' || captacao_ficha(:'tel', 'este', '{"valor":"2800"}', false);
SELECT '6 acrescenta  -> ' || captacao_ficha(:'tel', 'este', '{"mobilia":"mobiliado"}');
SELECT 'aviso depois  -> ' || coalesce(captacao_ficha_aviso(835), '(nenhum)');
SELECT tipo, estado, dados FROM captacao_cadastro WHERE lead_id = 835 ORDER BY id;

\echo '== B. OUTRO NO MEIO: abre a do imovel da campanha, ele fala de outro, a nova termina e volta'
DELETE FROM captacao_cadastro WHERE lead_id = 835;
SELECT '1 abre este   -> ' || captacao_ficha(:'tel', 'este', '{"valor":"2800"}', false);
SELECT '2 abre outro  -> ' || captacao_ficha(:'tel', 'outro', '{"detalhes":"uma casa no Taruma para vender","negocio":"venda","tipo":"casa","bairro":"Taruma"}', false);
SELECT 'aviso         -> ' || coalesce(captacao_ficha_aviso(835), '(nenhum)');
SELECT '3 outro comod -> ' || captacao_ficha(:'tel', 'outro', '{"quartos":"3","banheiros":"2","vagas":"2"}');
SELECT '4 outro parar -> ' || captacao_ficha(:'tel', 'outro', '{"parar":"sim"}');
SELECT 'aviso         -> ' || coalesce(captacao_ficha_aviso(835), '(nenhum)');

\echo '== C. ALUGADO: guardar_ficha(este) recusa, e a ficha que a foto abriu nao vira aviso'
DELETE FROM captacao_cadastro WHERE lead_id = 835;
UPDATE captacao_leads SET situacao = 'alugado' WHERE id = 835;
INSERT INTO captacao_cadastro (lead_id, tipo, codigo, fotos) VALUES (835, 'atualizar', 99001, '["https://x/1.jpg"]');
SELECT 'ficha este    -> ' || captacao_ficha(:'tel', 'este', '{"quartos":"2"}');
SELECT 'aviso         -> ' || coalesce(captacao_ficha_aviso(835), '(nenhum)');
SELECT 'outro ainda   -> ' || captacao_ficha(:'tel', 'outro', '{"detalhes":"um apartamento no Adrianopolis","negocio":"locacao"}', false);
SELECT 'fora da lista -> ' || captacao_ficha('5592900000000', 'este', '{}', true);
ROLLBACK;
