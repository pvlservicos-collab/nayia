-- 557 (Pedro, 01/11/2026: "pegue todas as perguntas que a Nay fez ao Tel nos últimos 7 e depois 15 dias e atualiza
-- nosso banco de dados com elas ... para que a Nay não pergunte novamente").
--
-- A memória das respostas (imovel_conhecimento) tinha três problemas, achados nas 185 perguntas de 17/10 a 01/11:
--   1. resposta que não foi guardada (5709: o IPTU e as cobranças; a pergunta voltou duas vezes);
--   2. o assunto guardado era o texto da pergunta ("pergunta: essa tem quintal?"), e a próxima pergunta do mesmo
--      assunto não achava a resposta; aqui cada uma ganha o assunto curto ("quintal", "piscina", "andar");
--   3. recado do Tel guardado como se fosse do imóvel ("chegou", "Excelente", "Segue o vídeo", o checklist, "Fala que
--      a gente vai ver"), resposta de outro imóvel (9027 recebeu o andar do Florence Garden), resposta de uma palavra
--      sem sentido ("Não", "não"), nome de cliente, negociação (piso de preço do 2108, faixa do 9064) e duplicatas.
-- Não mexe: os cinco em que o guardado e a ficha discordam (887, 5609, 3883, 5001 só reescrito fora, 5707), que vão ao
-- Pedro; o endereço exato do Weck sai (ao corretor só bairro e condomínio).
-- Cada linha confere o imóvel (id + código): se outra sessão mexeu, o comando não acha e não faz nada.
BEGIN;
SET LOCAL lock_timeout = '3s';

-- 1. a resposta que faltava
INSERT INTO imovel_conhecimento (codigo, assunto, texto, quem_contou)
VALUES ('5709', 'incluso_no_aluguel', 'O IPTU fica por conta do proprietário no aluguel de R$ 2.900. Seguro e outras taxas: confirmar com a equipe.',
        'dono (fila, 29/10; guardado em 01/11)')
ON CONFLICT (codigo, assunto) DO NOTHING;

-- 2. o assunto certo (e o texto sem nome de cliente, sem o outro imóvel, sem o valor truncado)
UPDATE imovel_conhecimento SET assunto = 'edicula', texto = 'A edícula foi construída bem no final do terreno, para trás (nos fundos).', atualizado_em = now() WHERE id = 694 AND codigo = '331';
UPDATE imovel_conhecimento SET assunto = 'gas_agua_iptu_caucao', atualizado_em = now() WHERE id = 700 AND codigo = '331';
UPDATE imovel_conhecimento SET texto = 'A proprietária informou R$ 2.500 de aluguel (09/10), sem reajuste até 28/10.', atualizado_em = now() WHERE id = 681 AND codigo = '331';
UPDATE imovel_conhecimento SET assunto = 'financiamento', atualizado_em = now() WHERE id = 703 AND codigo = '776';
UPDATE imovel_conhecimento SET assunto = 'disponibilidade', texto = 'Está desocupado (o Tel, 16/10).', atualizado_em = now() WHERE id = 405 AND codigo = '2014';
UPDATE imovel_conhecimento SET assunto = 'venda', atualizado_em = now() WHERE id = 716 AND codigo = '2014';
UPDATE imovel_conhecimento SET assunto = 'esquina', texto = 'A casa não é de esquina, mas fica quase na esquina.', atualizado_em = now() WHERE id = 699 AND codigo = '2120';
DELETE FROM imovel_conhecimento WHERE id = 543 AND codigo = '2462';     -- "R$ 6.800": o dono disse R$ 7.000 em 28/10
UPDATE imovel_conhecimento SET assunto = 'incluso_no_aluguel', atualizado_em = now() WHERE id = 706 AND codigo = '2462';
UPDATE imovel_conhecimento SET texto = regexp_replace(texto, '\s*Valor de venda dito:.*$', ''), atualizado_em = now() WHERE id = 544 AND codigo = '2462';
UPDATE imovel_conhecimento SET assunto = 'taxa_condominio', atualizado_em = now() WHERE id = 697 AND codigo = '4161';
UPDATE imovel_conhecimento SET assunto = 'quintal', atualizado_em = now() WHERE id = 691 AND codigo = '5709';
UPDATE imovel_conhecimento SET assunto = 'piscina', atualizado_em = now() WHERE id = 692 AND codigo = '9043';
UPDATE imovel_conhecimento SET assunto = 'finalidade', atualizado_em = now() WHERE id = 707 AND codigo = '9064';
UPDATE imovel_conhecimento SET assunto = 'contrato_minimo', atualizado_em = now() WHERE id = 723 AND codigo = '3078';
UPDATE imovel_conhecimento SET assunto = 'acesso_e_pe_direito', atualizado_em = now() WHERE id = 693 AND codigo = '5752';
UPDATE imovel_conhecimento SET assunto = 'localizacao', texto = 'O Conquista Tarumã fica entrando na Av. do Setur, no final.', atualizado_em = now() WHERE id = 419 AND codigo = '5722';
UPDATE imovel_conhecimento SET assunto = 'andar', texto = 'Fica no 2º andar.', atualizado_em = now() WHERE id = 408 AND codigo = '5758';
UPDATE imovel_conhecimento SET assunto = 'financiamento', texto = 'Não é por contrato de gaveta. Pode ser à vista ou financiado pelo banco com que o comprador tem relacionamento.', atualizado_em = now() WHERE id = 724 AND codigo = '5741';

-- 3. o que não é do imóvel
DELETE FROM imovel_conhecimento WHERE (id, codigo) IN (
  (688, '293'),    -- "Fala que a gente vai ver via WhatsApp ... manda o WhatsApp dele": recado do Tel
  (738, '1818'),   -- "Segue o vídeo do apartamento."
  (670, '2024'),   -- "O restante dos documentos que pedimos Ele enviou?": recado de fechamento
  (705, '2108'),   -- "O proprietário mencionou o valor de R$ 1.200.000": negociação (a ficha diz R$ 1.500.000)
  (689, '2462'),   -- "chegou"
  (413, '2659'),   -- fala do corretor, não do dono
  (667, '2944'),   -- "Preciso do locatário para fazer a análise dele": checklist
  (674, '3166'),   -- checklist
  (673, '4207'),   -- "das partes check list completo do locador"
  (412, '5001'),   -- "Lily, o Acácias está de 175.000": nome de corretora e valor que a ficha não confirma
  (414, '5707'),   -- "Já foi alugada a casa" para a pergunta do nome da rua (a ficha é de venda e está fora do mercado)
  (715, '5447'),   -- a rua e o número do Weck: ao corretor só bairro e condomínio
  (698, '5721'),   -- repete o 'venda' de 28/10
  (668, '5722'),   -- "Qual o valor do aluguei ?"
  (669, '5722'),   -- "Excelente"
  (729, '5725'),   -- a transferência que não foi feita: situação legal do dono, não é para repetir a corretor
  (421, '5727'),   -- "Nao" (a chave? sem sentido sozinho)
  (360, '5728'),   -- mobília "não": contradiz a ficha (com modulados e ar)
  (422, '5741'),   -- quitação "Não", solto
  (617, '5699'),   -- repete a 'portaria'
  (708, '5668'),   -- repete o 'habite_se' e a 'entrada'
  (416, '9027'),   -- o andar do Florence Garden (outro imóvel) guardado no 9027, que é só venda
  (725, '9051'),   -- "Sr. ..., seguem as fotos": recado com nome de cliente
  (720, '9058'),   -- repete a 'descricao_interna' (12º andar) e o 'iptu'
  (731, '9060'),   -- repete a 'escada'
  (719, '9064')    -- a faixa de preço que o dono aceita: negociação
);

COMMIT;
