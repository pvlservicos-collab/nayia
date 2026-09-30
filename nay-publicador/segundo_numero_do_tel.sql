-- UM SEGUNDO NÚMERO COM A VOZ DO TEL (Tel, 28/09)
--
-- O PEDIDO, literal: "todo comando que o Tel tem, você repassa também para
-- este número como se fosse ele 92 98595-6408 ... nestes dois números".
-- E, perguntado, ele escolheu que o número novo RECEBE tudo também.
--
-- O QUE ISTO DÁ A ESSE NÚMERO: postar nos 17 grupos, mandar imóvel para
-- qualquer corretor, agendar e apagar da grade, marcar VENDEU/ALUGOU. Nada
-- disso desfaz. Não é uma permissão de leitura -- é a mão dele.
--
-- A INFRAESTRUTURA JÁ EXISTIA, de 15/09: `nai_config.comando_telefones` e
-- `nai_pode_comandar()`, criadas para "quero que o tel e eu quando digitar no
-- pv dela Agenda de visitas". Só que valiam para um conjunto RESTRITO
-- (`nai_e_comando_extra`: agenda, parada, corretor, imóvel). O que muda hoje
-- é a largura: quem está na lista passa a ter TODOS os comandos.
--
-- MEDIDO ANTES DE ALARGAR: `comando_telefones` continha só o número do
-- próprio Tel. Ninguém ganha poder por tabela -- só quem entrar agora.
--
-- `nai_chave` normaliza (o WhatsApp entrega o mesmo número com e sem o 9),
-- então a comparação é por ela, nunca por igualdade crua.

BEGIN;

-- 1. QUEM TEM A VOZ DO TEL, num lugar só.
--
-- Vira função para os quatro pontos do `nai_abrir_turno` pararem de repetir
-- `v_chave = nai_chave(nai_cfg('tel_telefone'))`. Regra de identidade
-- repetida é o padrão 4.3 do HISTORICO -- e aqui a divergência daria comando
-- aceito num caminho e recusado no outro, que é o pior dos dois mundos:
-- parece quebrado e não é.
CREATE OR REPLACE FUNCTION nai_e_voz_do_tel(p_chave text)
RETURNS boolean LANGUAGE sql STABLE AS $$
  SELECT p_chave = nai_chave(nai_cfg('tel_telefone'))
      OR nai_pode_comandar(p_chave);
$$;

-- 2. O número entra nas duas listas.
UPDATE nai_config SET valor = '559294717316,5592985956408'
 WHERE chave = 'comando_telefones' AND valor = '559294717316';

-- `escala_sem_parar` é a lista de quem NÃO tem o chat "assumido" quando a
-- escalada acontece. Sem isto, o número novo manda uma imagem, o
-- `nai_parar_chat` marca o chat dele como "humano assumiu", e os comandos
-- dele passam a morrer em silêncio -- foi exatamente o que aconteceu com o
-- Tel em 25/09 e custou dois dias para achar.
UPDATE nai_config
   SET valor = valor || ',5592985956408'
 WHERE chave = 'escala_sem_parar'
   AND valor NOT LIKE '%5592985956408%';

COMMIT;

SELECT chave, valor FROM nai_config
 WHERE chave IN ('tel_telefone','comando_telefones','escala_sem_parar')
 ORDER BY chave;
