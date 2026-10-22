-- 475c: as 2 ordens de busca que o caminho antigo (Chrome do PC) nunca rodou (sem_navegador: o PC estava desligado) passam
-- ao fluxo novo (475), ativadas: a do lead 17 (casa de condomínio à venda no Parque 10, 3 quartos, 20/10) e a do lead 45
-- (busca manual do CRM, apartamento à venda até R$ 750 mil, Parque 10/Aleixo/Adrianópolis/N. Sra. das Graças, 22/10).

BEGIN;
UPDATE privado.olx_busca_parceiro SET estado = 'cancelado', atualizado_em = now() WHERE id IN (3, 6) AND estado = 'sem_navegador';
UPDATE privado.busca_cliente SET estado = 'buscando', ativada_em = now(), motivo = 'ordem antiga que o Chrome do PC não rodou',
       atualizado_em = now()
 WHERE lead IN (17, 45) AND estado = 'perfil';
INSERT INTO privado.busca_cliente_passo (busca, lugar, texto)
SELECT id, 'equipe', 'Busca ativada: a ordem antiga (pelo Chrome do PC) não tinha rodado; agora vai aos grupos e à OLX'
  FROM privado.busca_cliente WHERE lead IN (17, 45) AND estado = 'buscando';
COMMIT;
