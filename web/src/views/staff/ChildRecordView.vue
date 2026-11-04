<script setup>
import { computed, onMounted, watch } from 'vue'
import { useI18n } from 'vue-i18n'
import { RouterLink } from 'vue-router'
import { childrenApi } from '@/api/children'
import { referralsApi } from '@/api/referrals'
import GrowthCharts from '@/components/children/GrowthCharts.vue'
import MeasurementTable from '@/components/children/MeasurementTable.vue'
import CareSection from '@/components/referrals/CareSection.vue'
import ErrorState from '@/components/ui/ErrorState.vue'
import LoadingState from '@/components/ui/LoadingState.vue'
import PageHeader from '@/components/ui/PageHeader.vue'
import ReferralCode from '@/components/ui/ReferralCode.vue'
import SectionPanel from '@/components/ui/SectionPanel.vue'
import StatusBadge from '@/components/ui/StatusBadge.vue'
import UrgencyBadge from '@/components/ui/UrgencyBadge.vue'
import { useAsync } from '@/composables/useAsync'
import { useFormatters } from '@/composables/useFormatters'
import { useAuthStore } from '@/stores/auth'
import { ageInMonths, todayIso } from '@/utils/dates'
import { sortForTriage, urgencyOf } from '@/utils/triage'

const props = defineProps({ id: { type: String, required: true } })
const { t } = useI18n()
const fmt = useFormatters()
const auth = useAuthStore()

const record = useAsync(async () => {
  const [child, measurements, referrals] = await Promise.all([
    childrenApi.get(props.id),
    childrenApi.measurements(props.id),
    referralsApi.forChild(props.id),
  ])
  return { child, measurements, referrals: sortForTriage(referrals) }
})

const child = computed(() => record.data.value?.child ?? null)
const age = computed(() => (child.value ? ageInMonths(child.value.date_naissance, todayIso()) : 0))
const openReferral = computed(() => record.data.value?.referrals.find((r) => r.status !== 'sortie') ?? null)
const csbId = computed(() => auth.user?.csb_id ?? openReferral.value?.csb_id ?? null)

onMounted(record.run)
watch(() => props.id, record.run)
</script>

<template>
  <ErrorState v-if="record.error.value" :error="record.error.value" retryable @retry="record.run" />
  <LoadingState v-else-if="!child" />
  <template v-else>
    <PageHeader :title="child.nom">
      <template #before>
        <p class="eyebrow muted">{{ t('child.title') }}</p>
      </template>
    </PageHeader>

    <dl class="facts">
      <div>
        <dt>{{ t('child.sex') }}</dt>
        <dd>{{ t(`child.sexes.${child.sexe}`) }}</dd>
      </div>
      <div>
        <dt>{{ t('child.age') }}</dt>
        <dd>{{ t('child.ageMonths', age) }}</dd>
      </div>
      <div>
        <dt>{{ t('child.birthDate') }}</dt>
        <dd><time :datetime="child.date_naissance">{{ fmt.date(child.date_naissance) }}</time></dd>
      </div>
      <div>
        <dt>{{ t('child.careStatus') }}</dt>
        <dd>{{ t(`child.careStatuses.${child.statut_prise_en_charge}`) }}</dd>
      </div>
    </dl>

    <div class="stack">
      <SectionPanel :title="t('charts.growth')">
        <GrowthCharts v-if="record.data.value?.measurements.length" :measurements="record.data.value.measurements" />
        <p v-else class="muted">{{ t('measurements.empty') }}</p>
      </SectionPanel>

      <SectionPanel :title="t('measurements.title')">
        <MeasurementTable v-if="record.data.value?.measurements.length" :measurements="record.data.value.measurements" />
        <p v-else class="muted">{{ t('measurements.empty') }}</p>
      </SectionPanel>

      <SectionPanel :title="t('child.referrals')">
        <p v-if="!record.data.value?.referrals.length" class="muted">{{ t('child.noReferrals') }}</p>
        <ul v-else class="refs">
          <li v-for="r in record.data.value.referrals" :key="r.id" class="refs__item">
            <RouterLink :to="{ name: 'referral', params: { id: r.id } }">
              <span class="visually-hidden">{{ t('queue.open', { code: r.code_unique }) }}</span>
              <ReferralCode :code="r.code_unique" aria-hidden="true" />
            </RouterLink>
            <UrgencyBadge :urgency="urgencyOf(r)" />
            <StatusBadge :status="r.status" />
            <time class="muted" :datetime="r.date_referencement">{{ fmt.date(r.date_referencement) }}</time>
          </li>
        </ul>
      </SectionPanel>

      <CareSection :child-id="child.id" :referral-id="openReferral?.id ?? null" :csb-id="csbId" :can-write="auth.can('care:write')" />
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
  padding-left: var(--space-3);
  border-left: 3px solid var(--sky-300);
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
  border-bottom: 1px solid var(--sky-200);
}
</style>
