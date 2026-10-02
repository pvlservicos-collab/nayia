-- As fotos do turno viram fotos da ficha aberta. Sem ficha aberta,
-- devolve 0 e nada acontece.
SELECT nai_sec_guardar_fotos_do_turno($1::bigint) AS n;
