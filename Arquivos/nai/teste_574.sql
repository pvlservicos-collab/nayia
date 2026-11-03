-- 574: o Chat Zap lê os leads do ZAP como conversas
SELECT jsonb_array_length(crm_zap_chats()) AS conversas, crm_zap_chats()->0->>'chave' AS chave, crm_zap_chats()->0->>'naoLidas' AS nao_lidas;
SELECT jsonb_array_length(crm_zap_conversa('t99999999')) AS leads_do_teste;
SELECT p->'leads' AS leads, jsonb_array_length(p->'anuncios') AS no_cadastro, p->'senhaGuardada' AS senha, p->'naySim' AS nay
  FROM crm_zap_painel() p;
SELECT crm_zap_ler('t99999999') AS lidos_agora;
SELECT zap_portal('VivaReal'), zap_portal('Grupo OLX'), zap_portal('OLX'), zap_negocio('SELL'), zap_negocio('RENT');
SELECT has_function_privilege('nay_disparo', 'crm_zap_chats()', 'EXECUTE') AS crm_le,
       has_function_privilege('nay_site_leitura', 'crm_zap_ler(text)', 'EXECUTE') AS site_nao_pode;
