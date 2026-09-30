-- O grupo IMÓVEIS ALTO PADRÃO PARA ANUNCIAR EASY.
--
-- O PEDIDO (Tel, 25/09): "esse grupo foi criado só para enviar imóvel alto
-- padrão para alguns corretores, eles anunciam esses imóveis que vamos colocar
-- lá. quando o comando for: Nay envia para o grupo alto padrão 4567, ela só
-- vai enviar este imóvel que pedir".
--
-- POR QUE UM APELIDO, e não casar pelo nome: o comando do Easy seleciona
-- `todas_fotos = true`, e agora são DOIS grupos com essa marca. Casar pelo
-- nome seria comparar "IMÓVEIS PARA ANUNCIAR EASY" com "IMÓVEIS ALTO PADRÃO
-- PARA ANUNCIAR EASY" -- um é prefixo do outro, com emoji e acento no meio, e
-- é o tipo de casamento que este projeto já errou várias vezes. O apelido é
-- uma chave curta que o código nomeia direto.
--
-- CONFERIDO na Z-API antes de cadastrar, como manda o CLAUDE.md:
--   id 120363431003549527-group, 11 participantes,
--   adminOnlyMessage = true E a Nay (559294453618) é SUPER-ADMIN --
--   sem isso todo disparo falharia para ele sem aviso nenhum.

ALTER TABLE grupos ADD COLUMN IF NOT EXISTS apelido text;
CREATE UNIQUE INDEX IF NOT EXISTS grupos_apelido_unico
    ON grupos (apelido) WHERE apelido IS NOT NULL;

-- O Easy de sempre ganha o apelido que o código já usa por dentro.
UPDATE grupos SET apelido = 'easy'
 WHERE id_grupo = '120363296035090852-group' AND apelido IS DISTINCT FROM 'easy';

-- O novo. Os pisos são OS MESMOS do "🟢 Alto Padrão - OFERTA e BUSCA 🔍":
-- 6.500 de aluguel e 1.000.000 de venda. Reusar em vez de escolher outro
-- número evita duas definições de "alto padrão" divergindo com o tempo --
-- aqui eles não filtram o disparo (o Tel manda o código que quiser), servem
-- para a PERGUNTA de confirmação quando o imóvel está abaixo da faixa.
INSERT INTO grupos (id_grupo, nome, ativo, todas_fotos, aceita_venda,
                    aceita_locacao, aluguel_minimo, venda_minima,
                    so_condominio, so_comercial, limite_dia, apelido)
VALUES ('120363431003549527-group', 'IMÓVEIS ALTO PADRÃO PARA ANUNCIAR EASY',
        true, true, true, true, 6500, 1000000, false, false, 5, 'alto_padrao')
ON CONFLICT (id_grupo) DO UPDATE
   SET nome = EXCLUDED.nome, ativo = true, todas_fotos = true,
       aluguel_minimo = EXCLUDED.aluguel_minimo,
       venda_minima = EXCLUDED.venda_minima,
       apelido = 'alto_padrao';

-- A reserva atômica, igual à do Easy (`easy_publicacoes`). Tabela PRÓPRIA, e
-- não uma coluna a mais naquela: mexer no esquema que o `postar_easy` usa
-- arriscaria o comando que já está em produção, e o ganho seria nenhum.
--
-- A corrida que isto fecha é real, vista em 25/08 no Easy: checar e gravar
-- como passos separados deixava uma janela de minutos (o envio com todas as
-- fotos demora) em que dois pedidos do mesmo código passavam os dois.
CREATE TABLE IF NOT EXISTS alto_padrao_publicacoes (
  codigo       text PRIMARY KEY,
  publicado_em timestamptz NOT NULL DEFAULT now()
);
