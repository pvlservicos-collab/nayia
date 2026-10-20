\pset pager off
-- o que o checklist veria (as visitas desta semana que a Nay passou à Rayssa; a janela no ensaio é a da função)
SELECT visita_id, codigo, imovel, to_char(quando, 'DD/MM HH24:MI') quando, corretor, dono_nome, dono, dono_respondeu,
       moto_nome, moto, moto_respondeu
  FROM privado.visitas_parceria_situacao() ORDER BY visita_id;
SELECT count(*) AS ja_marcadas FROM privado.visita_parceria_grupo;
SELECT * FROM privado.visitas_parceria_sem_visita();
