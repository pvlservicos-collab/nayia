-- Migração: coluna `administrado` e marcação dos dois imóveis geridos
-- pela Imob Easy.
--
-- Motivo: a regra 4 (endereço) só pode funcionar direito com uma
-- marcação explícita no banco. Sem ela, a Nay trata TODO imóvel como
-- não-administrado e nunca passa a rua — mais seguro, mas errado para
-- os administrados. Com a coluna, a consulta decide o que mostrar por
-- dado, não por pedido no prompt.
--
-- Rodar no servidor:
--   docker exec nay-postgres psql -U nay -d naydb -f /tmp/administrado.sql
--
-- O que cada bloco faz:
--   1. Cria a coluna (idempotente — IF NOT EXISTS)
--   2. Proíbe parceiro + administrado no mesmo imóvel (CHECK)
--   3. Marca os dois confirmados pelo Tel em 29/08
--   4. Atualiza a regra 4 para referenciar a coluna
--   5. Insere regra de caução (varia por imóvel, escala ao Tel)
--   6. Verificação final

BEGIN;

-- 1) coluna
ALTER TABLE imoveis
  ADD COLUMN IF NOT EXISTS administrado boolean NOT NULL DEFAULT false;

-- 2) guarda: parceiro e administrado nunca coexistem.
-- Se a varredura do site marcar um administrado como parceiro, o UPDATE
-- falha em vez de silenciosamente apagar a marcação de administrado.
-- O nome da constraint é fixo para que o IF NOT EXISTS funcione.
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint WHERE conname = 'chk_parceiro_nao_administrado'
  ) THEN
    ALTER TABLE imoveis
      ADD CONSTRAINT chk_parceiro_nao_administrado
      CHECK (NOT (e_parceiro AND administrado));
  END IF;
END $$;

-- 3) marca os dois administrados confirmados (29/08/2026)
--    1327 = Casa Nova Cidade (Av. Curaçao), aluguel 2.500
--    4098 = Flex Parque Dez (Rua Misushiro), aluguel 3.100
UPDATE imoveis SET administrado = true, sincronizado_em = now()
  WHERE codigo = '1327' AND e_parceiro = false;

UPDATE imoveis SET administrado = true, sincronizado_em = now()
  WHERE codigo = '4098' AND e_parceiro = false;

-- 4) atualiza a regra 4 (endereço) — remove a exceção inerte
UPDATE regras SET
  texto = 'NÃO passe logradouro, rua nem número de NENHUM imóvel — EXCETO os marcados como administrado na consulta. Para esses, o endereço já vem na resposta da ferramenta; passe o que veio, menos a unidade.'
WHERE contexto = 'endereco'
  AND texto LIKE '%imóveis que a Imob Easy ADMINISTRA%';

-- 5) regra de caução — varia por imóvel, Nay não calcula
INSERT INTO regras (texto, contexto, ativa) VALUES (
  'Quando o corretor perguntar quanto precisa para entrar no imóvel, NÃO calcule o valor — o número de cauções varia por imóvel. Responda que vai verificar e escale ao Tel.',
  'locacao',
  true
);

COMMIT;

-- 6) verificação (fora da transação, só leitura)
SELECT codigo, condominio_nome, logradouro, e_parceiro, administrado,
       valor_aluguel
FROM imoveis WHERE administrado = true;

SELECT id, contexto, texto FROM regras WHERE ativa ORDER BY id;
