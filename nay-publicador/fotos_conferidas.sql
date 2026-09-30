-- QUANDO AS FOTOS DE CADA IMÓVEL FORAM CONFERIDAS NO SITE (Tel, 28/09)
--
-- O QUE ELE VIU: "Código: 964, na hora de disparar ainda está com as fotos
-- antigas". Conferido: o site tem 4 fotos (de 25/09) e a tabela guarda 5,
-- de uma carga bem mais velha. Quem lê a TABELA -- a resposta da Nay sobre
-- imagem -- manda as antigas.
--
-- POR QUE ENVELHECEU: `varrer_fotos` só olha imóvel com ZERO foto
-- (`NOT EXISTS (SELECT 1 FROM imovel_fotos ...)`). Uma vez que o imóvel tem
-- qualquer foto, ele nunca mais é visitado -- trocar as fotos no admin não
-- chega ao banco. É o MESMO padrão da mobília e dos lances de escada,
-- achados hoje: preenchedor que só preenche vazio, nunca atualiza.
--
-- ESTA COLUNA É O RODÍZIO. Reler os ~270 imóveis do mercado a cada hora seria
-- martelar o site (regra 5); com o carimbo, cada rodada pega os mais antigos
-- e o catálogo inteiro converge em algumas horas, sem pico.
--
-- NULO PRIMEIRO, de propósito: quem nunca foi conferido é quem mais
-- provavelmente está desatualizado.

ALTER TABLE imoveis ADD COLUMN IF NOT EXISTS fotos_conferidas_em timestamptz;

CREATE INDEX IF NOT EXISTS imoveis_fotos_conferidas_idx
    ON imoveis (fotos_conferidas_em NULLS FIRST)
 WHERE coalesce(publicado_no_site, false);

SELECT count(*) FILTER (WHERE fotos_conferidas_em IS NULL) AS nunca_conferidas,
       count(*) AS no_site
  FROM imoveis WHERE coalesce(publicado_no_site, false);
