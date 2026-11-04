import type { DischargeOutcome, Priorite, Referral, ReferralStatus, Urgency } from '@/api/types'

/** Backend priority → spec colour (the API also sends it as "urgence"). */
export const URGENCY_BY_PRIORITY: Record<Priorite, Urgency> = {
  urgente: 'rouge',
  haute: 'orange',
  normale: 'jaune',
}

const RANK: Record<Urgency, number> = { rouge: 0, orange: 1, jaune: 2 }

export function urgencyOf(referral: Pick<Referral, 'priorite'> & Partial<Pick<Referral, 'urgence'>>): Urgency {
  return referral.urgence ?? URGENCY_BY_PRIORITY[referral.priorite]
}

function referredAt(referral: Referral): number {
  return Date.parse(referral.date_referencement ?? referral.created_at)
}

/** Most urgent first; within the same urgency, the one waiting longest first. */
export function compareTriage(a: Referral, b: Referral): number {
  const byUrgency = (RANK[urgencyOf(a)] ?? 9) - (RANK[urgencyOf(b)] ?? 9)
  if (byUrgency !== 0) return byUrgency
  return referredAt(a) - referredAt(b)
}

export function sortForTriage(list: readonly Referral[]): Referral[] {
  return [...list].sort(compareTriage)
}

/** Life cycle of spec §7, as enforced by referencement/services.py (D7). */
export const STATUS_ORDER: ReferralStatus[] = ['envoye', 'recu', 'pris_en_charge', 'en_suivi', 'sortie']

/** The next ordinary step; the discharge is offered separately. */
export function nextStatus(status: ReferralStatus): ReferralStatus | null {
  if (status === 'en_suivi' || status === 'sortie') return null
  return STATUS_ORDER[STATUS_ORDER.indexOf(status) + 1] ?? null
}

/** A discharge is allowed once the patient has arrived (transfer, death…). */
export function canDischargeFrom(status: ReferralStatus): boolean {
  return status === 'recu' || status === 'pris_en_charge' || status === 'en_suivi'
}

export type QueueTab = 'incoming' | 'in_care' | 'closed'

/** "incoming" comes from /api/referrals/incoming/ (envoye and recu). */
export const STATUSES_BY_TAB: Record<QueueTab, ReferralStatus[]> = {
  incoming: ['envoye', 'recu'],
  in_care: ['pris_en_charge', 'en_suivi'],
  closed: ['sortie'],
}

/** Exit outcomes of spec §7 (IssueSortieEnum). */
export const OUTCOMES: DischargeOutcome[] = ['gueri', 'transfere', 'non_repondant', 'abandon', 'decede']
