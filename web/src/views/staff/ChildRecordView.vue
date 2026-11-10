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
  const [child, measurements, referrals, vaccinations, foodLogs] = await Promise.all([
    childrenApi.get(props.id),
    childrenApi.measurements(props.id),
    referralsApi.forChild(props.id),
    childrenApi.vaccinations(props.id),
    childrenApi.foodLogs(props.id),
  ])
  return {
    child,
    measurements,
    referrals: sortForTriage(referrals),
    vaccinations: [...vaccinations].sort((a, b) => a.date_faite.localeCompare(b.date_faite)),
    foodLogs: [...foodLogs].sort((a, b) => b.date_jour.localeCompare(a.date_jour)),
  }
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
  <LoadingState v-else-if="!child" variant="detail" />
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
      <div v-if="child.mere">
        <dt>{{ t('child.mother') }}</dt>
        <dd>
          <RouterLink
            v-if="auth.can('beneficiaries:read')"
            :to="{ name: 'beneficiary', params: { id: child.mere.id } }"
            class="mother-link"
          >
            {{ child.mere.prenom }} {{ child.mere.nom }}
          </RouterLink>
          <template v-else>{{ child.mere.prenom }} {{ child.mere.nom }}</template>
        </dd>
      </div>
    </dl>

    <div class="stack">
      <SectionPanel :title="t('charts.growth')">
        <GrowthCharts
          v-if="record.data.value?.measurements.length"
          :measurements="record.data.value.measurements"
          :sexe="record.data.value.child.sexe"
        />
        <p v-else class="muted">{{ t('measurements.empty') }}</p>
      </SectionPanel>

      <SectionPanel :title="t('measurements.title')">
        <MeasurementTable v-if="record.data.value?.measurements.length" :measurements="record.data.value.measurements" />
        <p v-else class="muted">{{ t('measurements.empty') }}</p>
      </SectionPanel>

      <SectionPanel :title="t('child.vaccines')">
        <p v-if="!record.data.value?.vaccinations.length" class="muted">{{ t('child.noVaccines') }}</p>
        <div v-else class="table-scroll">
          <table class="plain-table">
            <caption class="visually-hidden">{{ t('child.vaccines') }}</caption>
            <thead>
              <tr>
                <th scope="col">{{ t('child.vaccineCode') }}</th>
                <th scope="col">{{ t('measurements.date') }}</th>
                <th scope="col">{{ t('child.vaccineCentre') }}</th>
                <th scope="col">{{ t('child.vaccineSource') }}</th>
              </tr>
            </thead>
            <tbody>
              <tr v-for="v in record.data.value.vaccinations" :key="v.id">
                <th scope="row" class="vaccine-code">{{ v.code.toUpperCase() }}</th>
                <td><time :datetime="v.date_faite">{{ fmt.date(v.date_faite) }}</time></td>
                <td>{{ v.centre || '–' }}</td>
                <td>{{ v.confirme_carnet ? t('child.vaccineConfirmed') : t('child.vaccineDeclared') }}</td>
              </tr>
            </tbody>
          </table>
        </div>
      </SectionPanel>

      <SectionPanel :title="t('child.meals')">
        <p v-if="!record.data.value?.foodLogs.length" class="muted">{{ t('child.noMeals') }}</p>
        <div v-else class="table-scroll">
          <table class="plain-table">
            <caption class="visually-hidden">{{ t('child.meals') }}</caption>
            <thead>
              <tr>
                <th scope="col">{{ t('measurements.date') }}</th>
                <th scope="col">{{ t('child.breastfeeding') }}</th>
                <th scope="col">{{ t('child.mealsCount') }}</th>
                <th scope="col">{{ t('child.diversityScore') }}</th>
              </tr>
            </thead>
            <tbody>
              <tr v-for="log in record.data.value.foodLogs" :key="log.id">
                <th scope="row"><time :datetime="log.date_jour">{{ fmt.date(log.date_jour) }}</time></th>
                <td>{{ t(`child.breastfeedingTypes.${log.type_allaitement}`) }}</td>
                <td>{{ log.repas }}</td>
                <td>{{ t('child.diversityValue', { n: log.score_diversite }) }}</td>
              </tr>
            </tbody>
          </table>
        </div>
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

.mother-link {
  color: var(--primary);
}

.plain-table {
  width: 100%;
  border-collapse: collapse;
  font-size: var(--text-sm);
}

.plain-table th,
.plain-table td {
  padding: var(--space-2) var(--space-3);
  text-align: left;
  border-bottom: 1px solid var(--line);
}

.plain-table thead th {
  color: var(--ink-muted);
  font-size: var(--text-sm);
}

.vaccine-code {
  font-family: var(--font-code);
  letter-spacing: 0.04em;
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
