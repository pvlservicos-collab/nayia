SELECT pg_get_constraintdef(oid) FROM pg_constraint WHERE conname IN ('olx_visita_estado_check','olx_visita_consulta_estado_check');
