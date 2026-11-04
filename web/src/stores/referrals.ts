import { defineStore } from 'pinia'
import { computed, ref } from 'vue'
import { ApiError } from '@/api/errors'
import { referralsApi } from '@/api/referrals'
import type { DischargeOutcome, IsoDate, Referral, ReferralStatus, VersionConflictBody } from '@/api/types'
import { STATUSES_BY_TAB, nextStatus, sortForTriage, type QueueTab } from '@/utils/triage'

export interface DischargeDetails {
  issue_sortie: DischargeOutcome
  date_sortie: IsoDate
  notes: string
}

/** Referrals of the user's centre, shared by the queue and the detail page. */
export const useReferralsStore = defineStore('referrals', () => {
  const byId = ref<Record<string, Referral>>({})
  const loadedAt = ref<Date | null>(null)

  function remember(list: Referral[]): void {
    const next = { ...byId.value }
    for (const referral of list) next[referral.id] = referral
    byId.value = next
  }

  /** Loads every status of one tab (the backend filters one status at a time). */
  async function loadTab(tab: QueueTab): Promise<void> {
    const lists = await Promise.all(STATUSES_BY_TAB[tab].map((status) => referralsApi.list(status)))
    remember(lists.flat())
    loadedAt.value = new Date()
  }

  async function loadAll(): Promise<void> {
    await Promise.all((Object.keys(STATUSES_BY_TAB) as QueueTab[]).map(loadTab))
  }

  function tab(name: QueueTab): Referral[] {
    const statuses: ReferralStatus[] = STATUSES_BY_TAB[name]
    return sortForTriage(Object.values(byId.value).filter((r) => statuses.includes(r.status) && !r.deleted_at))
  }

  const counts = computed(() => ({
    incoming: tab('incoming').length,
    in_care: tab('in_care').length,
    closed: tab('closed').length,
  }))

  async function fetchOne(id: string): Promise<Referral> {
    const referral = await referralsApi.get(id)
    remember([referral])
    return referral
  }

  /**
   * Moves a referral to its next status. On a 409 the server's current row
   * replaces the local one and the error goes up: the user decides again.
   */
  async function advance(referral: Referral, discharge?: DischargeDetails): Promise<Referral> {
    const status = nextStatus(referral.status)
    if (!status) throw new ApiError({ kind: 'validation', status: 400 })
    try {
      const updated = await referralsApi.changeStatus(referral.id, {
        status,
        version: referral.version,
        ...(status === 'clos' && discharge ? discharge : {}),
      })
      remember([updated])
      return updated
    } catch (error) {
      if (error instanceof ApiError && error.kind === 'conflict') {
        const current = (error.body as VersionConflictBody<Referral> | null)?.current
        if (current) remember([current])
      }
      throw error
    }
  }

  return { byId, loadedAt, counts, loadTab, loadAll, tab, fetchOne, advance, remember }
})
