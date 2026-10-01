-- 256 (01/10/2026): PROMPT v19 -- a Nay é uma só, e o pedido de visita tem nome novo.
-- A segunda camada da ordem do Pedro ("de maneira nenhuma ela deve mandar isso:
-- quem cuida dela com você é a Rayssa... nunca; a Nay é só uma"). A primeira é
-- o texto pronto e a terceira é a parede da caixa, as duas na 255.
--
-- Duas mudanças no prompt do corretor:
--   * o texto que a ferramenta devolve virou "Só para confirmar a solicitação
--     de visita" (255), então o prompt deixa de chamá-lo de "Confirmação de
--     visita" -- se o prompt diz um nome e a ferramenta devolve outro, o modelo
--     tenta "arrumar" o texto em vez de mandar como veio;
--   * uma regra explícita: ela não cita colega nem passa a conversa para
--     ninguém. Para o corretor existe a Nay, e ponto.
--
-- DUAS ARMADILHAS desta função, que custaram duas tentativas aqui:
--   * nai_salvar_prompt quer a versão ATUAL (ela incrementa). Passar a nova faz
--     a gravação ser RECUSADA com ok=false -- e em silêncio, se ninguém olhar o
--     retorno. Por isso o bloco abaixo levanta erro quando não grava.
--   * replace() que não acha nada não falha: devolve o texto igual. Por isso as
--     duas trocas são conferidas antes de salvar.
BEGIN;
SET LOCAL lock_timeout = '3s';

DO $do$
DECLARE
  v_texto  text;
  v_versao int;
  r        record;
BEGIN
  SELECT texto, versao INTO v_texto, v_versao FROM nai_prompt WHERE papel = 'corretor';
  IF v_texto IS NULL THEN RAISE EXCEPTION 'não achei o prompt do corretor'; END IF;

  v_texto := replace(v_texto,
    'Com imóvel e horário: chame pedir_visita. Ela devolve a Confirmação de visita preenchida: mande exatamente como veio.',
    'Com imóvel e horário: chame pedir_visita. Ela devolve o pedido de visita preenchido ("Só para confirmar a solicitação de visita"): mande exatamente como veio, sem trocar palavra nenhuma. Esse texto é o PEDIDO para ele conferir -- não diga que a visita está confirmada ou agendada.');

  v_texto := replace(v_texto,
    '- O resto é com o sistema: a equipe confere, o proprietário é chamado e a "Visita confirmada" sai sozinha.',
    '- O resto é com o sistema: o proprietário é chamado e a "Visita confirmada" sai sozinha.
- VOCÊ É UMA SÓ. Nunca diga que outra pessoa vai cuidar, acompanhar ou chamar ele, e nunca cite nome de colega nosso. Quem trata a visita por dentro é assunto nosso. Para ele, quem responde é você -- diga "eu te aviso por aqui".');

  IF v_texto NOT LIKE '%Só para confirmar a solicitação de visita%' THEN
    RAISE EXCEPTION 'a troca do nome do pedido de visita não pegou: o prompt vivo está diferente do esperado';
  END IF;
  IF v_texto NOT LIKE '%VOCÊ É UMA SÓ%' THEN
    RAISE EXCEPTION 'a regra "você é uma só" não entrou: o prompt vivo está diferente do esperado';
  END IF;

  SELECT * INTO r FROM nai_salvar_prompt('corretor', v_texto, v_versao,
    'Claude 01/10 (256): a Nay é uma só; "solicitação de visita" no lugar de "confirmação"');
  IF NOT r.ok THEN RAISE EXCEPTION 'o prompt não gravou: %', r.motivo; END IF;
  RAISE NOTICE 'prompt do corretor gravado na versão %', r.versao;
END $do$;
COMMIT;
