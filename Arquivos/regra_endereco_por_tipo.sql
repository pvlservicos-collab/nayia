-- A regra de endereço passa a depender do TIPO do imóvel.
--
-- A DECISÃO DO TEL (01/09), palavra por palavra: "apartamento pode falar
-- o andar e a torre, agora casa não pode falar o número dela e nem o
-- número do apartamento".
--
-- O QUE ISSO RESOLVE: a tabela tinha duas regras `endereco` ATIVAS e
-- contraditórias, e a Nay escolhia por conta.
--
--   regra 1: "pode passar o endereço do CONDOMINIO (rua e numero) e
--             tambem a torre, o andar e a face solar"
--   regra 4: "NAO passe logradouro, rua nem numero de NENHUM imovel"
--
-- Uma libera a rua, a outra proíbe. Nenhuma das duas falava de casa, que
-- é o caso em que o número É o identificador da unidade -- 397 dos 1.208
-- imóveis são Casa ou Casa de condomínio.
--
-- A REGRA ÚNICA, agora, é por tipo:
--   APARTAMENTO -> andar, torre e face solar PODEM. Número do apto, NUNCA.
--   CASA        -> rua e bairro PODEM. Número da casa, NUNCA.
--   OS DOIS      -> o número sai no dia da visita, pelo Fernando.
--
-- Depois de aplicar: `python3 sincronizar_regras.py --escrever` no
-- servidor, e o import do fluxo. O prompt é cópia gerada desta tabela.
--
--   docker cp regra_endereco_por_tipo.sql nay-postgres:/tmp/re.sql
--   docker exec nay-postgres psql -U nay -d naydb -f /tmp/re.sql

-- A regra 1 passa a cobrir os dois tipos, sem contradizer ninguém.
UPDATE regras SET texto =
  'APARTAMENTO: voce PODE passar o andar, a torre e a face solar quando '
  'ele perguntar, e o endereco do CONDOMINIO -- o predio e publico. '
  'NUNCA o numero do apartamento nem o complemento do cadastro. '
  'CASA: voce PODE passar a rua e o bairro. NUNCA o numero da casa: o '
  'numero e o que identifica a casa, do mesmo jeito que o numero do '
  'apartamento identifica a unidade. '
  'NOS DOIS CASOS o numero sai no dia da visita, pelo Fernando, e voce '
  'nao promete verificar nem dizer depois -- essa e a resposta.'
WHERE id = 1 AND contexto = 'endereco';

-- A regra 4 para de proibir a rua (que a 1 libera) e passa a proibir só
-- o que identifica a unidade.
UPDATE regras SET texto =
  'O que identifica a UNIDADE nunca sai: numero do apartamento, numero '
  'da casa, complemento do cadastro, endereco exato ou completo. '
  'Imovel marcado como administrado traz o endereco na resposta da '
  'ferramenta -- passe o que veio e nada alem: a ferramenta ja tira o '
  'numero antes de te entregar.'
WHERE id = 4 AND contexto = 'endereco';

SELECT id, contexto, left(texto, 120) AS agora FROM regras
 WHERE contexto = 'endereco' ORDER BY id;
