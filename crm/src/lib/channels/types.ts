export interface ChannelSendResult {
  externalId?: string
  raw?: any
  /**
   * A forma do número que o canal REALMENTE aceitou, quando o canal sabe dizer.
   *
   * O mesmo celular brasileiro existe com e sem o nono dígito e só dá pra saber
   * qual funciona tentando; quem chama grava a que deu certo no lead, pra não
   * repetir a tentativa perdida em toda mensagem seguinte.
   */
  recipienteCorrigido?: string
}

export interface ChannelAdapter {
  /** Chave de metadata onde o id externo da mensagem enviada é gravado (ex: 'whatsapp_message_id'). */
  metadataIdKey: string
  supportsGroups: boolean
  /**
   * integrationId identifica a integração específica do lead (não apenas
   * organizationId+type) — necessário para canais com múltiplas contas por
   * organização (ex: Instagram). Adapters que hoje são singleton por org
   * (WhatsApp Cloud, Evolution) simplesmente ignoram o parâmetro.
   */
  sendText(organizationId: string, integrationId: string | null, recipient: string, content: string, isGroup?: boolean): Promise<ChannelSendResult>
  sendMedia(
    organizationId: string,
    integrationId: string | null,
    recipient: string,
    mediaType: string,
    mediaUrl: string,
    caption?: string,
    filename?: string,
    isGroup?: boolean
  ): Promise<ChannelSendResult>
  /**
   * Apaga a mensagem "para todos" no canal (revoke), quando o canal suporta. Ausente =
   * canal não suporta apagar mensagem já enviada (ex: WhatsApp Cloud API oficial e
   * Instagram — restrição da própria Meta, não é possível revogar mensagem de negócio).
   */
  deleteMessage?(
    organizationId: string,
    integrationId: string | null,
    recipient: string,
    externalMessageId: string,
    isGroup?: boolean
  ): Promise<void>
}
