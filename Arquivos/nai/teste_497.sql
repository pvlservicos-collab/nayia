SELECT origem, count(*), min(quando)::date, max(quando)::date, count(*) FILTER (WHERE com_motoboy) AS com_motoboy
  FROM nay_agenda_de_visitas(now() - interval '7 days', now() + interval '14 days') GROUP BY 1;
SET ROLE nay_core;
SELECT count(*) AS como_o_core FROM nay_agenda_de_visitas(now() - interval '7 days', now() + interval '14 days');
RESET ROLE;
