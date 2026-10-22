-- teste da 463 (dentro do ensaio)
SELECT count(*) AS na_lista, count(*) FILTER (WHERE nome IS NULL) AS sem_nome FROM nay_proprietario_bloqueio;
SELECT k.id, k.nome_whatsapp, k.nome_completo, nai_e_proprietario_contato(k.id) AS dono, nay_vocativo_dono(coalesce(k.nome_completo, k.nome_whatsapp)) AS chama
  FROM nai_contato k WHERE k.id = 15999;
SELECT x, nay_vocativo_dono(x) FROM unnest(ARRAY['DOS','Dunhellington Souza','JR Imoveis','ANA PAULA','Nicole Benchaya e esposo Felipe','💰Bacelar💰','5592993185882']) x;
SELECT count(*) AS nomes_postos FROM privado.nai_contato_nome_antes_463;
-- um corretor de verdade continua não sendo dono
SELECT nai_e_proprietario_contato(k.id) AS corretor_e_dono FROM nai_contato k WHERE right(k.chave, 8) = '93214318' LIMIT 1;
