-- 442 (Pedro, 20/10/2026): "em editar imóvel, nessa parte da unidade ... casa de condomínio colocando o nome ou número da
-- rua". A rua de dentro do condomínio (nome ou número) mora com o resto da unidade (torre, bloco, apartamento, casa,
-- lote) em imovel_privado: nunca sai para o cliente. Coluna nova, sem valor padrão (não reescreve a tabela; a trava
-- dura um instante e desiste em 3 s se alguém estiver usando).
BEGIN;
SET LOCAL lock_timeout = '3s';
ALTER TABLE public.imovel_privado ADD COLUMN IF NOT EXISTS rua text;
COMMENT ON COLUMN public.imovel_privado.rua IS
  '442: a rua da casa dentro do condomínio (nome ou número), do Editar imóvel. Uso interno, como torre/bloco/casa/lote.';
GRANT INSERT (rua), SELECT (rua), UPDATE (rua) ON public.imovel_privado TO nay_site_escrita;
COMMIT;
