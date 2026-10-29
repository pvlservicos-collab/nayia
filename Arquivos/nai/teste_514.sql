SELECT aprendizado_gravar('{"video": {"youtube_id": "teste514xx", "titulo": "Vídeo de teste", "quem": "x", "data": "2026-10-28"},
  "ideias": [{"numero": 9001, "titulo": "Ideia A", "area": "Marketing", "prazo": "curto", "nota_claude": 93, "sugestao": "- a"},
             {"numero": 9002, "titulo": "Ideia B", "prazo": "longo", "nota_claude": 40, "sugestao": "- b"}]}') AS primeira;
SELECT id AS ida FROM aprendizado_ideia WHERE numero = 9001 \gset
SET ROLE nay_site_escrita;
SELECT site_aprendizado_ideia_nota(:ida, 55, 'teste') AS barrinha;
SELECT jsonb_array_length(site_aprendizado_ideias()->'ideias') AS ideias_no_site,
       site_aprendizado_ideias()->'videos'->0->>'ideias' AS do_video;
RESET ROLE;
SET ROLE nay_site_leitura;
SELECT jsonb_array_length(site_aprendizado_ideias()->'ideias') AS leitura_le;
RESET ROLE;
-- a rotina roda de novo: o texto muda, a nota que o Pedro deu fica; a que ele não mexeu acompanha a nota_claude
SELECT aprendizado_gravar('{"ideias": [{"numero": 9001, "youtube_id": "teste514xx", "titulo": "Ideia A2", "prazo": "medio", "nota_claude": 80},
                                       {"numero": 9002, "youtube_id": "teste514xx", "titulo": "Ideia B", "prazo": "longo", "nota_claude": 45}]}') AS segunda;
SELECT numero, titulo, prazo, nota, nota_claude, nota_revisada, nota_por FROM aprendizado_ideia ORDER BY numero;
SELECT site_aprendizado_ideia_nota(:ida, 101, 'teste');
