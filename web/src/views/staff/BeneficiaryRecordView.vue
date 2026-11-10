<script setup>
import { computed, onMounted, watch } from 'vue'
import { useI18n } from 'vue-i18n'
import { RouterLink } from 'vue-router'
import { beneficiariesApi } from '@/api/beneficiaries'
import ErrorState from '@/components/ui/ErrorState.vue'
import InlineAlert from '@/components/ui/InlineAlert.vue'
import LoadingState from '@/components/ui/LoadingState.vue'
import PageHeader from '@/components/ui/PageHeader.vue'
import ReferralCode from '@/components/ui/ReferralCode.vue'
import SectionPanel from '@/components/ui/SectionPanel.vue'
import StatusBadge from '@/components/ui/StatusBadge.vue'
import UrgencyBadge from '@/components/ui/UrgencyBadge.vue'
import { useAsync } from '@/composables/useAsync'
import { useFormatters } from '@/composables/useFormatters'
import { ageInMonths, todayIso } from '@/utils/dates'
import { currentPregnancy, dueDate, gestationalWeeks } from '@/utils/pregnancy'
import { sortForTriage, urgencyOf } from '@/utils/triage'

/** @typedef {import('@/api/types').DangerSign} DangerSign */

const props = defineProps({ id: { type: String, required: true } })
const { t, te } = useI18n()
const fmt = useFormatters()

const record = useAsync(() => beneficiariesApi.get(props.id))
const dossier = computed(() => record.data.value)
const woman = computed(() => dossier.value?.beneficiaire ?? null)
const today = todayIso()

const pregnancy = computed(() => (dossier.value ? currentPregnancy(dossier.value.grossesses) : null))
const weeks = computed(() => (pregnancy.value ? gestationalWeeks(pregnancy.value, today) : null))
const due = computed(() => (pregnancy.value ? dueDate(pregnancy.value) : null))
const pastPregnancies = computed(
  () => dossier.value?.grossesses.filter((g) => g.terminee).length ?? 0,
)

// CPN contacts of the current pregnancy, in order.
const cpn = computed(() => {
  const current = pregnancy.value
  if (!current) return []
  return dossier.value.contacts_soin
    .filter((c) => c.grossesse_id === current.id && c.type === 'cpn')
    .sort((a, b) => a.numero - b.numero)
})

// Every danger sign of her file, the newest first.
const dangers = computed(() =>
  [...(dossier.value?.signes_danger ?? [])].sort((a, b) =>
    b.date_signalement.localeCompare(a.date_signalement),
  ),
)

const children = computed(() => dossier.value?.enfants ?? [])
const referrals = computed(() => sortForTriage(dossier.value?.referencements ?? []))

/**
 * The sign's wording when the code is known, else the code itself.
 * @param {DangerSign} danger
 * @returns {string}
 */
function dangerLabel(danger) {
  const key = `dangers.codes.${danger.code}`
  return te(key) ? t(key) : danger.code
}

onMounted(record.run)
watch(() => props.id, record.run)
</script>

<template>
  <ErrorState v-if="record.error.value" :error="record.error.value" retryable @retry="record.run" />
  <LoadingState v-else-if="!woman" variant="detail" />
  <template v-else>
    <PageHeader :title="`${woman.prenom} ${woman.nom}`">
      <template #before>
        <p class="eyebrow muted">{{ t('beneficiary.title') }}</p>
      </template>
    </PageHeader>

    <dl class="facts">
      <div v-if="woman.code_beneficiaire">
        <dt>{{ t('beneficiary.code') }}</dt>
        <dd><code class="code">{{ woman.code_beneficiaire }}</code></dd>
      </div>
      <div>
        <dt>{{ t('beneficiary.phone') }}</dt>
        <dd>{{ woman.phone || t('beneficiary.notProvided') }}</dd>
      </div>
      <div>
        <dt>{{ t('beneficiary.childrenCount') }}</dt>
        <dd>{{ t('beneficiaries.children', children.length) }}</dd>
      </div>
    </dl>

    <div class="stack">
      <SectionPanel :title="t('beneficiary.pregnancy')">
        <p v-if="!pregnancy" class="muted">{{ t('beneficiary.noPregnancy') }}</p>
        <template v-else>
          <dl class="facts facts--panel">
            <div v-if="weeks !== null">
              <dt>{{ t('beneficiary.gestationalAge') }}</dt>
              <dd>{{ t('beneficiary.weeks', weeks) }}</dd>
            </div>
            <div v-if="due">
              <dt>{{ t('beneficiary.dpa') }}</dt>
              <dd><time :datetime="due">{{ fmt.date(due) }}</time></dd>
            </div>
            <div v-if="pregnancy.ddr">
              <dt>{{ t('beneficiary.ddr') }}</dt>
              <dd><time :datetime="pregnancy.ddr">{{ fmt.date(pregnancy.ddr) }}</time></dd>
            </div>
          </dl>

          <h3 class="subhead">{{ t('beneficiary.cpn') }}</h3>
          <p v-if="!cpn.length" class="muted">{{ t('beneficiary.noCpn') }}</p>
          <ul v-else class="plain-list">
            <li v-for="contact in cpn" :key="contact.id">
              {{ t('beneficiary.cpnItem', { n: contact.numero }) }}
              <time class="muted" :datetime="contact.date_faite">{{ fmt.date(contact.date_faite) }}</time>
            </li>
          </ul>
        </template>
        <p v-if="pastPregnancies" class="muted past">
          {{ t('beneficiary.finishedPregnancies', pastPregnancies) }}
        </p>
      </SectionPanel>

      <SectionPanel :title="t('beneficiary.dangers')">
        <p v-if="!dangers.length" class="muted">{{ t('beneficiary.noDangers') }}</p>
        <ul v-else class="plain-list">
          <li v-for="danger in dangers" :key="danger.id" class="danger">
            <strong>{{ dangerLabel(danger) }}</strong>
            <span v-if="danger.periode" class="muted">{{ t(`beneficiary.periods.${danger.periode}`) }}</span>
            <time class="muted" :datetime="danger.date_signalement">{{ fmt.date(danger.date_signalement) }}</time>
          </li>
        </ul>
      </SectionPanel>

      <SectionPanel :title="t('beneficiary.children')">
        <p v-if="!children.length" class="muted">{{ t('beneficiary.noChildren') }}</p>
        <ul v-else class="plain-list">
          <li v-for="child in children" :key="child.id" class="child">
            <RouterLink :to="{ name: 'child', params: { id: child.id } }" class="child__link">
              {{ child.nom }}
            </RouterLink>
            <span class="muted">
              {{ t(`child.sexes.${child.sexe}`) }} ·
              {{ t('child.ageMonths', ageInMonths(child.date_naissance, today)) }}
            </span>
          </li>
        </ul>
      </SectionPanel>

      <SectionPanel :title="t('beneficiary.referrals')">
        <p v-if="!referrals.length" class="muted">{{ t('beneficiary.noReferrals') }}</p>
        <ul v-else class="refs">
          <li v-for="r in referrals" :key="r.id" class="refs__item">
            <RouterLink :to="{ name: 'referral', params: { id: r.id } }">
              <span class="visually-hidden">{{ t('queue.open', { code: r.code_unique }) }}</span>
              <ReferralCode :code="r.code_unique" aria-hidden="true" />
            </RouterLink>
            <span class="muted">{{ t(`origin.${r.origine}`) }}</span>
            <UrgencyBadge :urgency="urgencyOf(r)" />
            <StatusBadge :status="r.status" />
            <time class="muted" :datetime="r.date_referencement">{{ fmt.date(r.date_referencement) }}</time>
          </li>
        </ul>
      </SectionPanel>

      <InlineAlert tone="info">{{ t('beneficiary.auditNote') }}</InlineAlert>
    </div>
  </template>
</template>

<style scoped>
.eyebrow {
  margin-bottom: var(--space-1);
  font-weight: 700;
}

.facts {
  display: grid;
  grid-template-columns: repeat(auto-fit, minmax(10rem, 1fr));
  gap: var(--space-3);
  margin: 0 0 var(--space-5);
}

.facts div {
  padding: var(--space-3) var(--space-4);
  background: var(--sky-50);
  border-radius: var(--radius-sm);
}

.facts dt {
  font-size: var(--text-sm);
  color: var(--ink-muted);
}

.facts dd {
  margin: 0;
  font-size: var(--text-md);
  font-weight: 700;
}

.facts--panel {
  margin-bottom: var(--space-4);
}

.facts--panel div {
  background: transparent;
  padding: 0;
}

.code {
  font-family: var(--font-code);
  letter-spacing: 0.08em;
}

.subhead {
  margin: 0 0 var(--space-2);
  font-size: var(--text-sm);
  color: var(--ink-muted);
}

.plain-list {
  list-style: none;
  margin: 0;
  padding: 0;
}

.plain-list li {
  display: flex;
  flex-wrap: wrap;
  align-items: baseline;
  gap: var(--space-3);
  min-height: var(--target-min);
  padding: var(--space-1) 0;
}

.plain-list li + li {
  border-top: 1px solid var(--line);
}

.past {
  margin: var(--space-3) 0 0;
  font-size: var(--text-sm);
}

.child__link {
  font-weight: 700;
  color: var(--primary);
}

.refs {
  list-style: none;
  margin: 0;
  padding: 0;
}

.refs__item {
  display: flex;
  flex-wrap: wrap;
  align-items: center;
  gap: var(--space-3);
  min-height: var(--target);
  padding: var(--space-2) 0;
  border-bottom: 1px solid var(--line);
}
</style>
