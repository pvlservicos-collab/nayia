-- 475d: uma busca por mensagem nos grupos (Tel, 22/10): o intervalo entre mensagens no mesmo grupo cai de 120 para 15 min
BEGIN;
UPDATE privado.olx_config SET valor = '15', atualizado_em = now() WHERE chave = 'busca_grupos_intervalo_min';
COMMIT;
