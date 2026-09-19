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

CREATE OR REPLACE FUNCTION nay_sincronizar_nome(p_telefone text, p_nome text)
RETURNS void
LANGUAGE plpgsql AS $fn$
DECLARE
  v_tel  text := regexp_replace(coalesce(p_telefone,''),'[^0-9]','','g');
  v_nome text := btrim(coalesce(p_nome,''));
BEGIN
  -- Nome vazio, ou que é só o próprio número (a Z-API manda assim quando
  -- não tem contato salvo), não serve para nada.
  IF v_nome = '' OR v_nome ~ '^\+?[0-9@ .-]+$' OR length(v_nome) < 2 THEN
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
WITH ultimo AS (
  SELECT DISTINCT ON (right(regexp_replace(telefone,'[^0-9]','','g'),8))
         right(regexp_replace(telefone,'[^0-9]','','g'),8) AS fim,
         nome
    FROM mensagens
   WHERE coalesce(nome,'') <> ''
     AND nome !~ '^\+?[0-9@ .-]+$'
   ORDER BY right(regexp_replace(telefone,'[^0-9]','','g'),8), id DESC
)
UPDATE corretores c
   SET nome = u.nome, nome_origem = 'whatsapp', nome_visto_em = now()
  FROM ultimo u
 WHERE right(regexp_replace(c.telefone,'[^0-9]','','g'),8) = u.fim
   AND coalesce(c.nome_origem,'') <> 'manual'
   AND coalesce(c.nome,'') IS DISTINCT FROM u.nome;
