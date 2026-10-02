-- O CABECALHO do turno: quem escreveu, em que papel, qual visita, qual memoria.
SELECT nai_abrir_turno($1, $2, $3, $4, ARRAY(SELECT jsonb_array_elements_text($5::jsonb)::bigint)) AS cab;
