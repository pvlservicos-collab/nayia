-- teste da 464: os cards das visitas de hoje e dos próximos dias
\timing on
SELECT c->>'texto' AS card FROM visitas_cards(now() - interval '12 hours', now() + interval '3 days') c;
SELECT jsonb_pretty(visita_card((SELECT id FROM nai_visita WHERE excluida_em IS NULL ORDER BY quando DESC LIMIT 1)));
