import type { Priorite, Referral, ReferralStatus } from '@/api/types'

/**
 * The spec speaks of red / orange / yellow urgency; the backend stores
 * "urgente" / "haute" / "normale". This is the mapping between the two.
 */
export type Urgency = 'rouge' | 'orange' | 'jaune'

export const URGENCY_BY_PRIORITY: Record<Priorite, Urgency> = {
  urgente: 'rouge',
  haute: 'orange',
  normale: 'jaune',
}

const RANK: Record<Priorite, number> = { urgente: 0, haute: 1, normale: 2 }

export function urgencyOf(priorite: Priorite): Urgency {
  return URGENCY_BY_PRIORITY[priorite]
}

/** Most urgent first; within the same urgency, the one waiting longest first. */
export function compareTriage(a: Referral, b: Referral): number {
  const byUrgency = (RANK[a.priorite] ?? 9) - (RANK[b.priorite] ?? 9)
  if (byUrgency !== 0) return byUrgency
  return Date.parse(a.created_at) - Date.parse(b.created_at)
}

export function sortForTriage(list: readonly Referral[]): Referral[] {
  return [...list].sort(compareTriage)
}

/** Order of the backend's status machine (referencement/services.py). */
export const STATUS_ORDER: ReferralStatus[] = ['envoye', 'recu', 'vu', 'pris_en_charge', 'clos']

/** The backend only allows the next status; null when the referral is closed. */
export function nextStatus(status: ReferralStatus): ReferralStatus | null {
  const index = STATUS_ORDER.indexOf(status)
  return STATUS_ORDER[index + 1] ?? null
}

export type QueueTab = 'incoming' | 'in_care' | 'closed'

export const STATUSES_BY_TAB: Record<QueueTab, ReferralStatus[]> = {
  incoming: ['envoye'],
  in_care: ['recu', 'vu', 'pris_en_charge'],
  closed: ['clos'],
}
