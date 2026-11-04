import { defineStore } from 'pinia'
import { computed, ref } from 'vue'
import { ApiError } from '@/api/errors'
import { referralsApi } from '@/api/referrals'
import { STATUSES_BY_TAB, sortForTriage } from '@/utils/triage'

/** @typedef {import('@/api/types').DischargeOutcome} DischargeOutcome */
/** @typedef {import('@/api/types').Referral} Referral */
/** @typedef {import('@/api/types').ReferralStatus} ReferralStatus */
/** @typedef {import('@/api/types').VersionConflictBody} VersionConflictBody */
/** @typedef {import('@/utils/triage').QueueTab} QueueTab */

/** Referrals of the user's centre, shared by the queue and the detail page. */
export const useReferralsStore = defineStore('referrals', () => {
  /** @type {import('vue').Ref<Record<string, Referral>>} */
  const byId = ref({})
  /** @type {import('vue').Ref<Date | null>} */
  const loadedAt = ref(null)

  /** @param {Referral[]} list */
  function remember(list) {
    const next = { ...byId.value }
    for (const referral of list) next[referral.id] = referral
    byId.value = next
  }

  /**
   * @param {QueueTab} tab
   * @returns {Promise<void>}
   */
  async function loadTab(tab) {
    const lists =
      tab === 'incoming'
        ? [await referralsApi.incoming()]
        : await Promise.all(STATUSES_BY_TAB[tab].map((status) => referralsApi.list(status)))
    remember(lists.flat())
    loadedAt.value = new Date()
  }

  /** @returns {Promise<void>} */
  async function loadAll() {
    await Promise.all(Object.keys(STATUSES_BY_TAB).map(loadTab))
  }

  /**
   * @param {QueueTab} name
   * @returns {Referral[]}
   */
  function tab(name) {
    /** @type {ReferralStatus[]} */
    const statuses = STATUSES_BY_TAB[name]
    return sortForTriage(Object.values(byId.value).filter((r) => statuses.includes(r.status) && !r.deleted_at))
  }

  const counts = computed(() => ({
    incoming: tab('incoming').length,
    in_care: tab('in_care').length,
    closed: tab('closed').length,
  }))

  /**
   * @param {string} id
   * @returns {Promise<Referral>}
   */
  async function fetchOne(id) {
    const referral = await referralsApi.get(id)
    remember([referral])
    return referral
  }

  /**
   * Moves a referral on. On a 409 the server's current row replaces the
   * local one and the error goes up: the user looks again and decides.
   * @param {Referral} referral
   * @param {ReferralStatus} status
   * @param {DischargeOutcome} [outcome]
   * @returns {Promise<Referral>}
   */
  async function changeStatus(referral, status, outcome) {
    try {
      const updated = await referralsApi.changeStatus(referral.id, {
        status,
        version: referral.version,
        ...(status === 'sortie' && outcome ? { issue_sortie: outcome } : {}),
      })
      remember([updated])
      return updated
    } catch (error) {
      if (error instanceof ApiError && error.kind === 'conflict') {
        const current = error.body?.current
        if (current) remember([current])
      }
      throw error
    }
  }

  return { byId, loadedAt, counts, loadTab, loadAll, tab, fetchOne, changeStatus, remember }
})
