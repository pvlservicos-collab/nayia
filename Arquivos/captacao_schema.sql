-- Onde a captação mora ENQUANTO ela ainda não está no site.
--
-- O CASO REAL: o Tel captou o imóvel com o proprietário, o proprietário já
-- anunciou na OLX, e o Tel quer colar o link numa tela e ver o imóvel
-- cadastrado no imobeasy.com sem redigitar nada -- "e o que estiver faltando
-- de informação eu vou preenchendo na plataforma". Entre o link colado e o
-- imóvel no site existe um rascunho de horas ou dias, com fotos baixadas e
-- perguntas ainda sem resposta. É esse rascunho que mora aqui.
--
-- POR QUE TABELA PRÓPRIA, E NÃO `imoveis`: a plataforma NÃO escreve em
-- `imoveis`. Ela cadastra no site; a varredura horária
-- (`sincronizar_catalogo.py`, aos :17) traz o imóvel do site para o banco
-- sozinha. Rascunho dentro de `imoveis` seria imóvel meio pronto aparecendo
-- na busca da Nay, e a regra 1 do projeto (nunca apagar linha de `imoveis`)
-- deixaria o meio-pronto lá para sempre.
--
-- E POR ISSO NÃO EXISTE CHAVE ESTRANGEIRA DE `codigo_no_site` PARA `imoveis`:
-- entre cadastrar no site e a varredura rodar passa até uma hora. FK aqui
-- recusaria a gravação exatamente no momento em que ela é mais importante --
-- o momento em que deu certo.
--
-- O QUE FOI MEDIDO EM `imoveis` ANTES DE ESCOLHER AS COLUNAS (02/09/2026,
-- 1.211 linhas, das quais 1.172 a varredura de fato leu -- as outras 39 estão
-- sem `tipo` e sem `status`). Percentual de não-nulos entre essas 1.172:
--
--     logradouro 100,0 | venda ou aluguel 100,0 | cidade/estado  99,7
--     bairro      98,4 | condomínio        97,4 | pelo menos 1 foto 96,9
--     área útil   92,2 | quartos           90,6 | banheiros      73,4
--     suítes      73,4 | vagas             61,3 | sol            59,8
--     descrição   55,2 | andar             36,5 | área total     29,3
--
-- É essa medição, e não opinião, que define o que `nay_captacao_pendencias`
-- cobra. Descrição em 55% é o exemplo que mais surpreende: mais da metade do
-- catálogo NÃO tem descrição, então exigir descrição travaria a plataforma
-- por um campo que a prática não exige.
--
-- OS NOMES SÃO OS DE `imoveis`, DE PROPÓSITO: as chaves de `campos` se
-- chamam `tipo`, `bairro`, `logradouro`, `valor_venda`, `area_util`,
-- `quartos`... exatamente como as colunas de `imoveis`. Assim o passo de
-- cadastrar no site não precisa de tabela de tradução, e
-- `nay_captacao_campos_desconhecidos` acusa o dia em que alguém escrever
-- `quarto` no lugar de `quartos`.
--
--   docker cp captacao_schema.sql nay-postgres:/tmp/cs.sql
--   docker exec nay-postgres psql -U nay -d naydb -f /tmp/cs.sql
--
-- RODAR DE NOVO É SEGURO, MAS NÃO ALTERA TABELA QUE JÁ EXISTE: as funções são
-- `CREATE OR REPLACE` e voltam corrigidas, mas `CREATE TABLE IF NOT EXISTS`
-- não acrescenta CHECK nenhum a uma tabela já instalada. Quem instalar uma
-- versão anterior e depois esta precisa aplicar os CHECK à mão
-- (`ALTER TABLE ... ADD CONSTRAINT`), senão o arquivo diz uma coisa e o banco
-- faz outra -- a divergência calada que este projeto já pagou caro.
-- Conferido em 02/09: rodar o arquivo duas vezes seguidas não dá erro.

-- --------------------------------------------------------------------
-- A CHAVE DO ANÚNCIO, tirada do próprio link.
--
-- POR QUE NÃO BASTA COMPARAR O TEXTO DO LINK: o mesmo anúncio chega escrito
-- de muitas formas. `www.olx.com.br/...` e `am.olx.com.br/...` são o mesmo
-- anúncio (o extrator troca um pelo outro porque o `www` devolve 308 para a
-- home). Link compartilhado pelo WhatsApp vem com `?utm_source=...` colado
-- no fim. E o pior: quando o proprietário edita o título, a OLX muda o SLUG
-- e mantém o id -- o mesmo anúncio passa a ter dois endereços diferentes.
-- Só o número final é estável.
--
-- POR QUE ISSO É UMA FUNÇÃO DE LINK E NÃO DE `dados_olx`: o servidor está
-- BLOQUEADO pela OLX (403 Cloudflare, medido em 02/09). Decidir "essa eu já
-- tenho" não pode depender de buscar a página -- tem que sair do texto que o
-- Tel colou, antes de qualquer requisição.
--
-- IMMUTABLE porque é ela que indexa: `captacao_um_por_anuncio` é um índice
-- único sobre esta expressão. Por isso ela também não usa `unaccent`, que é
-- apenas STABLE -- e slug de OLX não tem acento mesmo.
CREATE OR REPLACE FUNCTION nay_chave_do_link(p_link text)
RETURNS text
LANGUAGE sql IMMUTABLE AS $fn$
  WITH sem_cauda AS (
    -- Fora tudo depois de '?' ou '#' (utm_source, gclid, xtmc): muda a cada
    -- compartilhamento e é o mesmo anúncio. E fora a barra final.
    SELECT regexp_replace(
             split_part(split_part(btrim(coalesce(p_link, '')), '#', 1), '?', 1),
             '/+$', '') AS t
  ), normal AS (
    -- `lower` ANTES de tirar o protocolo, e não depois: `^https?://` é
    -- sensível a caixa, e o teclado do celular manda a primeira letra da
    -- mensagem em maiúscula -- "Https://am.olx.com.br/...". Com a ordem
    -- invertida o protocolo não era removido e o MESMO endereço gerava duas
    -- chaves (medido em 02/09). Só mordia o caminho `url:`, o de link sem id;
    -- quando há id, o número do fim salva a comparação.
    SELECT regexp_replace(lower(t), '^https?://(www\.)?', '') AS t FROM sem_cauda
  )
  SELECT CASE
           WHEN t = '' THEN NULL
           -- O id do anúncio é o último grupo de 8 ou mais dígitos do
           -- caminho (ex.: .../casa-no-parque-das-laranjeiras-1526572128).
           -- Oito é o piso: CEP tem 8 e nunca fica no fim do slug, e
           -- número de casa no slug tem 1 a 4.
           ELSE coalesce('olx:' || substring(t from '(\d{8,})$'), 'url:' || t)
         END
    FROM normal;
$fn$;

-- --------------------------------------------------------------------
-- O RASCUNHO DA CAPTAÇÃO.
CREATE TABLE IF NOT EXISTS captacoes (
  id             bigserial PRIMARY KEY,
  link_olx       text NOT NULL,
  olx_id         text,           -- o `listId` que veio no anúncio, como texto
  -- O retorno CRU do extrator, sem conversão nenhuma. Não se decide nada
  -- lendo daqui: é a prova de onde cada número saiu, para quando alguém
  -- perguntar "de onde ela tirou isso". O extrator devolve `preco_texto`
  -- como "R$ 390.000" justamente porque o primeiro anúncio pego sem escolher
  -- era uma fazenda de 12.000 hectares com "R$ 1.500 / Aluguel" -- e era
  -- R$ 1.500 POR HECTARE, à venda.
  dados_olx      jsonb,
  -- O que um humano ACEITOU: pré-preenchido a partir de `dados_olx` quando
  -- não há ambiguidade, corrigido e completado pelo Tel na tela. As chaves
  -- têm o nome das colunas de `imoveis`.
  campos         jsonb NOT NULL DEFAULT '{}'::jsonb,
  status         text NOT NULL DEFAULT 'rascunho',
  codigo_no_site text,           -- o código que o site deu, quando cadastrou
  erro           text,
  quem           text,           -- telefone canônico do Tel, ou login da tela
  criado_em      timestamptz NOT NULL DEFAULT now(),
  atualizado_em  timestamptz NOT NULL DEFAULT now(),

  CONSTRAINT captacao_link_nao_vazio CHECK (btrim(link_olx) <> ''),
  -- Link que é SÓ cauda ('?utm_source=whatsapp', '///') não é vazio, então
  -- passava pelo CHECK de cima -- mas `nay_chave_do_link` devolve NULL para
  -- ele, e índice único NÃO junta nulos. Medido em 02/09: dois desses entram
  -- lado a lado, e `nay_captacao_do_link` (que exige chave não nula) nunca
  -- acha nenhum dos dois. A tela criaria uma linha nova a cada colada, e a
  -- proteção contra duplicar ficaria calada exatamente onde deveria falar.
  -- Falha FECHADO: sem chave, não entra.
  CONSTRAINT captacao_link_tem_chave
    CHECK (nay_chave_do_link(link_olx) IS NOT NULL),
  CONSTRAINT captacao_status_ok
    CHECK (status IN ('rascunho', 'pronto', 'publicado', 'erro')),
  -- Publicado sem o código do site é captação que ninguém consegue ligar ao
  -- imóvel depois -- nem a varredura, nem quem for auditar.
  CONSTRAINT captacao_publicado_tem_codigo
    CHECK (status <> 'publicado' OR codigo_no_site IS NOT NULL),
  -- Só dígitos: os códigos deste catálogo vão de 45 a 5712. Sem isto, um
  -- "erro ao ler a página" gravado no lugar do código vira código.
  CONSTRAINT captacao_codigo_e_numero
    CHECK (codigo_no_site IS NULL OR codigo_no_site ~ '^[0-9]+$'),
  -- Erro sem mensagem é o silêncio que já custou três dias de varredura
  -- parada. Se o status é 'erro', tem que dizer qual.
  CONSTRAINT captacao_erro_tem_motivo
    CHECK (status <> 'erro' OR erro IS NOT NULL)
);

-- UMA captação por anúncio, e é o banco que garante. O pedido do Tel foi
-- explícito ("para não duplicar quando eu colar o mesmo link duas vezes"), e
-- duplicar não é só linha repetida: é o mesmo imóvel cadastrado duas vezes no
-- site, com as fotos baixadas duas vezes.
CREATE UNIQUE INDEX IF NOT EXISTS captacao_um_por_anuncio
  ON captacoes (nay_chave_do_link(link_olx));

-- A tela lista "o que está em aberto", mais recente primeiro.
CREATE INDEX IF NOT EXISTS captacoes_status_idx
  ON captacoes (status, atualizado_em DESC);

-- `atualizado_em` no gatilho, não na mão: campo de carimbo que depende de
-- quem escreve o UPDATE é campo que envelhece calado, e aí "parou quando?"
-- não tem resposta.
CREATE OR REPLACE FUNCTION nay_captacao_marca_atualizacao()
RETURNS trigger LANGUAGE plpgsql AS $fn$
BEGIN
  NEW.atualizado_em := now();
  RETURN NEW;
END $fn$;

DROP TRIGGER IF EXISTS captacoes_atualizado_em ON captacoes;
CREATE TRIGGER captacoes_atualizado_em
  BEFORE UPDATE ON captacoes
  FOR EACH ROW EXECUTE FUNCTION nay_captacao_marca_atualizacao();

-- --------------------------------------------------------------------
-- AS FOTOS DA CAPTAÇÃO.
--
-- Espelha `imovel_fotos` (codigo, ordem, url, arquivo, e_capa) com dois
-- campos a mais, e cada um tem uma medição por trás:
--
--  * `erro` e `baixada_em` separam "ainda não tentei" de "tentei e falhou".
--    Sem isso, foto que faltou é indistinguível de foto que não existe, e a
--    captação fica "quase pronta" para sempre.
--  * `bytes` porque URL de foto que NÃO existe devolve 404 COM UM JPEG DE
--    VERDADE DENTRO -- um quadrado cinza de ~49 KB (medido em 02/09). Quem
--    baixa é obrigado a conferir o status, mas se um dia esquecer, um lote
--    inteiro de fotos com o mesmo tamanho de ~49 KB é o rastro que denuncia.
--
-- `e_fachada` de `imovel_fotos` não tem equivalente aqui de propósito: nada
-- no anúncio da OLX diz qual foto é a fachada. Inventar seria chute.
CREATE TABLE IF NOT EXISTS captacao_fotos (
  id          bigserial PRIMARY KEY,
  captacao_id bigint NOT NULL REFERENCES captacoes(id) ON DELETE CASCADE,
  -- A ordem do anúncio, começando em 1 -- é a ordem que o proprietário
  -- escolheu, e é a mesma convenção de `imovel_fotos` (medido: 1.164 imóveis,
  -- ordem mínima 1, e a capa é sempre a ordem 1).
  ordem       int NOT NULL,
  url_olx     text NOT NULL,
  baixada_em  timestamptz,
  caminho     text,             -- o `arquivo` de `imovel_fotos`, no disco
  bytes       int,
  e_capa      boolean NOT NULL DEFAULT false,
  erro        text,

  CONSTRAINT foto_ordem_positiva CHECK (ordem >= 1),
  -- Foto de 0 byte marcada como baixada é arquivo vazio que só se descobre na
  -- hora de subir para o site -- e é o mesmo silêncio do JPEG cinza de 49 KB,
  -- um degrau abaixo. Negativo é bug de quem contou.
  CONSTRAINT foto_bytes_positivo CHECK (bytes IS NULL OR bytes > 0),
  -- Baixada sem caminho é foto que ninguém acha na hora de subir para o site.
  CONSTRAINT foto_baixada_tem_caminho
    CHECK (baixada_em IS NULL OR caminho IS NOT NULL),
  -- Ou baixou, ou falhou. Retentativa que dá certo tem que LIMPAR o erro --
  -- senão a foto boa continua contando como falha na hora de decidir se a
  -- captação está pronta.
  CONSTRAINT foto_ou_baixou_ou_falhou
    CHECK (baixada_em IS NULL OR erro IS NULL)
);

CREATE UNIQUE INDEX IF NOT EXISTS captacao_foto_ordem_unica
  ON captacao_fotos (captacao_id, ordem);
-- A mesma URL duas vezes é a mesma foto: a listagem da OLX repete anúncio
-- entre páginas (4 em 50, medido), e uma releitura do mesmo anúncio não pode
-- baixar tudo de novo.
CREATE UNIQUE INDEX IF NOT EXISTS captacao_foto_url_unica
  ON captacao_fotos (captacao_id, url_olx);
-- Uma capa só. Duas capas é a tela mostrando uma e o site publicando outra.
CREATE UNIQUE INDEX IF NOT EXISTS captacao_foto_uma_capa
  ON captacao_fotos (captacao_id) WHERE e_capa;

-- --------------------------------------------------------------------
-- A captação daquele link, se já existir.
--
-- Devolve 0 ou 1 linha -- em Python, `cur.fetchone()` sendo None quer dizer
-- "nunca vi esse anúncio". Link vazio devolve 0 linhas, nunca "a primeira que
-- eu achar": porteiro que erra para o lado de mostrar alguma coisa mostraria
-- a captação de outro imóvel.
CREATE OR REPLACE FUNCTION nay_captacao_do_link(p_link text)
RETURNS SETOF captacoes
LANGUAGE sql STABLE AS $fn$
  SELECT c.* FROM captacoes c
   WHERE nay_chave_do_link(p_link) IS NOT NULL
     AND nay_chave_do_link(c.link_olx) = nay_chave_do_link(p_link)
   -- O índice único já garante uma só. O ORDER BY + LIMIT é para o dia em que
   -- alguém dropar o índice: aí a mais antiga é a canônica, e a resposta
   -- continua sendo UMA, não uma sorteada.
   ORDER BY c.id
   LIMIT 1;
$fn$;

-- --------------------------------------------------------------------
-- NÃO existe mais aqui: `nay_captacao_pendencias`.
--
-- Ela nasceu ao mesmo tempo que `captacao_campos.o_que_falta`, em Python, e
-- as duas decidiam a MESMA regra: o que ainda falta para publicar. Duas
-- implementações da mesma regra é o padrão 4.3 do HISTORICO -- a gramática de
-- comando deste projeto chegou a ter quatro cópias, uma errada, e o sintoma
-- foi comando morto em produção.
--
-- E não era teoria: o `teste_captacao_pendencias_iguais.py`, escrito para
-- amarrar as duas, mostrou que elas discordavam nos SETE cenários. O banco
-- cobrava `cidade`, `fotos`, `logradouro` e `condominio_nome`; o Python
-- cobrava `banheiros` e `vagas`. Quem usa a tela é o Tel, e é a tela que
-- precisa de rótulo e ordem -- então o Python ficou como dono, e esta função
-- saiu. Os limiares que ela carregava (medidos contra o catálogo) estão nos
-- comentários do começo deste arquivo e continuam valendo como referência.


-- --------------------------------------------------------------------
-- Aviso, não parede: quais chaves de `campos` não existem em `imoveis`.
--
-- POR QUE NÃO É UM CHECK: a tela pode guardar coisa que só interessa a ela
-- (uma observação interna, quais fotos foram escolhidas), e um CHECK
-- recusaria a gravação inteira por causa disso. Mas um `quarto` no lugar de
-- `quartos` some calado até o dia do cadastro no site -- e aí ninguém liga o
-- campo vazio ao erro de digitação de semanas antes.
CREATE OR REPLACE FUNCTION nay_captacao_campos_desconhecidos(p_campos jsonb)
RETURNS text[]
LANGUAGE sql STABLE AS $fn$
  SELECT coalesce(array_agg(k ORDER BY k), ARRAY[]::text[])
    FROM jsonb_object_keys(coalesce(p_campos, '{}'::jsonb)) AS k
   WHERE k NOT IN (SELECT column_name::text
                     FROM information_schema.columns
                    WHERE table_schema = 'public' AND table_name = 'imoveis')
     -- NOSSOS, não do site: campo que a plataforma usa e que NÃO vai para o
     -- imobeasy.com. Sem esta exceção a função acusa um campo que a própria
     -- tela criou, e o Tel vê "campo inventado" para a anotação que ele
     -- mesmo escreveu.
     AND k NOT IN ('anotacoes');
$fn$;

-- --------------------------------------------------------------------
-- Confirmação na tela de quem instalou: `CREATE OR REPLACE` com assinatura
-- diferente NÃO substitui, cria uma SOBRECARGA -- foi assim que existiram
-- duas `nay_responder_conversando`, uma delas sem parede nenhuma. Se
-- aparecer a mesma função duas vezes aqui, é isso.
SELECT proname AS funcao, pg_get_function_identity_arguments(oid) AS argumentos
  FROM pg_proc
 WHERE proname LIKE 'nay_captacao%' OR proname = 'nay_chave_do_link'
 ORDER BY 1, 2;
