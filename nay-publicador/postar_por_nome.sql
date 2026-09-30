-- POSTAR PELO NOME DO CONDOMÍNIO (Tel, 15/09).
--
-- A conversa que fez isto existir:
--
--   Tel:  Posta o jardim das cerejeiras
--   Nay:  Não entendi o comando "Posta o jardim das cerejeiras". Exemplos
--         que eu reconheço: "posta o 5750", ...
--
-- Literal dele: *"eu nunca lembro por código e preciso que neste caso quando
-- eu pedir pelo nome do condomínio, ela procure e me pergunte se é para venda
-- ou locação"*. E: *"se estiver mais de uma opção ela vai me mandar o jardim
-- das cerejeiras com o valor e código para eu decidir e respondo com ela pelo
-- valor ou código que ela me enviou"*.
--
-- POR QUE PRECISA DE ESTADO: a resposta dele é "locação", "5725" ou "3.6k" --
-- palavras que sozinhas não dizem nada. Sem a pergunta guardada, "locação"
-- não tem como virar postagem em 14 grupos (e não pode mesmo virar, se não
-- houver pergunta aberta).
--
-- REAPROVEITA `pergunta_ao_tel`, que já existe para o "sim" do repostar_easy:
-- é o mesmo conceito (uma pergunta aberta por vez, com janela), e é a mesma
-- linha que o `nay_pergunta_aberta_do_tel()` -- lido no `Reservar mensagens`
-- -- usa para deixar a resposta curta virar comando em vez de ir ao agente.
--
--   docker cp postar_por_nome.sql nay-postgres:/tmp/pn.sql
--   docker exec nay-postgres psql -U nay -d naydb -v ON_ERROR_STOP=1 -f /tmp/pn.sql

-- Os códigos que ela ofereceu. A resposta dele só pode escolher DENTRO desta
-- lista -- "5725" com outro imóvel na cabeça não posta o que ela não ofereceu.
ALTER TABLE pergunta_ao_tel ADD COLUMN IF NOT EXISTS candidatos text[] NOT NULL DEFAULT '{}';
-- O nome como ele escreveu, para a resposta dela citar de volta.
ALTER TABLE pergunta_ao_tel ADD COLUMN IF NOT EXISTS nome text;
-- 'venda' / 'locacao' quando ele JÁ disse -- aí a pergunta é só qual imóvel.
ALTER TABLE pergunta_ao_tel ADD COLUMN IF NOT EXISTS negocio text;
