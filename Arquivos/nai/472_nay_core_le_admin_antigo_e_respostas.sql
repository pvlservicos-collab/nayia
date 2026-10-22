-- 472 -- O nay-core lê o andar do admin antigo e o que o Tel já respondeu sobre o imóvel
--
-- Pedro, 22/10/2026 (Everton B. Teixeira, 5727 Mirante das Flores, "Qual o andar?" subiu ao Tel): "pede para a IA antes
-- de me perguntar verificar se não tem nenhuma informação do imóvel ... se for código antigo pede para ver no site antigo
-- também ... a nay tá perguntando muita informação que já tem". A unidade 1101 (11º andar) estava em imovel_privado e a
-- resposta do Tel a perguntas iguais fica em imovel_conhecimento, que o núcleo não lia.
-- O nay-core (nay/cerebro/repo.py, ficha) passa a juntar essas fontes; o papel nay_core só lê as colunas de que precisa:
-- nada de locatário, contato ou observação do admin antigo.
BEGIN;
SET LOCAL lock_timeout = '3s';
GRANT SELECT (codigo, andar, apartamento) ON public.imoveis_admin_detalhe TO nay_core;
GRANT SELECT (codigo, assunto, texto, atualizado_em) ON public.imovel_conhecimento TO nay_core;
COMMIT;
