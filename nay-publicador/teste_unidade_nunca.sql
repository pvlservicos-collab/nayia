-- Prova que a parede do número da unidade fecha, e que não fecha demais.
--
-- AS DUAS METADES IMPORTAM. Fechar demais é tão ruim quanto abrir: a
-- primeira versão bloqueava 31 das 2.960 mensagens reais, e "me informe
-- se esse Apartamento tá quitado", "Você tem apartamento no metrópole" e
-- "Tem alguém no apartamento?" estavam entre elas. Uma Nay que se recusa
-- a falar sempre que a palavra "apartamento" aparece é inútil.
--
-- Os casos de BLOQUEIA que vieram de mensagem real estão marcados. Os
-- outros são variações que ainda não apareceram, mas vão.
--
--   docker cp teste_unidade_nunca.sql nay-postgres:/tmp/t.sql
--   docker exec nay-postgres psql -U nay -d naydb -f /tmp/t.sql

BEGIN;
CREATE TEMP TABLE casos(texto text, deve_bloquear boolean, origem text);
INSERT INTO casos VALUES
-- ---------------- TEM QUE BLOQUEAR ----------------
('Código 4946' || chr(10) || 'Qual andar, bloco e apartamento', true, 'REAL 01/09'),
('Qual é  o bloco e o apartamento',                     true,  'REAL'),
('4.6.  Qual torre e apto e senha',                     true,  'REAL'),
('3.5.  Qual é a torre e apto',                         true,  'REAL'),
('Me passa qual o apto',                                true,  'REAL'),
('Qual torre e andar?',                                 true,  'REAL'),
('qual o apartamento?',                                 true,  'variação'),
('qual o apto?',                                        true,  'variação'),
('qual apt',                                            true,  'variação'),
('qual a unidade',                                      true,  'variação'),
('qual o complemento',                                  true,  'variação'),
('qual o numero do apartamento',                        true,  'variação'),
('numero do apto por favor',                            true,  'variação'),
('nº do apartamento',                                   true,  'variação'),
('me passa o numero',                                   true,  'variação'),
('me manda o complemento',                              true,  'variação'),
('me passa o endereço completo',                        true,  'variação'),
('preciso do endereço exato',                           true,  'variação'),
('onde fica exatamente',                                true,  'variação'),
('qual apartamento e andar',                            true,  'variação'),
('bloco e apto qual é',                                 true,  'variação'),
('qual o apto pra visita amanhã',                       true,  'a visita não abre a parede'),
('qual o numero do apartamento, quero mandar as fotos', true,  'foto não abre a parede'),
-- ---------------- NÃO PODE BLOQUEAR ----------------
('Depois me informe se esse Apartamento tá quitado, e o valor de entrada.', false, 'REAL — pagamento'),
('Você tem apartamento no metrópole',                   false, 'REAL — busca'),
('Tem alguém no apartamento?',                          false, 'REAL — visita'),
('TÁ LÁ NO APT AINDA É',                                false, 'REAL — conversa'),
('Estive no apto e o mesmo é muito bom',                false, 'REAL — conversa'),
('Me passa as fotos desse apto',                        false, 'REAL — foto'),
('Envia aquele Apto do Unno 100% mobiliado',            false, 'REAL — envio'),
('Bom dia me envia o material dessa apartamento',       false, 'REAL — material'),
('Me confirma a visita no apartamento?',                false, 'REAL — visita'),
('Gostaria de saber a disponibilidade de visita no apartamento no Estilo Ponta Negra', false, 'REAL — visita'),
('Qual o andar do Smart Tower. Minha cliente gostou.',  false, 'REAL — andar sozinho é venda'),
('O apt é em qual torre? Quero saber se é nascente',    false, 'REAL — orientação'),
('E qual o andar do apto? Nascente ou poente?',         false, 'REAL — orientação'),
('Qual é a torre?',                                     false, 'REAL — torre sozinha'),
('Qual bloco?',                                         false, 'REAL — bloco sozinho'),
('QUEM TEM APARTAMENTO NO PARQUE 10',                   false, 'REAL — busca'),
('quantos andares tem o prédio',                        false, 'característica do prédio'),
('qual o valor do condomínio',                          false, 'valor'),
('apartamento de 2 quartos no Tarumã',                  false, 'busca'),
('esse apartamento aceita pet?',                        false, 'regra do condomínio'),
('qual a area do apartamento',                          false, 'área'),
('qual o valor do apartamento',                         false, 'valor'),
-- ---- red team de 01/09: as abreviações e as janelas ----
('qual o ap',                                           true,  'RED TEAM — ap era a que faltava'),
('qual o apê?',                                         true,  'RED TEAM'),
('Qual é o apartamento?',                               true,  'RED TEAM — duas palavrinhas'),
('Torre e apto?',                                       true,  'REAL — sem "qual", passava'),
('qual o numero?',                                      true,  'RED TEAM — sozinho, passava'),
('qual o lote',                                         true,  'RED TEAM — 94 lotes no catálogo'),
('qual a quadra',                                       true,  'RED TEAM'),
('qual a sala',                                         true,  'RED TEAM'),
-- ...e o que o red team pediu para bloquear e a decisão do Tel MANDA passar:
-- "torre DO apto" é possessivo, pergunta uma coisa só, e ele liberou a torre.
('Qual a torre do apto?',                               false, 'possessivo, não conjunção'),
('E qual o andar do apto? Nascente ou poente?',         false, 'REAL — orientação solar'),
-- ---- red team de 01/09: a cauda de foto NÃO abre a parede ----
-- Havia um filtro negativo que devolvia false se a mensagem citasse
-- foto, vídeo ou material -- antes de olhar qualquer regra positiva.
-- "qual o apartamento" bloqueava; "qual o apartamento e me manda as
-- fotos" passava. E pedir foto é o gesto mais comum da conversa.
('qual o apartamento e me manda as fotos',              true,  'RED TEAM'),
('qual o apartamento? manda a foto',                    true,  'RED TEAM'),
('qual a unidade? manda as fotos',                      true,  'RED TEAM'),
('Qual andar, bloco e apartamento, e manda as fotos',   true,  'RED TEAM'),
('qual o numero da casa? manda o video',                true,  'RED TEAM'),
('Pode me enviar fotos e descricao? Qual e o bloco e o apartamento?', true, 'RED TEAM'),
('Tem as fotos' || chr(10) || 'Qual o apartamento' || chr(10) || 'Tem a descricao', true, 'RED TEAM'),
('qual o apartamento? preciso do anuncio',              true,  'RED TEAM'),
('qual o apartamento e a ficha',                        true,  'RED TEAM'),
-- ...e as legítimas que o filtro existia para proteger, que continuam passando
('Quer saber onde fica ? E se tem foto da frente tb',   false, 'REAL — sem o filtro, ainda passa'),
-- ---- decisão do Tel em 01/09: casa não pode falar o número dela ----
('qual o numero da casa',                               true,  'número da casa'),
('numero da casa?',                                     true,  'número da casa'),
('me passa o numero da casa',                           true,  'número da casa'),
('qual o numero do sobrado',                            true,  'mesma coisa'),
-- ...mas "casa" é o substantivo mais comum da conversa: 45 mensagens
-- reais citam casa, quase todas em busca. Nenhuma pode ser calada.
('qual a casa',                                         false, 'busca'),
('procuro casa na cidade nova',                         false, 'REAL — busca'),
('casa do nova cidade disponivel?',                     false, 'REAL — busca'),
('Busco Casa pra Locação de 2.500 a 3.000',             false, 'REAL — busca'),
('A casa em condomínio fechado só nao pode ser no taruma', false, 'REAL — perfil'),
('essa casa e boa?',                                    false, 'opinião'),
-- ...e o que o Tel liberou de propósito para apartamento
('qual o andar',                                        false, 'REAL — o Tel liberou'),
('qual a torre',                                        false, 'REAL — o Tel liberou'),
('qual o andar e a face solar',                         false, 'o Tel liberou');

SELECT CASE WHEN nay_pede_localizacao_da_unidade(texto) = deve_bloquear THEN 'OK  ' ELSE 'ERRO' END AS r,
       CASE WHEN deve_bloquear THEN 'bloqueia' ELSE 'passa   ' END AS esperado,
       left(replace(texto, chr(10), ' / '), 52) AS caso,
       origem
  FROM casos
 ORDER BY (nay_pede_localizacao_da_unidade(texto) = deve_bloquear), deve_bloquear DESC, texto;

-- --------------------------------------------------------------------
-- E o detector de numero de unidade em TEXTO, que guarda o reuso de
-- resposta antiga. Errar para o lado frouxo aqui bloqueia conhecimento
-- legitimo; errar para o lado apertado deixa o numero ser reusado.
-- --------------------------------------------------------------------
-- E o endereço sem o número, o outro lado da decisão: a rua pode, o
-- número da casa não.
CREATE TEMP TABLE casos_end(txt text, deve text);
INSERT INTO casos_end VALUES
  ('Av. Curaçao',                 'Av. Curaçao'),
  ('Rua José de Arimateia, 128',  'Rua José de Arimateia'),
  ('Avenida do Turismo nº 450',   'Avenida do Turismo'),
  ('Rua X - 12',                  'Rua X'),
  -- número no MEIO é nome de via, não porta
  ('KM 09 da AM 70',              'KM 09 da AM 70'),
  ('Avenida das Torres',          'Avenida das Torres');

SELECT CASE WHEN nay_endereco_sem_numero(txt) = deve THEN 'OK  ' ELSE 'ERRO' END AS r,
       txt, nay_endereco_sem_numero(txt) AS deu, deve
  FROM casos_end ORDER BY (nay_endereco_sem_numero(txt) = deve), txt;

CREATE TEMP TABLE casos_texto(txt text, deve boolean);
INSERT INTO casos_texto VALUES
  ('o apartamento e o 401',              true),
  ('ap 401',                             true),
  ('apto 1204 torre B',                  true),
  ('unidade 51',                         true),
  ('bloco B',                            true),
  ('torre 2',                            true),
  ('ap. n 302',                          true),
  ('e o apartamento: 1102',              true),
  -- os falsos positivos que a medicao contra as 1.208 descricoes achou
  ('ap 2 Quartos, 43m2, 1 vaga',         false),
  ('Av. das Torres 4 super suites',      false),
  ('Alphaville Manaus 4',                false),
  ('1o piso Garagem coberta p 4 carros', false),
  ('Apto com 3d sdo 1 ste',              false),
  ('9 andar 2 dormitorios',              false),
  ('apartamento de 2 quartos no Taruma', false),
  ('aceita pet ate 10kg',                false),
  ('o condominio e 450 reais',           false),
  -- a outra metade da regra do Tel, que os detectores não conheciam
  ('a casa 12 da quadra B',              true),
  ('casa 45',                            true),
  ('lote 22',                            true),
  ('quadra 7 casa 3',                    true),
  ('casa de 3 quartos',                  false),
  ('casa com 120m2',                     false),
  ('lote de 300 metros',                 false),
  -- 'porta 402' e a forma que o Tel usaria ao responder
  ('a porta 402, chave com o porteiro',   true),
  ('porta de entrada blindada',           false),
  ('portaria 24h',                        false),
  ('apartamento com 4 portas',            false);

SELECT CASE WHEN nay_tem_numero_de_unidade(txt) = deve THEN 'OK  ' ELSE 'ERRO' END AS r,
       CASE WHEN deve THEN 'tem numero' ELSE 'nao tem   ' END AS esperado, txt
  FROM casos_texto ORDER BY (nay_tem_numero_de_unidade(txt) = deve), deve DESC;

SELECT CASE WHEN falhas = 0
            THEN 'TODOS OS ' || total || ' CASOS PASSARAM'
            ELSE falhas || ' DE ' || total || ' FALHARAM'
       END AS resumo
  FROM (
    SELECT count(*) FILTER (WHERE NOT ok) AS falhas, count(*) AS total FROM (
      SELECT nay_pede_localizacao_da_unidade(texto) = deve_bloquear AS ok FROM casos
      UNION ALL
      SELECT nay_tem_numero_de_unidade(txt) = deve FROM casos_texto
      UNION ALL
      SELECT nay_endereco_sem_numero(txt) = deve FROM casos_end
    ) u
  ) s;
ROLLBACK;
