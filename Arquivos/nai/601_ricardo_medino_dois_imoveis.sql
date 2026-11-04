-- 601 (Pedro, 04/11/2026: "o Ricardo Medino mandou 2 imóveis parceiros novos, pede para a Nay cadastrar certinho e você
-- ajusta preenchendo as informações que os 2 imóveis dele não têm"). Às 08:20-08:22 ele mandou dois anúncios seguidos e a
-- Nay dos corretores juntou os dois no 9132 (nome e números de um, descrição do outro, as 32 fotos dos dois):
--   9132  Jardim Paradiso Girassol (Tarumã): 3 quartos, 53 m², 3º andar de escada, 1 vaga; fotos 17-32 (08:22, a legenda
--         do anúncio veio na última foto). Aluguel: o anúncio dizia "2 mil + caução" e ele escreveu às 08:36 "menor valor
--         2.300": fica R$ 2.300, com o anúncio anotado no uso interno.
--   novo  Conquista Torquato (Colônia Terra Nova, ao lado do Allegro): 2 quartos, 42 m², 4º andar, mobiliado, R$ 2.500 com
--         condomínio e água inclusos; fotos 1-16 (08:21).
BEGIN;

DO $$
DECLARE
  v_novo int;
BEGIN
  -- o Jardim Paradiso Girassol
  UPDATE imoveis SET
    tipo = 'Apartamento', bairro = 'Tarumã', condo_id = 10, condominio_nome = 'Jardim Paradiso Girassol',
    quartos = 3, suites = NULL, area_util = 53, andar = '3º andar (escada)', vagas = 1,
    valor_aluguel = 2300, valor_venda = NULL, taxa_condominio = 320, mobilia = 'mobiliado',
    observacao = 'Condomínio e IPTU já inclusos no aluguel. Caução. Não aceita pet.',
    descricao = '3 quartos, 1 banheiro e varanda; modulados na cozinha; 1 vaga de garagem. Condomínio fechado com portaria e '
             || 'vigilância 24 h, mercado autônomo e área de lazer. Av. Dona Otília, no Tarumã, ao lado do hipermercado, perto '
             || 'da Bemol da Torquato, do Coema e da UPA 24 h.'
  WHERE codigo = 9132;
  PERFORM privado.uso_interno_somar(9132, 'Anúncio repassado pelo Ricardo Medino (CRECI 6841), de Kennedy Farias (CRECI 5233): '
          || '"Valor 2 mil + caução", condomínio R$ 320 (a tabela de condomínios diz R$ 219 e vale para a taxa); às 08:36 de 04/11 o Ricardo escreveu "menor valor 2.300". O anúncio também diz "IPTU por '
          || 'conta do inquilino" e "IPTU já incluso": confirmar.');

  -- o Conquista Torquato
  INSERT INTO imoveis (codigo, origem, status, disponivel, publicado_no_site, criado_em, captado_em, e_parceiro, proprietario_id,
                       tipo, bairro, condo_id, condominio_nome, quartos, area_util, andar, valor_aluguel, mobilia,
                       observacao, descricao, extras)
  SELECT nextval('imoveis_crm_codigo_seq'), 'busca', 'Disponível', true, i.publicado_no_site, now(), to_char(now(), 'DD/MM/YYYY'),
         true, i.proprietario_id,
         'Apartamento', 'Colônia Terra Nova', 338, 'Conquista Torquato', 2, 42, '4º andar', 2500, 'mobiliado',
         'Condomínio e água inclusos no aluguel. Caução de R$ 2.500. Energia e IPTU por conta do inquilino.',
         '2 quartos e 1 banheiro; sala de estar e jantar; cozinha com modulados, cooktop de 4 bocas, forno, sugar e geladeira; '
         || '2 ar-condicionados; 2 TVs Smart; cama Queen e guarda-roupa de casal; mesa de jantar de vidro para 3 lugares, mesa de '
         || 'centro e sofá de 5 lugares. Na Av. Torquato Tapajós, ao lado do condomínio Allegro.',
         i.extras
    FROM imoveis i WHERE i.codigo = 9132
  RETURNING codigo INTO v_novo;

  -- as fotos de 08:21 (1-16) vão para o Conquista Torquato; as de 08:22 ficam no 9132, renumeradas
  UPDATE imovel_fotos SET codigo = v_novo, e_capa = (ordem = 1) WHERE codigo = 9132 AND ordem BETWEEN 1 AND 16;
  UPDATE imovel_fotos SET ordem = ordem - 16, e_capa = (ordem = 17) WHERE codigo = 9132 AND ordem BETWEEN 17 AND 32;
  PERFORM privado.uso_interno_somar(v_novo, 'Corretor parceiro: Ricardo Medino (CRECI 6841, 92 99139-8020), 04/11.');

  RAISE NOTICE 'Conquista Torquato = #%', v_novo;
END $$;

SELECT codigo, condominio_nome, condo_id, bairro, quartos, area_util, andar, valor_aluguel, taxa_condominio,
       (SELECT count(*) FROM imovel_fotos f WHERE f.codigo = i.codigo) AS fotos,
       (SELECT count(*) FROM imovel_fotos f WHERE f.codigo = i.codigo AND f.e_capa) AS capas
  FROM imoveis i WHERE codigo = 9132 OR (origem = 'busca' AND condo_id = 338 AND criado_em > now() - interval '1 hour')
 ORDER BY codigo;
COMMIT;
