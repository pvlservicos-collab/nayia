# Nay- recebe mensagem  (id sQuiEjbEDMEbjX5U, atualizado em 2026-10-02 03:31)

nó | tipo | modelo/extra | vai para
---|---|---|---
Webhook | webhook |  | NAI ou Nay? (quem atende)
NAI ou Nay? (quem atende) | postgres | onError=continueRegularOutput | Vai para a NAI?
Filtrar e normalizar | code |  | Gravar na fila
Vai para a NAI? | if |  | Mandar para a NAI, Filtrar e normalizar
Gravar na fila | postgres |  | Janela de 25s
Mandar para a NAI | httpRequest | onError=continueErrorOutput | Prazo estourado? (a NAI recebeu)
Janela de 25s | wait |  | Reservar mensagens
Reservar mensagens | postgres |  | Juntar mensagens, Detectar audio
Prazo estourado? (a NAI recebeu) | if |  | Filtrar e normalizar
Detectar audio | code |  | Baixar audio
Juntar mensagens | code |  | Achar codigo, Rotear para o agente, Comando do Tel
Transcrever | openAi |  | Juntar mensagens
Achar codigo | code |  | Buscar imovel
Buscar imovel | postgres |  | Montar mensagem
Rotear para o agente | code |  | AI Agent
Montar mensagem | code |  | Buscar fotos
Comando do Tel | code |  | Responder pendencia
Baixar audio | httpRequest |  | Transcrever
OpenAI Chat Model | lmChatOpenAi | gpt-6-luna | AI Agent [ai_languageModel]
Buscar fotos | postgres |  | Preparar envio
Postgres Chat Memory | memoryPostgresChat |  | AI Agent [ai_memory]
Responder pendencia | postgres |  | Preparar aviso do comando
como_funciona_a_visita | postgresTool |  | AI Agent [ai_tool]
disponibilidade_no_condominio | postgresTool |  | AI Agent [ai_tool]
Preparar envio | code |  | Loop fotos
AI Agent | agent |  | Achar codigo na resposta
o_que_sei_do_imovel | postgresTool |  | AI Agent [ai_tool]
guardar_do_imovel | postgresTool |  | AI Agent [ai_tool]
listar_no_condominio | postgresTool |  | AI Agent [ai_tool]
guardar_como_funciona_a_visita | postgresTool |  | AI Agent [ai_tool]
Achar codigo na resposta | code |  | Buscar fotos do agente
avaliar_visita | postgresTool |  | AI Agent [ai_tool]
guardar_dados_do_corretor | postgresTool |  | AI Agent [ai_tool]
resumo_do_condominio | postgresTool |  | AI Agent [ai_tool]
Buscar fotos do agente | postgres |  | Preparar envio do agente
buscar_por_perfil | postgresTool |  | AI Agent [ai_tool]
dados_do_corretor | postgresTool |  | AI Agent [ai_tool]
Preparar envio do agente | code |  | Loop fotos
imovel_por_codigo | postgresTool |  | AI Agent [ai_tool]
escalar_ao_tel | toolWorkflow |  | AI Agent [ai_tool]
responder_pendencia | toolWorkflow |  | AI Agent [ai_tool]
Loop fotos | splitInBatches |  | Preparar registro, Pausa
Preparar aviso do comando | code |  | Enviar Z-API
guardar_retorno | postgresTool |  | AI Agent [ai_tool]
Pausa | wait |  | Enviar Z-API
imovel_do_disparo | postgresTool |  | AI Agent [ai_tool]
Preparar registro | code |  | Registrar envio
Enviar Z-API | httpRequest |  | Registrar saida
o_que_ficou_de_enviar | postgresTool |  | AI Agent [ai_tool]
ficou_devendo | postgresTool |  | AI Agent [ai_tool]
Registrar envio | postgres |  | 
Registrar saida | postgres | onError=continueRegularOutput | Loop fotos
Listar condominios | postgres |  | Achar condominio
Achar condominio | code |  | Buscar no condominio
Buscar no condominio | postgres |  | Montar lista
Montar lista | code |  | Enviar lista
Enviar lista | httpRequest |  | Fechar ciclo
Fechar ciclo | postgres |  | 
