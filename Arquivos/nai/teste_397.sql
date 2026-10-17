SELECT count(*) FROM crm_donos_do_cadastro(ARRAY['88542400','99154084','00000000']);
SELECT has_function_privilege('nay_disparo', 'crm_donos_do_cadastro(text[])', 'EXECUTE');
