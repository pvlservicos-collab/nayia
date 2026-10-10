-- 341 -- A mobília do cadastro corrigida em 5 imóveis (é o cadastro que a busca da Nay lê)
--
-- Pedro, 10/10/2026: "o Maison Rochelle é mobiliado e aceita financiamento, o Tel tá até mandando para ele lá ...
-- dá aquela revisada nos parâmetros dos imóveis que podem estar mal preenchidos".
--
-- A busca da Nay nova compara a mobília do PEDIDO com `imoveis.mobilia` (via `core_imovel_busca`), e a comparação
-- é exata: quem pede "mobiliado" não vê "semi-mobiliado" nem o que está vazio. A varredura do site antigo não
-- mexe nessa coluna, então o que entrou errado (ou mudou no anúncio depois) fica errado para sempre.
--
-- Auditoria de 10/10 nos 292 imóveis que ela pode oferecer. Só o que não deixa dúvida entra aqui:
--   2944 Maison Rochelle       semi-mobiliado -> mobiliado   (palavra do Tel em 10/10; as observações do anúncio
--                                                             listam sofás, mesa, geladeira, fogão, camas)
--                              "aceita financiamento" Não -> Sim (o anúncio já diz Sim desde 10/10 à tarde)
--   4207 Residencial Efhraim   semi-mobiliado -> mobiliado   (o anúncio diz Mobiliado; locação de R$ 7.500)
--   5609 Reserva das Flores    (vazio)        -> mobiliado   (o anúncio diz Mobiliado)
--   462  Viva Verde            (vazio)        -> semi-mobiliado (o anúncio diz Semi-Mobiliado)
--   2411 Coral Gables          (vazio)        -> semi-mobiliado (o anúncio diz Semi-Mobiliado)
--
-- Cada UPDATE só vale se o valor ainda for o de antes (se alguém corrigiu à mão nesse meio tempo, não é tocado).
-- Desfazer: os valores de antes estão na tabela acima.
BEGIN;
SET LOCAL lock_timeout = '3s';

UPDATE imoveis
   SET mobilia = 'mobiliado',
       caracteristicas = array_replace(caracteristicas, 'Semi-Mobiliado', 'Mobiliado'),
       extras = coalesce(extras, '{}'::jsonb) || jsonb_build_object('aceita financiamento', 'Sim')
 WHERE codigo = 2944 AND mobilia = 'semi-mobiliado';

UPDATE imoveis SET mobilia = 'mobiliado' WHERE codigo = 4207 AND mobilia = 'semi-mobiliado';
UPDATE imoveis SET mobilia = 'mobiliado' WHERE codigo = 5609 AND coalesce(btrim(mobilia), '') = '';
UPDATE imoveis SET mobilia = 'semi-mobiliado' WHERE codigo IN (462, 2411) AND coalesce(btrim(mobilia), '') = '';

COMMIT;
