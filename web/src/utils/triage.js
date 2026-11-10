/** @typedef {import('@/api/types').DischargeOutcome} DischargeOutcome */
/** @typedef {import('@/api/types').Priorite} Priorite */
/** @typedef {import('@/api/types').Referral} Referral */
/** @typedef {import('@/api/types').ReferralStatus} ReferralStatus */
/** @typedef {import('@/api/types').Urgency} Urgency */

/**
 * Backend priority → spec colour (the API also sends it as "urgence").
 * @type {Record<Priorite, Urgency>}
 */
export const URGENCY_BY_PRIORITY = {
  urgente: 'rouge',
  haute: 'orange',
  normale: 'jaune',
}

/** @type {Record<Urgency, number>} */
const RANK = { rouge: 0, orange: 1, jaune: 2 }

/**
 * @param {Pick<Referral, 'priorite'> & Partial<Pick<Referral, 'urgence'>>} referral
 * @returns {Urgency}
 */
export function urgencyOf(referral) {
  return referral.urgence ?? URGENCY_BY_PRIORITY[referral.priorite]
}

/**
 * @param {Referral} referral
 * @returns {number}
 */
function referredAt(referral) {
  return Date.parse(referral.date_referencement ?? referral.created_at)
}

/**
 * Most urgent first; within the same urgency, the one waiting longest first.
 * @param {Referral} a
 * @param {Referral} b
 * @returns {number}
 */
export function compareTriage(a, b) {
  const byUrgency = (RANK[urgencyOf(a)] ?? 9) - (RANK[urgencyOf(b)] ?? 9)
  if (byUrgency !== 0) return byUrgency
  return referredAt(a) - referredAt(b)
}

/**
 * @param {readonly Referral[]} list
 * @returns {Referral[]}
 */
export function sortForTriage(list) {
  return [...list].sort(compareTriage)
}

/**
 * Life cycle of spec §7, as enforced by referencement/services.py (D7).
 * @type {ReferralStatus[]}
 */
export const STATUS_ORDER = ['envoye', 'recu', 'pris_en_charge', 'en_suivi', 'sortie']

/**
 * The next ordinary step; the discharge is offered separately.
 * @param {ReferralStatus} status
 * @returns {ReferralStatus | null}
 */
export function nextStatus(status) {
  if (status === 'en_suivi' || status === 'sortie') return null
  return STATUS_ORDER[STATUS_ORDER.indexOf(status) + 1] ?? null
}

/**
 * A discharge is allowed once the patient has arrived (transfer, death…).
 * @param {ReferralStatus} status
 * @returns {boolean}
 */
export function canDischargeFrom(status) {
  return status === 'recu' || status === 'pris_en_charge' || status === 'en_suivi'
}

/** @typedef {'incoming' | 'in_care' | 'closed'} QueueTab */

/**
 * "incoming" comes from /api/referrals/incoming/ (envoye and recu).
 * @type {Record<QueueTab, ReferralStatus[]>}
 */
export const STATUSES_BY_TAB = {
  incoming: ['envoye', 'recu'],
  in_care: ['pris_en_charge', 'en_suivi'],
  closed: ['sortie'],
}

/**
 * Exit outcomes of spec §7 (IssueSortieEnum).
 * @type {DischargeOutcome[]}
 */
export const OUTCOMES = ['gueri', 'transfere', 'non_repondant', 'abandon', 'decede']
