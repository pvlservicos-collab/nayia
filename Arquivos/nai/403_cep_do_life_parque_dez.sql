-- 403 -- O CEP do Life Parque Dez (o 5739 não subia para a OLX)
--
-- Pedro, 17/10/2026: "esse imóvel aqui não consigo anunciar, diz que é sem valor ... Imóvel 5739 · Life Parque Dez".
-- O "sem valor" era a aba VENDA (o 5739 é só aluguel, R$ 5.878) -- o popup abria nela quando nenhum lado estava pronto.
-- O que barrava a LOCAÇÃO era o CEP: nem o imóvel nem a ficha do condomínio tinham. Pelo ViaCEP (Correios), Avenida
-- Tancredo Neves "de 861 a 1077 - lado ímpar" = 69058-120, e o número do condomínio é 877 (os 12 imóveis dele dizem 877).
-- Vai na ficha (id 419, condomínio 28), como no 366/368/376, e vale para todo imóvel de lá sem CEP próprio.
-- De fora: 2148 e 707 têm "69055-000" no imóvel (CEP geral, não é o da avenida); o do imóvel vence o da ficha.
BEGIN;
SET LOCAL lock_timeout = '3s';
UPDATE condominio_ficha
   SET cep = '69058-120', numero = coalesce(nullif(btrim(numero), ''), '877'), atualizado_em = now()
 WHERE id = 419 AND condominio_id = 28 AND coalesce(regexp_replace(cep, '\D', '', 'g'), '') !~ '^[0-9]{8}$';
COMMIT;
