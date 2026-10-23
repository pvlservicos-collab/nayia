"""O que o serviço lê do ambiente (/root/nay-cadastro/.env no servidor, fora do git)."""
import os

DATABASE_URL = os.environ.get("DATABASE_URL", "")
OPENAI_API_KEY = os.environ.get("OPENAI_API_KEY", "")
MODELO = os.environ.get("CADASTRO_MODELO", "gpt-6-luna")      # todo modelo de texto da casa (01/10)
# a API do site: cria e salva o imóvel, sobe as fotos, cria o condomínio (o segredo de máquina do painel do CRM)
SITE_API_URL = os.environ.get("SITE_API_URL", "http://127.0.0.1:8092").rstrip("/")
PAINEL_SEGREDO = os.environ.get("CRM_PAINEL_SEGREDO", "")
LINK_DO_EDITOR = "https://imobeasy.online/admin/imovel-editar.html?codigo={codigo}"
# o grupo CADASTRO DE IMÓVEL IMOBEASY, no número da Parceria
GRUPO_ID = os.environ.get("CADASTRO_GRUPO_ID", "120363414621414957-group")
# a Z-API da Parceria (as mesmas credenciais do publicador), só para POSTAR no grupo: o privado vai pela caixa da Nay
ZAPI_ENV = os.environ.get("CADASTRO_ZAPI_ENV", "/root/nay-publicador/.env")
# 479 (Tel, 23/10: "tem que ser a mesma Nay Leads fazer as perguntas"): quem escreveu para o número de Leads (8595, a
# Z-API da captação) nesses dias é perguntado por ele. A credencial está no config do vigia (o mesmo do nay-olx).
CONF_DO_VIGIA = os.environ.get("CADASTRO_CONF_DO_VIGIA", "/root/vigia_whatsapp/config.json")
LEADS_DIAS = float(os.environ.get("CADASTRO_LEADS_DIAS", "3"))
# alguém da equipe escreveu pelo 8595 nesses minutos: a conversa é dela (o mesmo meio hora do Tel na Parceria)
LEADS_GENTE_MIN = int(os.environ.get("CADASTRO_LEADS_GENTE_MIN", "30"))
# segundos de silêncio que fecham uma leva no grupo (o encaminhamento chega em rajada)
LEVA_SILENCIO_S = int(os.environ.get("CADASTRO_LEVA_SILENCIO_S", "90"))
# segundos de silêncio antes de ler a resposta dele no privado (ele pode mandar em duas mensagens)
RESPOSTA_SILENCIO_S = int(os.environ.get("CADASTRO_RESPOSTA_SILENCIO_S", "20"))
# sem resposta: aviso no grupo depois de X horas; a ficha fecha depois de Y horas
AVISO_SEM_RESPOSTA_H = float(os.environ.get("CADASTRO_AVISO_SEM_RESPOSTA_H", "3"))
ENCERRA_SEM_RESPOSTA_H = float(os.environ.get("CADASTRO_ENCERRA_SEM_RESPOSTA_H", "24"))
# o privado só começa nesse horário (Manaus); o grupo responde a qualquer hora
HORA_INICIO = int(os.environ.get("CADASTRO_HORA_INICIO", "8"))
HORA_FIM = int(os.environ.get("CADASTRO_HORA_FIM", "20"))
# só o que chegou ao grupo depois disto entra (o serviço não cadastra o histórico de antes de ser ligado)
DESDE_H = float(os.environ.get("CADASTRO_DESDE_H", "48"))
BATIMENTO = os.environ.get("CADASTRO_BATIMENTO", "/tmp/nay-cadastro.batimento")
# a abertura do privado é campos.abertura (Tel, 20/10: "Oi (NOME) estou fazendo o cadastro do seu imóvel ...")
