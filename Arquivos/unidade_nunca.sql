-- O número da unidade NUNCA sai. Nem a promessa de verificar.
--
-- O CASO (01/09, 00h23): o Gustavo perguntou "Código 4946 / Qual andar,
-- bloco e apartamento" e a Nay respondeu "vou verificar o andar, o bloco
-- e o apartamento do código 4946 e te retorno".
--
-- POR QUE ISSO É GRAVE, nas palavras do Tel: "se a Nay passa o
-- apartamento para o corretor ele vai direto para o proprietário e ele
-- fazendo isso não temos negócio feito e tem muito corretor mal caráter
-- que faz isso". O identificador da unidade é o que separa a imobiliária
-- do negócio. Não é dado sensível por privacidade: é o ativo.
--
-- O CAMINHO DO VAZAMENTO NÃO É O BANCO PÚBLICO. Medido em 01/09: os 257
-- `complemento` preenchidos são referência de lugar ("próximo à Nilton
-- Lins"), não número de porta, e `imovel_por_codigo` não devolve nem
-- `complemento` nem `andar`. O vazamento acontece pelo CICLO DE
-- APRENDIZADO:
--
--   ela promete verificar -> escala ao Tel -> o Tel responde "ap 401"
--   -> a resposta fica em `pendencias.resposta` -> e é REUSADA para
--   todo mundo que perguntar parecido naquele imóvel, para sempre.
--
-- Por isso a parede fica em `nay_escalar`: a pergunta de unidade nem
-- chega a virar pendência. O Tel não é convidado a responder, então não
-- existe resposta para reusar. Regra no prompt seria pedido; isto é
-- parede.
--
-- SEGUNDA PAREDE, para o que já está gravado: nenhuma resposta antiga
-- que contenha número de unidade é reusada.
--
--   docker cp unidade_nunca.sql nay-postgres:/tmp/un.sql
--   docker exec nay-postgres psql -U nay -d naydb -f /tmp/un.sql

-- --------------------------------------------------------------------
-- A pergunta pede o identificador da UNIDADE?
--
-- MEDIDO CONTRA AS 2.960 MENSAGENS REAIS, e a medição mudou a regra. A
-- primeira versão bloqueava 25 mensagens, e 15 delas eram legítimas:
--
--   "Me passa as fotos desse apto"          -> quer FOTO, "apto" é só o
--   "Envia aquele Apto do Unno mobiliado"      substantivo do imóvel
--   "me envia o material dessa apartamento"
--   "Qual o andar do Smart Tower"           -> quer a VISTA
--   "O apt é em qual torre? Quero saber     -> quer a ORIENTAÇÃO (sol),
--    se é nascente"                            que é argumento de venda
--   "E qual o andar do apto? Nascente ou poente?"
--
-- Andar e torre SOZINHOS são pergunta de venda, e 11 corretores fizeram
-- essa pergunta. Bloquear os dois calaria a Nay num assunto legítimo e
-- diário. O que localiza a porta é o NÚMERO DA UNIDADE -- foi disso que
-- o Tel reclamou, e é isso que fecha aqui.
--
-- Quem quiser fechar mais: `config.unidade_nivel = 'tudo'` bloqueia andar
-- e torre também, com um UPDATE e sem deploy.
--
-- CUIDADO ao editar: `~` e `||` tem a MESMA precedencia no Postgres e
-- associam a esquerda, entao `t ~ 'a' || 'b'` vira `(t ~ 'a') || 'b'` e a
-- regex e avaliada pela metade -- "parentheses not balanced" em tempo de
-- execucao, nao na criacao. Toda regex quebrada em duas linhas precisa
-- estar dentro de parenteses.
CREATE OR REPLACE FUNCTION nay_pede_localizacao_da_unidade(p_texto text)
RETURNS boolean
LANGUAGE plpgsql STABLE AS $fn$
DECLARE
  t     text := lower(unaccent(coalesce(p_texto,'')));
  nivel text := coalesce((SELECT valor FROM config WHERE chave = 'unidade_nivel'),
                         'apartamento');
  -- "apartamento" e o substantivo mais comum da conversa inteira: aparece
  -- em busca ("tem apartamento no Tarumã"), em visita ("confirma a visita
  -- no apartamento"), em conversa ("tá lá no apt ainda?"). A janela entre
  -- a pergunta e o substantivo TEM que ser curta -- com 25 caracteres a
  -- regra pegava "me informe se esse Apartamento ta quitado", que e
  -- pergunta de pagamento. So cabe artigo e verbo de ligacao.
  -- Ate duas palavrinhas, nao uma: "Qual E O apartamento?" atravessava a
  -- janela de uma so. Achado no red team de 01/09.
  colagem constant text := '\s*(e|eh|é|o|a|os|as|do|da|de|no|na|seu|sua|esse|essa|este|esta|qual)?'
                        || '\s*(o|a|os|as|do|da|de|esse|essa|este|esta)?\s*';
  unidade  constant text := '(apartamento|apartamentos|apto|aptos|apt|ap|ape|apes|'
                            || 'cobertura|kitnet|kit|unidade|unidades|complemento|porta|'
                            -- 94 imóveis são "Lote em Condomínio": ali o número
                            -- do lote é o identificador, igual ao do apartamento.
                            || 'lote|lotes|quadra|sala)';
  -- CASA entra so na pergunta pelo NUMERO. "qual casa" e busca -- das 45
  -- mensagens reais que citam casa, quase todas sao "procuro casa na
  -- cidade nova", "casa do nova cidade disponivel?". Bloquear "qual casa"
  -- calaria a Nay na conversa mais comum que ela tem.
  numerada constant text := '(apartamento|apartamentos|apto|aptos|apt|ap|ape|apes|'
                            || 'cobertura|unidade|unidades|complemento|porta|casa|casas|'
                            || 'sobrado|lote|lotes|quadra|sala|conjunto)';
  loc      constant text := '(apartamento|apto|apt|unidade|bloco|torre|andar|complemento)';
BEGIN
  IF t = '' THEN RETURN false; END IF;

  -- NAO EXISTE FILTRO NEGATIVO AQUI, e a ausencia e deliberada.
  --
  -- Havia um: se a mensagem citasse foto, video, material ou ficha, a
  -- funcao devolvia false ANTES de olhar qualquer regra positiva. O red
  -- team de 01/09 furou em um minuto:
  --     BLOQUEIA  "qual o apartamento"
  --     PASSA     "qual o apartamento e me manda as fotos"
  -- E pedir foto e o gesto mais comum da conversa -- 57 mensagens --
  -- porque o proprio gatilho de fotos EXIGE que o corretor peca. Pior: o
  -- no `Gravar na fila` chama esta mesma funcao, entao a segunda camada
  -- (o aviso no turno do agente) caia junto.
  --
  -- MEDIDO antes de remover: as 15 mensagens legitimas que o filtro
  -- existia para proteger continuam passando sem ele -- quem separa e a
  -- janela curta `colagem` com a lista estreita `unidade`, como o proprio
  -- comentario ja dizia. Nas 2.960 reais: 6 bloqueadas com ele, 6 sem.
  --
  -- A LICAO, que ja estava escrita neste arquivo e eu apliquei pela
  -- metade de manha: filtro negativo em regra de seguranca e senha que
  -- qualquer um adivinha. Nao basta encurtar a lista -- ela nao pode
  -- existir.

  -- PERGUNTA direta pelo identificador da unidade. Janela curta.
  IF t ~ ('\mqual' || colagem || unidade || '\M')
     OR t ~ ('\m(numero|nro|n[°º]|n\.)' || colagem || '(do|da)?\s*' || numerada || '\M')
     -- "qual o numero da casa", "qual o numero" -- decisao do Tel em
     -- 01/09: o numero da casa e o identificador dela, igual ao numero do
     -- apartamento.
     OR t ~ ('\mqual' || colagem || '(o\s+)?numero' || colagem || '(do|da)?\s*' || numerada || '\M')
     OR t ~ ('\m' || unidade || '\s*(e|eh|é)?\s*(qual|numero|nro)\M')
     OR t ~ '\mendereco\s*(completo|exato|certo|detalhado|certinho)\M'
     OR t ~ '\m(completo|exato)\s*(o\s*)?endereco\M'
     OR t ~ ('\m(me\s+)?(passa|passe|manda|mande|informa|informe|envia|envie|diz|fala)\s*'
          || '(me\s+)?(o|a)?\s*(numero|complemento|localizador|endereco completo)\M')
     OR t ~ ('\m(me\s+)?(passa|passe|manda|mande)\s*(me\s+)?qual' || colagem || unidade || '\M')
     OR t ~ '\monde\s*(fica|e|é)?\s*(exatamente|certinho)\M'
     -- "qual o numero?" sozinho. Num contexto de imovel nao ha outro
     -- numero que ele possa querer -- valor ele pede por "valor" ou
     -- "quanto".
     OR t ~ ('\mqual' || colagem || '(numero|nro|n[°º])\M')
  THEN
    RETURN true;
  END IF;

  -- DOIS localizadores numa pergunta: "torre e apto", "bloco e
  -- apartamento", "qual andar, bloco e apartamento". O conjunto e a porta,
  -- mesmo que cada parte sozinha fosse aceitavel.
  -- Dois localizadores juntos NAO precisam de "qual": "Torre e apto?" e
  -- mensagem real deste banco e passava, porque o bloco exigia o
  -- interrogativo. A pergunta esta na propria justaposicao.
  IF (
       -- SÓ conjunção, nunca possessivo. "torre E apto" pergunta duas
       -- coisas e a segunda é o número; "torre DO apto" pergunta uma só, a
       -- torre, que o Tel liberou. Com "do" na lista, "E qual o andar do
       -- apto? Nascente ou poente?" -- mensagem real, pergunta de
       -- orientação solar -- passava a ser recusada.
       t ~ ('\m(bloco|torre|tr|bl|andar)\s*(,|e|eh|é)?\s*(o|a)?\s*' || unidade || '\M')
    OR t ~ ('\m' || unidade || '\s*(,|e|eh|é)?\s*(o|a)?\s*(bloco|torre|andar)\M')
    OR t ~ '\m(bloco|torre)\s*(,|e|eh|é)?\s*(o|a)?\s*andar\M'
    OR t ~ '\mandar\s*(,|e|eh|é)?\s*(o|a)?\s*(bloco|torre)\M')
  THEN
    RETURN true;
  END IF;

  -- Só quando o Tel apertar: andar e torre sozinhos passam a ser recusa.
  IF nivel = 'tudo' AND t ~ ('\mqual' || colagem || '(andar|bloco|torre)\M') THEN
    RETURN true;
  END IF;

  RETURN false;
END;
$fn$;

INSERT INTO config (chave, valor) VALUES ('unidade_nivel', 'apartamento')
ON CONFLICT (chave) DO NOTHING;

-- --------------------------------------------------------------------
-- Um texto CONTÉM identificador de unidade? Usado para não reusar
-- resposta antiga que já tenha o número, e para não deixar a descrição
-- do anúncio entregar o que a pergunta não conseguiu.
CREATE OR REPLACE FUNCTION nay_tem_numero_de_unidade(p_texto text)
RETURNS boolean
LANGUAGE plpgsql IMMUTABLE AS $fn$
DECLARE
  t text := lower(unaccent(coalesce(p_texto,'')));
  -- O que cabe entre a palavra e o numero: "ap 401", "ap. n 401",
  -- "apartamento e o 401", "unidade: 51".
  conn constant text := '\.?\s*(n[o°º]?\.?|numero|e|eh|é|:|,)?\s*(o|a)?\s*';
  -- O que vem DEPOIS e que decide se e porta ou descricao: "ap 2 quartos"
  -- e tipo de imovel, nao numero de unidade. Sem esta exclusao o detector
  -- acusava 74 descricoes, quase todas assim.
  medida constant text := '(quarto|quartos|qto|qtos|dorm|suite|suites|ste|vaga|vagas|'
                       || 'banheiro|banheiros|m2|m²|metros|mil|reais|andar|andares|'
                       || 'piso|pisos|carro|carros|d\M|q\M)';
BEGIN
  IF t = '' THEN RETURN false; END IF;

  -- "porta 402" entra: e a forma que o Tel usaria respondendo. Numero
  -- SECO ("401") NAO entra, de proposito -- a resposta dele pode ser
  -- "3500" falando de preco, e bloquear todo numero mataria o reuso de
  -- conhecimento legitimo. A parede que impede a pergunta de virar
  -- pendencia e que carrega o peso; este detector e a segunda linha.
  IF t ~ ('\m(ap|apto|apart|apartamento|unidade|un|porta|casa|sobrado|lote|quadra)\M' || conn || '[0-9]{1,5}[a-z]?\M')
     AND t !~ ('\m(ap|apto|apart|apartamento|unidade|un|porta|casa|sobrado|lote|quadra)\M' || conn
            || '[0-9]{1,5}[a-z]?\s*' || medida)
  THEN
    RETURN true;
  END IF;

  -- "bloco B", "torre 2", "bl 3". O `\M` depois da palavra e essencial:
  -- sem ele, "Av. das Torres 4" casa como "torre" + "s", e vira falso
  -- positivo num nome de avenida de Manaus.
  IF t ~ ('\m(bloco|torre|bl|tr)\M' || conn || '[0-9a-z]{1,2}\M') THEN
    RETURN true;
  END IF;

  RETURN false;
END;
$fn$;

-- --------------------------------------------------------------------
-- A frase que ela diz. Uma só, para não haver duas versões da política.
--
-- NÃO diz "não posso informar" seco: o corretor é parceiro, não suspeito.
-- Diz o motivo comercial, que ele entende, e oferece o caminho certo --
-- que é a visita agendada pela Imob Easy.
CREATE OR REPLACE FUNCTION nay_recusa_de_unidade()
RETURNS text
LANGUAGE sql IMMUTABLE AS $fn$
  SELECT 'RECUSE, e NAO escale ao Tel. Diga ao corretor, com as suas palavras '
      || 'e no seu tom, que o numero do apartamento, o bloco, a torre e o andar '
      || 'a gente so passa na hora da visita agendada -- e politica da Imob Easy '
      || 'para todos os imoveis, nao e nada contra ele. Ofereca agendar a visita, '
      || 'que e quando ele ve tudo. NAO prometa verificar, NAO diga que vai '
      || 'perguntar ao Tel, NAO diga que retorna depois: nao existe retorno, a '
      || 'resposta e essa. Se ele insistir, repita uma vez e siga ajudando no '
      || 'resto -- valor, area, quartos, fotos, tudo isso voce passa normalmente.';
$fn$;

-- --------------------------------------------------------------------
-- A descrição do anúncio, sem o número da unidade.
--
-- ACHADO NA AUDITORIA (01/09): eu tinha descartado a descrição como vetor
-- de vazamento com o argumento de que ela vem do anúncio PÚBLICO. O
-- argumento estava certo e a conclusão errada -- três anúncios trazem o
-- número literal:
--
--   3985  "apto 801- Torre Speranza 8° andar"
--   5196  "Aluga-se apart. 601 Torre Verdi – Cond. Flor..."
--   3893  "01 vaga de Garagem 2° andar, torre 2"
--
-- Que o site publique não autoriza a Nay a entregar: o corretor teria que
-- ir ao site procurar, e ela entrega de mão beijada a quem perguntar. São
-- coisas de atrito muito diferente. (Os três anúncios são um problema do
-- cadastro, e isso é do Tel.)
--
-- `imovel_por_codigo` despeja a descrição inteira em `instrucao_para_voce`
-- para responder pet, mobília e ponto comercial. Passa a despejar esta.
-- Obedece o MESMO `config.unidade_nivel` da pergunta: um interruptor só
-- governa o que ela recusa e o que ela lê. Em 'tudo', torre e andar também
-- somem da descrição -- senão o Tel apertaria a regra e a descrição
-- continuaria entregando pela porta dos fundos.
CREATE OR REPLACE FUNCTION nay_descricao_segura(p_texto text)
RETURNS text
LANGUAGE sql STABLE AS $fn$
  SELECT NULLIF(btrim(regexp_replace(
    CASE WHEN coalesce((SELECT valor FROM config WHERE chave='unidade_nivel'),
                       'apartamento') = 'tudo'
         THEN regexp_replace(x, '\m(torre|bloco|bl|tr)\M\.?\s*[0-9a-z]{1,2}\M',
                             'no condomínio', 'gi')
         ELSE x END,
    '\s+', ' ', 'g')), '')
  FROM (SELECT btrim(regexp_replace(coalesce(p_texto,''),
      -- "apto 801", "apart. 601", "ap 401", "unidade 51" -- mas nunca
      -- "apto 3 QTS" nem "apartamento 2 quartos", que descrevem o tipo.
      '\m(ap|apto|apart|apartamento|unidade|un|porta|casa|sobrado|lote|quadra)\M\.?\s*(n[o°º]?\.?)?\s*'
      || '([0-9]{2,5}[a-z]?)(?!\s*(quarto|qto|dorm|suite|ste|vaga|banheiro|m2|m²|'
      || 'metros|mil|reais|andar|piso|carro|qts|d\M|q\M))',
      -- `\1` devolve o SUBSTANTIVO casado, nao a palavra "apartamento":
      -- some só o número. Antes, "Linda casa 45" virava "Linda
      -- apartamento", que além de errado entregava o tipo trocado.
      '\1', 'gi')) AS x) s;
$fn$;

-- --------------------------------------------------------------------
-- O logradouro sem o número.
--
-- DECISÃO DO TEL (01/09): "casa não pode falar o número dela". O card de
-- imóvel administrado mostra `i.logradouro`, e hoje nenhum dos que
-- aparecem tem número -- mas 34 logradouros do catálogo têm, e o dia em
-- que um desses virar administrado o número sai sozinho. A proteção fica
-- na query, não na sorte do cadastro.
--
-- "Av. Curaçao"           -> "Av. Curaçao"        (nada a tirar)
-- "Rua José de Arimateia, 128" -> "Rua José de Arimateia"
-- "KM 09 da AM 70"        -> "KM 09 da AM 70"     (não é número de porta)
CREATE OR REPLACE FUNCTION nay_endereco_sem_numero(p_texto text)
RETURNS text
LANGUAGE sql IMMUTABLE AS $fn$
  SELECT NULLIF(btrim(regexp_replace(
    regexp_replace(coalesce(p_texto,''),
      -- número de porta: vírgula/nº/traço e o número, no FIM do endereço.
      -- Preso ao fim de propósito: "KM 09 da AM 70" e "Av. das Torres 4"
      -- têm número no meio e são nome de via, não porta.
      '\s*(,|-|–|n[°º]?\.?|numero)\s*[0-9]{1,6}[a-z]?\s*$', '', 'gi'),
    '\s+', ' ', 'g'), ' ,-'), '');
$fn$;
