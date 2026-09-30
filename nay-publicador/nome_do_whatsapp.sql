-- O nome do corretor vem do WhatsApp sozinho, e fica sincronizado.
--
-- O PROBLEMA (31/08): 1.050 corretores cadastrados e só 75 com nome. O
-- Ênio recebeu dois imóveis e a confirmação saiu como "mandei para
-- 559292760556", porque `corretores.nome` estava vazio -- enquanto
-- `mensagens.nome` tinha "Ênio Cruz .•." desde a primeira mensagem dele.
-- O dado sempre esteve lá, só nunca foi copiado.
--
-- Sem nome, o comando "Nay manda o 5750 pro Ênio" também não funciona: a
-- resolução por nome não acha ninguém e o Tel tem que digitar o telefone.
--
-- POR QUE SINCRONIZAR SEMPRE, e não uma vez: o corretor troca o nome do
-- perfil, casa, muda de sobrenome, acrescenta "Corretor" ao lado. O nome
-- que importa é o que ele usa HOJE.
--
-- O QUE NÃO SE SOBRESCREVE: nome que o Tel digitou à mão. Se ele
-- cadastrou "Fernando acompanhante", o WhatsApp não pode trocar por
-- "Ferzinho 🏠". A coluna `nome_origem` separa os dois.
--
--   docker cp nome_do_whatsapp.sql nay-postgres:/tmp/nw.sql
--   docker exec nay-postgres psql -U nay -d naydb -f /tmp/nw.sql

ALTER TABLE corretores
  ADD COLUMN IF NOT EXISTS nome_origem text,
  ADD COLUMN IF NOT EXISTS nome_visto_em timestamptz;

-- Quem já tem nome e nunca foi marcado veio do Tel ou do histórico: trata
-- como manual, para a sincronização não passar por cima.
UPDATE corretores SET nome_origem = 'manual'
 WHERE coalesce(nome,'') <> '' AND nome_origem IS NULL;

-- O NOME DA NOSSA PRÓPRIA CONTA NÃO É NOME DE CORRETOR (14/09).
--
-- Desde 12/09 as mensagens que a Nay ENVIA também são gravadas em `mensagens`
-- (direcao='enviada'), e a Z-API manda nelas o `senderName` da conta que
-- enviou: "Nay Mendes". O `Gravar na fila` chama esta função para TODA
-- mensagem, sem olhar a direção -- então cada card que a Nay mandava a um
-- corretor renomeava o corretor para "Nay Mendes". Medido em 14/09: 8
-- corretores, entre eles a Renata, a Marlúcia e a Amanda das visitas, e a
-- Flávia uma hora depois de cadastrada. A frase de cortesia do envio sairia
-- "Nay, segue as opções que fiquei de te enviar".
--
-- A causa raiz está no nó (o parâmetro `$6`, "saindo", existe e não é lido
-- na chamada). A parede mora AQUI também, e de propósito: o nome da nossa
-- conta nunca é nome de corretor, venha a chamada de onde vier -- e esta
-- parede vale sem reiniciar o n8n. O nome fica em `config`, porque a conta
-- pode trocar de nome no WhatsApp.
INSERT INTO config (chave, valor) VALUES ('nome_da_conta_whatsapp', 'Nay Mendes')
  ON CONFLICT (chave) DO NOTHING;

CREATE OR REPLACE FUNCTION nay_sincronizar_nome(p_telefone text, p_nome text)
RETURNS void
LANGUAGE plpgsql AS $fn$
DECLARE
  v_tel  text := regexp_replace(coalesce(p_telefone,''),'[^0-9]','','g');
  v_nome text := btrim(coalesce(p_nome,''));
  v_conta text := btrim(coalesce(
    (SELECT valor FROM config WHERE chave = 'nome_da_conta_whatsapp'), ''));
BEGIN
  -- Nome vazio, ou que é só o próprio número (a Z-API manda assim quando
  -- não tem contato salvo), não serve para nada.
  IF v_nome = '' OR v_nome ~ '^\+?[0-9@ .-]+$' OR length(v_nome) < 2 THEN
    RETURN;
  END IF;

  -- O nome da conta que ENVIOU: é a Nay falando, não o corretor.
  IF v_conta <> '' AND lower(v_nome) = lower(v_conta) THEN
    RETURN;
  END IF;

  UPDATE corretores c
     SET nome = v_nome,
         nome_origem = 'whatsapp',
         nome_visto_em = now()
   WHERE right(regexp_replace(c.telefone,'[^0-9]','','g'),8) = right(v_tel,8)
     AND coalesce(c.nome_origem,'whatsapp') <> 'manual'   -- não pisa no do Tel
     AND coalesce(c.nome,'') IS DISTINCT FROM v_nome;     -- só quando mudou
END;
$fn$;

-- Preenche de uma vez com o que o histórico já tem, pegando o nome MAIS
-- RECENTE de cada telefone.
--
-- SÓ DE MENSAGEM RECEBIDA (14/09). Sem o filtro, rodar este arquivo depois de
-- 12/09 renomearia para "Nay Mendes" TODO corretor que já recebeu mensagem
-- dela -- a última linha de cada telefone é, quase sempre, a nossa. É também
-- o que conserta os 8 que a função já tinha renomeado.
WITH ultimo AS (
  SELECT DISTINCT ON (right(regexp_replace(telefone,'[^0-9]','','g'),8))
         right(regexp_replace(telefone,'[^0-9]','','g'),8) AS fim,
         nome
    FROM mensagens
   WHERE direcao = 'recebida'
     AND coalesce(nome,'') <> ''
     AND lower(btrim(nome)) IS DISTINCT FROM lower(btrim(coalesce(
           (SELECT valor FROM config WHERE chave = 'nome_da_conta_whatsapp'), '')))
     AND nome !~ '^\+?[0-9@ .-]+$'
     -- nome sem nenhuma letra ("💫") não diz quem é
     AND nome ~ '[[:alpha:]]'
   ORDER BY right(regexp_replace(telefone,'[^0-9]','','g'),8), id DESC
)
UPDATE corretores c
   SET nome = u.nome, nome_origem = 'whatsapp', nome_visto_em = now()
  FROM ultimo u
 WHERE right(regexp_replace(c.telefone,'[^0-9]','','g'),8) = u.fim
   AND coalesce(c.nome_origem,'') <> 'manual'
   AND coalesce(c.nome,'') IS DISTINCT FROM u.nome
   -- SÓ COMPLETA O VAZIO E DESFAZ O NOME DA CONTA. Medido em 14/09: sem esta
   -- linha, rodar o arquivo renomeava os três números de teste interno, que
   -- têm o rótulo "(numero de teste interno -- nao atender)" -- e o rótulo é o
   -- aviso. Nome que já existe continua sendo trocado pela sincronização de
   -- cada mensagem, não por este preenchimento de uma vez.
   AND (coalesce(btrim(c.nome),'') = ''
        OR lower(btrim(c.nome)) = lower(btrim(coalesce(
             (SELECT valor FROM config WHERE chave = 'nome_da_conta_whatsapp'), ''))));
