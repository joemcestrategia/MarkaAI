export type TicketStatus = 'open' | 'in_progress' | 'waiting_client' | 'resolved' | 'closed'
export type TicketPriority = 'critical' | 'high' | 'medium' | 'low'
export type TicketCategory = 'scheduling' | 'payment' | 'whatsapp' | 'nfse' | 'account' | 'other'
export type TicketSource = 'client_portal' | 'manual' | 'email' | 'whatsapp'
export type AuthorRole = 'client' | 'support' | 'admin'
export type HistoryActorRole = 'client' | 'support' | 'admin' | 'system'
export type LastReplyBy = 'client' | 'support'

export interface SupportTicket {
  id: string
  ticket_number: number
  title: string
  description: string
  status: TicketStatus
  priority: TicketPriority
  category: TicketCategory
  source: TicketSource
  shop_id: string | null
  shop_name: string | null
  opened_by_user_id: string
  opened_by_name: string
  reporter_email: string | null
  assigned_to: string | null
  sla_deadline: string | null
  resolved_at: string | null
  closed_at: string | null
  last_reply_at: string | null
  last_reply_by: LastReplyBy | null
  has_unread_admin: boolean
  has_unread_client: boolean
  created_at: string
  updated_at: string
  // joined
  assigned_user?: { nome: string; email: string } | null
  tags?: TicketTag[]
}

export interface TicketMessage {
  id: string
  ticket_id: string
  author_id: string
  author_name: string
  author_role: AuthorRole
  body: string
  is_internal: boolean
  attachments: TicketAttachment[]
  created_at: string
}

export interface TicketAttachment {
  name: string
  url: string
  size: number
  type: string
}

export interface TicketHistory {
  id: string
  ticket_id: string
  actor_name: string
  actor_role: HistoryActorRole
  action: string
  old_value: string | null
  new_value: string | null
  created_at: string
}

export interface TicketTag {
  id: string
  name: string
  color: string
}

export interface TicketTagLink {
  ticket_id: string
  tag_id: string
}

export interface AdminUser {
  id: string
  nome: string
  email: string
  role: string
}

export interface TicketFilters {
  status?: TicketStatus[]
  priority?: TicketPriority[]
  category?: TicketCategory[]
  source?: TicketSource[]
  assigned_to?: string | 'unassigned'
  search?: string
  dateFrom?: string
  dateTo?: string
}

export interface TicketMetrics {
  criticalOpen: number
  unreadFromClient: number
  openedToday: number
  avgResponseTimeHours: number
  slaCompliancePercent: number
}
