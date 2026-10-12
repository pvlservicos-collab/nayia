# NAI atendimento locação  (id NaiAtendLocacao1, atualizado em 2026-10-12 14:09)

nó | tipo | modelo/extra | vai para
---|---|---|---
Webhook | webhook |  | Filtrar e normalizar, Espelhar no CRM
Espelhar no CRM | httpRequest | onError=continueRegularOutput | 
Filtrar e normalizar | code |  | Gravar na fila, Foi o Tel pelo celular?
📌 NAI atendimento locação | stickyNote |  | 
🧪 MODO TESTE | stickyNote |  | 
Foi o Tel pelo celular? | if |  | Espera 15s (eco)
Gravar na fila | postgres |  | Janela de 25s
Espera 15s (eco) | wait |  | O Tel assumiu a conversa
Janela de 25s | wait |  | Reservar mensagens
O Tel assumiu a conversa | postgres |  | 
Reservar mensagens | postgres |  | Juntar mensagens, Detectar audio, Detectar imagem
Juntar mensagens | code |  | Abrir turno
Detectar audio | code |  | Baixar audio
Detectar imagem | code |  | Baixar imagem
Baixar imagem | httpRequest | onError=continueRegularOutput | Montar leitura da imagem
Baixar audio | httpRequest | onError=continueRegularOutput | Transcrever
Abrir turno | postgres |  | Rotear pelo cabeçalho, Espelhar decisão
Montar leitura da imagem | code |  | Ler imagem (GPT)
Ler imagem (GPT) | httpRequest | onError=continueRegularOutput | Juntar mensagens
Transcrever | httpRequest | onError=continueRegularOutput | Juntar mensagens
Rotear pelo cabeçalho | code |  | Precisa da mente?
Espelhar decisão | httpRequest | onError=continueRegularOutput | 
Precisa da mente? | if |  | Ler estado, Qual caminho?
Qual caminho? | switch |  | NAI (corretor), Enfileirar card do código, Enfileirar cortesia, NAI (proprietário), NAI (Fernando), Comando de visita (Tel), Comando do Tel, Aviso no teste, Fotos do cadastro
GPT (corretor) | lmChatOpenAi | gpt-6-luna | NAI (corretor) [ai_languageModel]
Comando do Tel | code |  | Responder pendencia
Ler estado | postgres |  | Montar pergunta ao Jev
Montar pergunta ao Jev | code |  | Jev decide
Responder pendencia | postgres |  | Preparar aviso do comando
Fotos do cadastro | postgres |  | NAI (secretária)
Memória (corretor) | memoryPostgresChat |  | NAI (corretor) [ai_memory]
NAI (corretor) | agent |  | Achar codigo na resposta
GPT (secretária) | lmChatOpenAi | gpt-6-luna | NAI (secretária) [ai_languageModel]
responder_pendencia | toolWorkflow |  | NAI (corretor) [ai_tool]
GPT (Fernando) | lmChatOpenAi | gpt-6-luna | NAI (Fernando) [ai_languageModel]
imovel_por_codigo | postgresTool |  | NAI (corretor) [ai_tool]
GPT (proprietário) | lmChatOpenAi | gpt-6-luna | NAI (proprietário) [ai_languageModel]
Jev decide | httpRequest | onError=continueRegularOutput | Ler o Jev
imovel_do_disparo | postgresTool |  | NAI (corretor) [ai_tool]
NAI (Fernando) | agent |  | Resposta do Fernando
NAI (proprietário) | agent |  | Resposta do proprietário
Memória (secretária) | memoryPostgresChat |  | NAI (secretária) [ai_memory]
Memória (Fernando) | memoryPostgresChat |  | NAI (Fernando) [ai_memory]
Aviso no teste | postgres |  | Fechar turno
Memória (proprietário) | memoryPostgresChat |  | NAI (proprietário) [ai_memory]
Preparar aviso do comando | code |  | Enviar aviso do comando
Enfileirar card do código | postgres |  | Fechar turno
Enfileirar cortesia | postgres |  | Fechar turno
Comando de visita (Tel) | postgres |  | Fechar turno
Ler o Jev | code |  | Decidir quem responde
resumo_do_condominio | postgresTool |  | NAI (corretor) [ai_tool]
escalar_ao_tel | postgresTool |  | NAI (corretor) [ai_tool]
NAI (secretária) | agent |  | Resposta da secretária
Achar codigo na resposta | code |  | Fotos faltando?
consultar_o_que_sei | postgresTool |  | NAI (secretária) [ai_tool]
resposta_do_motoboy | postgresTool |  | NAI (Fernando) [ai_tool]
resposta_do_proprietario | postgresTool |  | NAI (proprietário) [ai_tool]
listar_no_condominio | postgresTool |  | NAI (corretor) [ai_tool]
dados_do_corretor | postgresTool |  | NAI (corretor) [ai_tool]
Resposta do Fernando | code |  | Enfileirar resposta
Decidir quem responde | postgres |  | Rota da mente
Resposta do proprietário | code |  | Enfileirar resposta
Fotos faltando? | postgres |  | Buscar fotos no site
perguntar_ao_tel | postgresTool |  | NAI (secretária) [ai_tool]
buscar_por_perfil | postgresTool |  | NAI (corretor) [ai_tool]
pedir_visita | postgresTool |  | NAI (corretor) [ai_tool]
Rota da mente | code |  | Qual caminho?
Enviar aviso do comando | httpRequest | onError=continueRegularOutput | 
abrir_cadastro_de_imovel | postgresTool |  | NAI (secretária) [ai_tool]
disponibilidade_no_condominio | postgresTool |  | NAI (corretor) [ai_tool]
Buscar fotos no site | code |  | Enfileirar resposta
guardar_dados_da_visita | postgresTool |  | NAI (corretor) [ai_tool]
guardar_do_imovel_novo | postgresTool |  | NAI (secretária) [ai_tool]
o_que_sei_do_imovel | postgresTool |  | NAI (corretor) [ai_tool]
Resposta da secretária | code |  | Enfileirar resposta
guardar_do_imovel | postgresTool |  | NAI (corretor) [ai_tool]
Enfileirar resposta | postgres |  | Fechar turno
responder_horario_do_proprietario | postgresTool |  | NAI (corretor) [ai_tool]
mudar_horario_da_visita | postgresTool |  | NAI (corretor) [ai_tool]
Fechar turno | postgres |  | Liberar saída
Agenda (todo minuto) | scheduleTrigger |  | Agenda da NAI
Agenda da NAI | postgres |  | Liberar saída
resultado_da_visita | postgresTool |  | NAI (corretor) [ai_tool]
Liberar saída | postgres |  | Conferir cabeçalho
Conferir cabeçalho | code |  | Pode enviar?
Pode enviar? | if |  | Enviar Z-API, Registrar bloqueio
Enviar Z-API | httpRequest | onError=continueRegularOutput | Confirmar envio
Registrar bloqueio | postgres |  | 
Confirmar envio | postgres |  | 
