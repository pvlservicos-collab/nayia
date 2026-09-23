-- =====================================================================
-- NAI -- 104: os imoveis do site antigo que faltavam (Tel, 23/09/2026)
--
-- Ele deixou duas planilhas do site antigo e pediu: "mantem o atual e todas
-- as atualizacoes do atual que o tel ja passou... e compara com os da
-- planilha do site antigo para ver se nao tem imovel do antigo que nao esta
-- no novo, se achar adiciona".
--
-- A CONTA (planilha "Imoveis (2).xlsx", 5.636 imoveis x 1.248 no sistema):
--   4.405 estao no antigo e nao no atual, e quase todos por bom motivo --
--   2.306 vendidos, 767 alugados, 743 removidos, 534 arquivados, 37
--   rascunhos e 16 em revisao.
--   Sobram DOIS marcados como "Disponivel" no antigo e que nao existem aqui.
--   Sao estes.
--
-- NADA DO ATUAL E TOCADO: nenhum imovel muda de situacao, preco ou
-- disponibilidade. O que o Tel ja atualizou continua como esta -- inclusive
-- os 310 que estavam "Disponivel" no antigo e que hoje estao fora do site,
-- que sao justamente as baixas que ele deu.
--
-- SEM FOTO: a planilha do site antigo nao traz foto. Os dois entram com
-- zero, e ai o card sai com "Ja te mando as fotos!" e o sistema avisa o Tel.
-- E o comportamento normal de imovel sem foto -- so precisa saber que vai
-- acontecer com estes dois ate alguem subir as imagens.
-- =====================================================================

\set ON_ERROR_STOP on

BEGIN;

INSERT INTO imoveis (codigo, tipo, condominio_nome, bairro, cidade, estado, logradouro,
                     quartos, banheiros, suites, vagas, area_util,
                     valor_venda, valor_aluguel, origem,
                     disponivel, bloqueado, publicado_no_site, e_parceiro,
                     travado, precisa_confirmacao, administrado)
VALUES
  (5551, 'Casa de condomínio', 'Bosque Residencial Portinari', 'Tarumã', 'Manaus', 'AM',
   'Av. do Turismo, 356', 2, 1, 0, 0, 52.0,
   NULL, 1800.00, 'site_antigo', true, false, true, false, false, false, false),
  (5723, 'Apartamento', 'Luar Ponta Negra', 'Tarumã', 'Manaus', 'AM',
   'Av. Perimetral Thales Loureiro, 1030', 3, 2, 1, 0, 60.0,
   300000.00, NULL, 'site_antigo', true, false, true, false, false, false, false)
ON CONFLICT (codigo) DO NOTHING;

COMMIT;

SELECT codigo, tipo, condominio_nome, bairro, quartos,
       coalesce(valor_venda::text, '-') AS venda,
       coalesce(valor_aluguel::text, '-') AS aluguel,
       (SELECT count(*) FROM imovel_fotos f WHERE f.codigo = i.codigo) AS fotos,
       nay_esta_no_mercado(disponivel, bloqueado, publicado_no_site) AS no_mercado
  FROM imoveis i WHERE origem = 'site_antigo' ORDER BY codigo;
