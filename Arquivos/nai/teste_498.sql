-- teste da 498 (dentro da transação do ensaio, antes do ROLLBACK)
SELECT privado.biblioteca_gravar('{"nay": "parceria", "ref": "2026-10-23/4318-05956a", "dia": "2026-10-23", "tel4": "4318",
  "resultado": "erro", "confianca": "revisão", "nota": 80, "fontes": ["revisao_gemini", "nota_automatica"],
  "marcas": [{"fonte": "revisao_gemini", "resultado": "erro", "resumo": "loop no horário da visita",
              "erros": [{"tipo": "visita", "o_que_aconteceu": "perguntou o horário 3x"}]}],
  "texto": "10:51 Corretor: Visita amanhã às 10.30"}'::jsonb) > 0 AS gravou;
SELECT privado.biblioteca_gravar('{"nay": "parceria", "ref": "2026-10-23/4318-05956a", "dia": "2026-10-23", "tel4": "4318",
  "resultado": "erro", "confianca": "humano", "fontes": ["pedro_chat"], "marcas": []}'::jsonb) > 0 AS atualizou;
SELECT (site_biblioteca('{"busca": "4318"}')->>'total')::int AS achou, site_biblioteca('{}')->'por_nay' AS por_nay;
SELECT x->>'confianca' AS confianca, x->>'resumo' AS resumo, x->'tipos' AS tipos
  FROM jsonb_array_elements(site_biblioteca('{"tel4": "4318"}')->'linhas') x LIMIT 1;
SELECT site_biblioteca_conversa((SELECT id FROM privado.conversa_biblioteca WHERE ref = '2026-10-23/4318-05956a'))->>'texto' AS texto;
