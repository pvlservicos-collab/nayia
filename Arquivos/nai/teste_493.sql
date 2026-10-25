SELECT nay_leads_perguntar_ao_dono(1, '5592987123456', 'Ana', 'Olá, Ana! O imóvel aceita pet?') AS id1;
SELECT nay_leads_perguntar_ao_dono(1, '92987123456', 'Ana', 'Olá, Ana! O imóvel aceita pet?') AS id_igual;
SELECT telefone, nome, estado, linha FROM privado.nay_leads_dono_pergunta;
DO $$ BEGIN PERFORM nay_leads_perguntar_ao_dono(1, '123', NULL, 'x'); RAISE EXCEPTION 'devia recusar';
EXCEPTION WHEN raise_exception THEN IF SQLERRM = 'devia recusar' THEN RAISE; END IF; RAISE NOTICE 'recusou: %', SQLERRM; END $$;
