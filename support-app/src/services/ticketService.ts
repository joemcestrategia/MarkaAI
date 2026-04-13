import { supabase } from '../lib/supabase'
import type {
  SupportTicket,
  TicketMessage,
  TicketHistory,
  TicketTag,
  TicketFilters,
  TicketStatus,
  TicketPriority,
  TicketCategory,
  TicketSource,
  TicketMetrics,
} from '../types/ticket.types'

// =============================================================================
// SHARED
// =============================================================================

export async function getCurrentUser() {
  const { data: { user } } = await supabase.auth.getUser()
  return user
}

export async function getUserProfile(userId: string) {
  const { data } = await supabase
    .from('users')
    .select('id, nome, email, role, shop_id')
    .eq('id', userId)
    .maybeSingle()
  return data
}

export async function isCurrentUserAdmin(): Promise<boolean> {
  const user = await getCurrentUser()
  if (!user) return false
  const profile = await getUserProfile(user.id)
  return profile?.role === 'admin'
}

// =============================================================================
// CLIENT-SIDE OPERATIONS
// =============================================================================

export async function getClientTickets(status?: string): Promise<SupportTicket[]> {
  let query = supabase
    .from('support_tickets')
    .select('*')
    .order('created_at', { ascending: false })

  if (status && status !== 'all') {
    if (status === 'open_active') {
      query = query.in('status', ['open', 'in_progress', 'waiting_client'])
    } else {
      query = query.eq('status', status)
    }
  }

  const { data, error } = await query
  if (error) throw error
  return data ?? []
}

export async function getClientTicketById(id: string): Promise<SupportTicket | null> {
  const { data, error } = await supabase
    .from('support_tickets')
    .select('*')
    .eq('id', id)
    .maybeSingle()
  if (error) throw error
  return data
}

export async function createClientTicket(params: {
  title: string
  description: string
  category: TicketCategory
  shop_id: string
  shop_name: string
  opened_by_name: string
  reporter_email?: string
}): Promise<SupportTicket> {
  const user = await getCurrentUser()
  if (!user) throw new Error('Usuário não autenticado')

  const { data, error } = await supabase
    .from('support_tickets')
    .insert({
      title: params.title,
      description: params.description,
      category: params.category,
      source: 'client_portal' as TicketSource,
      shop_id: params.shop_id,
      shop_name: params.shop_name,
      opened_by_user_id: user.id,
      opened_by_name: params.opened_by_name,
      reporter_email: params.reporter_email ?? user.email,
    })
    .select()
    .single()

  if (error) throw error
  return data
}

export async function sendClientMessage(ticketId: string, body: string, authorName: string): Promise<TicketMessage> {
  const user = await getCurrentUser()
  if (!user) throw new Error('Usuário não autenticado')

  const { data, error } = await supabase
    .from('ticket_messages')
    .insert({
      ticket_id: ticketId,
      author_id: user.id,
      author_name: authorName,
      author_role: 'client',
      body,
      is_internal: false,
    })
    .select()
    .single()

  if (error) throw error
  return data
}

export async function markClientTicketRead(ticketId: string): Promise<void> {
  // Only admin can update tickets via RLS, so this uses a specific approach:
  // Client marks as read by updating has_unread_client — but RLS blocks client UPDATE.
  // We use an RPC or the admin handles this. For now, this is a no-op on client side.
  // The unread flag is cleared when the client views the ticket detail.
  // Alternative: create an RPC function that allows this specific update.
}

export async function clientConfirmResolved(ticketId: string): Promise<void> {
  // Client can't update ticket via RLS — use RPC
  const { error } = await supabase.rpc('client_close_ticket', { p_ticket_id: ticketId })
  if (error) throw error
}

export async function clientReopenTicket(ticketId: string, authorName: string): Promise<void> {
  const { error } = await supabase.rpc('client_reopen_ticket', {
    p_ticket_id: ticketId,
    p_author_name: authorName,
  })
  if (error) throw error
}

// =============================================================================
// ADMIN-SIDE OPERATIONS
// =============================================================================

export async function getAdminTickets(filters?: TicketFilters): Promise<SupportTicket[]> {
  let query = supabase
    .from('support_tickets')
    .select('*')

  if (filters?.status?.length) {
    query = query.in('status', filters.status)
  }
  if (filters?.priority?.length) {
    query = query.in('priority', filters.priority)
  }
  if (filters?.category?.length) {
    query = query.in('category', filters.category)
  }
  if (filters?.source?.length) {
    query = query.in('source', filters.source)
  }
  if (filters?.assigned_to === 'unassigned') {
    query = query.is('assigned_to', null)
  } else if (filters?.assigned_to) {
    query = query.eq('assigned_to', filters.assigned_to)
  }
  if (filters?.search) {
    query = query.or(
      `title.ilike.%${filters.search}%,shop_name.ilike.%${filters.search}%,ticket_number.eq.${parseInt(filters.search) || 0}`
    )
  }
  if (filters?.dateFrom) {
    query = query.gte('created_at', filters.dateFrom)
  }
  if (filters?.dateTo) {
    query = query.lte('created_at', filters.dateTo)
  }

  query = query
    .order('has_unread_admin', { ascending: false })
    .order('priority', { ascending: true })
    .order('created_at', { ascending: true })

  const { data, error } = await query.limit(100)
  if (error) throw error

  // Sort with custom priority order
  const priorityOrder: Record<string, number> = { critical: 0, high: 1, medium: 2, low: 3 }
  return (data ?? []).sort((a, b) => {
    if (a.has_unread_admin !== b.has_unread_admin) return a.has_unread_admin ? -1 : 1
    const pA = priorityOrder[a.priority] ?? 99
    const pB = priorityOrder[b.priority] ?? 99
    if (pA !== pB) return pA - pB
    return new Date(a.created_at).getTime() - new Date(b.created_at).getTime()
  })
}

export async function getAdminTicketById(id: string): Promise<SupportTicket | null> {
  const { data, error } = await supabase
    .from('support_tickets')
    .select('*')
    .eq('id', id)
    .maybeSingle()
  if (error) throw error
  return data
}

export async function updateTicket(
  id: string,
  updates: Partial<Pick<SupportTicket, 'status' | 'priority' | 'category' | 'assigned_to'>>
): Promise<SupportTicket> {
  const { data, error } = await supabase
    .from('support_tickets')
    .update(updates)
    .eq('id', id)
    .select()
    .single()
  if (error) throw error
  return data
}

export async function assignTicketToMe(ticketId: string): Promise<void> {
  const user = await getCurrentUser()
  if (!user) throw new Error('Não autenticado')
  await updateTicket(ticketId, { assigned_to: user.id })
}

export async function sendAdminMessage(params: {
  ticketId: string
  body: string
  authorName: string
  authorRole: 'support' | 'admin'
  isInternal: boolean
}): Promise<TicketMessage> {
  const user = await getCurrentUser()
  if (!user) throw new Error('Não autenticado')

  const { data, error } = await supabase
    .from('ticket_messages')
    .insert({
      ticket_id: params.ticketId,
      author_id: user.id,
      author_name: params.authorName,
      author_role: params.authorRole,
      body: params.body,
      is_internal: params.isInternal,
    })
    .select()
    .single()

  if (error) throw error

  // Clear unread flag for admin when replying
  if (!params.isInternal) {
    await supabase
      .from('support_tickets')
      .update({ has_unread_admin: false })
      .eq('id', params.ticketId)
  }

  return data
}

export async function markAdminTicketRead(ticketId: string): Promise<void> {
  await supabase
    .from('support_tickets')
    .update({ has_unread_admin: false })
    .eq('id', ticketId)
}

export async function createManualTicket(params: {
  title: string
  description: string
  category: TicketCategory
  priority: TicketPriority
  source: TicketSource
  shop_id?: string
  shop_name?: string
  opened_by_name: string
  reporter_email?: string
  assigned_to?: string
  internal_note?: string
}): Promise<SupportTicket> {
  const user = await getCurrentUser()
  if (!user) throw new Error('Não autenticado')

  const { data, error } = await supabase
    .from('support_tickets')
    .insert({
      title: params.title,
      description: params.description,
      category: params.category,
      priority: params.priority,
      source: params.source,
      shop_id: params.shop_id ?? null,
      shop_name: params.shop_name ?? null,
      opened_by_user_id: user.id,
      opened_by_name: params.opened_by_name,
      reporter_email: params.reporter_email,
      assigned_to: params.assigned_to ?? null,
    })
    .select()
    .single()

  if (error) throw error

  // Add initial internal note if provided
  if (params.internal_note) {
    await supabase.from('ticket_messages').insert({
      ticket_id: data.id,
      author_id: user.id,
      author_name: params.opened_by_name,
      author_role: 'admin',
      body: params.internal_note,
      is_internal: true,
    })
  }

  return data
}

// =============================================================================
// MESSAGES & HISTORY
// =============================================================================

export async function getTicketMessages(ticketId: string): Promise<TicketMessage[]> {
  const { data, error } = await supabase
    .from('ticket_messages')
    .select('*')
    .eq('ticket_id', ticketId)
    .order('created_at', { ascending: true })
  if (error) throw error
  return data ?? []
}

export async function getTicketHistory(ticketId: string): Promise<TicketHistory[]> {
  const { data, error } = await supabase
    .from('ticket_history')
    .select('*')
    .eq('ticket_id', ticketId)
    .order('created_at', { ascending: false })
  if (error) throw error
  return data ?? []
}

// =============================================================================
// TAGS
// =============================================================================

export async function getAllTags(): Promise<TicketTag[]> {
  const { data, error } = await supabase
    .from('ticket_tags')
    .select('*')
    .order('name')
  if (error) throw error
  return data ?? []
}

export async function getTicketTags(ticketId: string): Promise<TicketTag[]> {
  const { data, error } = await supabase
    .from('ticket_tag_links')
    .select('tag_id, ticket_tags(id, name, color)')
    .eq('ticket_id', ticketId)
  if (error) throw error
  return (data ?? []).map((d: any) => d.ticket_tags).filter(Boolean)
}

export async function setTicketTags(ticketId: string, tagIds: string[]): Promise<void> {
  // Remove existing
  await supabase.from('ticket_tag_links').delete().eq('ticket_id', ticketId)
  // Add new
  if (tagIds.length > 0) {
    await supabase.from('ticket_tag_links').insert(
      tagIds.map(tag_id => ({ ticket_id: ticketId, tag_id }))
    )
  }
}

// =============================================================================
// ADMIN USERS (for assignment dropdown)
// =============================================================================

export async function getAdminUsers() {
  const { data, error } = await supabase
    .from('users')
    .select('id, nome, email, role')
    .eq('role', 'admin')
  if (error) throw error
  return data ?? []
}

// =============================================================================
// SHOPS (for manual ticket creation autocomplete)
// =============================================================================

export async function searchShops(query: string) {
  const { data, error } = await supabase
    .from('shops')
    .select('id, name')
    .ilike('name', `%${query}%`)
    .limit(10)
  if (error) throw error
  return data ?? []
}

// =============================================================================
// METRICS (admin dashboard)
// =============================================================================

export async function getTicketMetrics(daysBack: number = 30): Promise<TicketMetrics> {
  const since = new Date()
  since.setDate(since.getDate() - daysBack)

  const { data: allTickets } = await supabase
    .from('support_tickets')
    .select('id, status, priority, has_unread_admin, created_at, resolved_at, sla_deadline')
    .gte('created_at', since.toISOString())

  const tickets = allTickets ?? []
  const today = new Date()
  today.setHours(0, 0, 0, 0)

  const criticalOpen = tickets.filter(t => t.priority === 'critical' && !['resolved', 'closed'].includes(t.status)).length
  const unreadFromClient = tickets.filter(t => t.has_unread_admin).length
  const openedToday = tickets.filter(t => new Date(t.created_at) >= today).length

  // Average response time (from created to resolved)
  const resolved = tickets.filter(t => t.resolved_at)
  const avgMs = resolved.length > 0
    ? resolved.reduce((sum, t) => sum + (new Date(t.resolved_at!).getTime() - new Date(t.created_at).getTime()), 0) / resolved.length
    : 0
  const avgResponseTimeHours = Math.round((avgMs / (1000 * 60 * 60)) * 10) / 10

  // SLA compliance
  const withSla = tickets.filter(t => t.sla_deadline && t.resolved_at)
  const withinSla = withSla.filter(t => new Date(t.resolved_at!) <= new Date(t.sla_deadline!))
  const slaCompliancePercent = withSla.length > 0 ? Math.round((withinSla.length / withSla.length) * 100) : 100

  return { criticalOpen, unreadFromClient, openedToday, avgResponseTimeHours, slaCompliancePercent }
}

export async function getTicketStatsForReports(daysBack: number) {
  const since = new Date()
  since.setDate(since.getDate() - daysBack)

  const { data } = await supabase
    .from('support_tickets')
    .select('*')
    .gte('created_at', since.toISOString())
    .order('created_at', { ascending: true })

  return data ?? []
}

// =============================================================================
// CLIENT SHOP INFO
// =============================================================================

export async function getClientShopInfo() {
  const user = await getCurrentUser()
  if (!user) return null
  const { data } = await supabase
    .from('shops')
    .select('id, name')
    .eq('owner_id', user.id)
    .maybeSingle()
  return data
}

export async function getClientProfile() {
  const user = await getCurrentUser()
  if (!user) return null
  const { data } = await supabase
    .from('users')
    .select('id, nome, email, role, shop_id')
    .eq('id', user.id)
    .maybeSingle()
  return data
}
