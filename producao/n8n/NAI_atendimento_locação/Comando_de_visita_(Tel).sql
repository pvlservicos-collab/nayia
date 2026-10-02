-- VISITAS / VISITA <id> OK|CANCELA|HORARIO|AVISA|FERNANDO OK / ACESSO <codigo> <como>
SELECT * FROM nai_comando_tel($1::bigint, $2);
