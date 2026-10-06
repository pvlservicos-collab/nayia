-- dentro do ensaio (ROLLBACK no fim): o "Me envia" do site para um número que não existe
SELECT site_me_envia('92900000001', ARRAY[9020], 'ensaio-298') ->> 'mensagem' AS retorno;
SELECT s.ordem, s.tipo, s.motivo, left(regexp_replace(coalesce(s.texto, ''), '\s+', ' ', 'g'), 70) AS comeco
  FROM nai_saida s JOIN nai_contato k ON k.id = s.contato_id
 WHERE right(regexp_replace(k.telefone, '\D', '', 'g'), 8) = '00000001' ORDER BY s.ordem LIMIT 6;
SELECT count(*) FILTER (WHERE s.texto ILIKE '%fiquei de te enviar%') AS com_a_frase, count(*) AS mensagens
  FROM nai_saida s JOIN nai_contato k ON k.id = s.contato_id
 WHERE right(regexp_replace(k.telefone, '\D', '', 'g'), 8) = '00000001';
