<script setup>
import { computed, onMounted, watch } from 'vue'
import { useI18n } from 'vue-i18n'
import { RouterLink } from 'vue-router'
import { childrenApi } from '@/api/children'
import CareSection from '@/components/referrals/CareSection.vue'
import ReferralActions from '@/components/referrals/ReferralActions.vue'
import StatusStepper from '@/components/referrals/StatusStepper.vue'
import AgentContact from '@/components/ui/AgentContact.vue'
import ErrorState from '@/components/ui/ErrorState.vue'
import InlineAlert from '@/components/ui/InlineAlert.vue'
import LoadingState from '@/components/ui/LoadingState.vue'
import ReferralCode from '@/components/ui/ReferralCode.vue'
import SectionPanel from '@/components/ui/SectionPanel.vue'
import UrgencyBadge from '@/components/ui/UrgencyBadge.vue'
import { useAsync } from '@/composables/useAsync'
import { useFormatters } from '@/composables/useFormatters'
import { useAuthStore } from '@/stores/auth'
import { useReferentielStore } from '@/stores/referentiel'
import { useReferralsStore } from '@/stores/referrals'
import { toNumber } from '@/utils/numbers'
import { urgencyOf } from '@/utils/triage'

const props = defineProps({ id: { type: String, required: true } })
const { t } = useI18n()
const fmt = useFormatters()
const auth = useAuthStore()
const store = useReferralsStore()
const referentiel = useReferentielStore()

const loader = useAsync(() => store.fetchOne(props.id))
// The store copy follows status changes made on this page.
const referral = computed(() => store.byId[props.id] ?? null)
const measurement = useAsync(() =>
  referral.value?.mesure_id ? childrenApi.measurement(referral.value.mesure_id) : Promise.resolve(null),
)
const facility = computed(() => {
  const r = referral.value
  const found = r ? referentiel.facilities.find((f) => f.id === r.csb_id) : undefined
  if (!found) return r ? `#${r.csb_id}` : ''
  return t('referral.facilityType', { name: found.name, type: t(`centreTypes.${found.type_centre}`) })
})
const urgency = computed(() => (referral.value ? urgencyOf(referral.value) : 'jaune'))
const referredAt = computed(() => referral.value?.date_referencement ?? referral.value?.created_at ?? '')

/** @returns {Promise<void>} */
async function load() {
  await loader.run()
  void measurement.run()
  void referentiel.load().catch(() => undefined)
}

onMounted(load)
watch(() => props.id, load)
</script>

<template>
  <ErrorState v-if="loader.error.value && !referral" :error="loader.error.value" retryable @retry="load" />
  <LoadingState v-else-if="!referral" variant="detail" />
  <div v-else class="detail" :class="`detail--${urgency}`">
    <header class="detail__head">
      <p class="detail__label muted">{{ t('referral.code') }}</p>
      <h1 tabindex="-1" data-page-title class="detail__title">
        <span class="visually-hidden">{{ t('referral.title', { code: referral.code_unique }) }}</span>
        <ReferralCode :code="referral.code_unique" size="xl" aria-hidden="true" />
      </h1>
      <div class="detail__badges">
        <UrgencyBadge :urgency="urgency" with-hint />
        <span v-if="referral.status === 'envoye'" class="muted">{{ t('duration.waiting', { duration: fmt.waiting(referredAt) }) }}</span>
        <span v-if="referral.en_retard" class="detail__late">{{ t('referral.late') }}</span>
      </div>
    </header>

    <div class="detail__grid">
      <div class="stack detail__main">
        <SectionPanel :title="t('referral.progress')">
          <StatusStepper :referral="referral" />
        </SectionPanel>

        <SectionPanel :title="t('referral.reason')">
          <p class="detail__reason">{{ referral.motif }}</p>
          <dl class="facts">
            <div>
              <dt>{{ t('referral.origin') }}</dt>
              <dd>{{ t(`origin.${referral.origine}`) }}</dd>
            </div>
            <div v-if="referral.femme">
              <dt>{{ t('referral.mother') }}</dt>
              <dd>{{ referral.femme.prenom }} {{ referral.femme.nom }}</dd>
            </div>
            <div>
              <dt>{{ t('referral.facility') }}</dt>
              <dd>{{ facility }}</dd>
            </div>
            <div>
              <dt>{{ t('referral.agent') }}</dt>
              <dd><AgentContact :contact="referral.asc" /></dd>
            </div>
            <div v-if="referral.issue_sortie">
              <dt>{{ t('referral.outcome') }}</dt>
              <dd>{{ t(`discharge.outcomes.${referral.issue_sortie}`) }}</dd>
            </div>
          </dl>
          <p v-if="referral.enfant_id">
            <RouterLink :to="{ name: 'child', params: { id: referral.enfant_id } }" class="detail__child-link">
              {{ t('referral.openChild') }}
            </RouterLink>
          </p>
        </SectionPanel>

        <SectionPanel v-if="referral.mesure_id" :title="t('referral.measurement')">
          <LoadingState v-if="measurement.loading.value" />
          <ErrorState v-else-if="measurement.error.value" :error="measurement.error.value" />
          <dl v-else-if="measurement.data.value" class="facts facts--numbers">
            <div>
              <dt>{{ t('measurements.date') }}</dt>
              <dd>{{ fmt.date(measurement.data.value.date_mesure) }}</dd>
            </div>
            <div>
              <dt>{{ t('measurements.weight') }}</dt>
              <dd>{{ fmt.number(toNumber(measurement.data.value.poids_kg) ?? 0, 2) }}</dd>
            </div>
            <div>
              <dt>{{ t('measurements.height') }}</dt>
              <dd>{{ fmt.number(toNumber(measurement.data.value.taille_corrigee_cm) ?? 0) }}</dd>
            </div>
            <div>
              <dt>{{ t('measurements.muac') }}</dt>
              <dd>{{ measurement.data.value.pb_mm ?? t('measurements.notAvailable') }}</dd>
            </div>
            <div>
              <dt>{{ t('measurements.oedema') }}</dt>
              <dd>{{ measurement.data.value.oedemes_bilateraux === 'aucun' ? t('common.none') : measurement.data.value.oedemes_bilateraux }}</dd>
            </div>
            <div>
              <dt>{{ t('measurements.whz') }}</dt>
              <dd>{{ toNumber(measurement.data.value.whz) === null ? '–' : fmt.number(toNumber(measurement.data.value.whz), 2) }}</dd>
            </div>
            <div>
              <dt>{{ t('measurements.classification') }}</dt>
              <dd>
                {{
                  measurement.data.value.classification
                    ? t(`measurements.classifications.${measurement.data.value.classification}`)
                    : t('measurements.notClassified')
                }}
              </dd>
            </div>
            <div v-if="measurement.data.value.orientation_centre">
              <dt>{{ t('measurements.orientation') }}</dt>
              <dd>{{ t(`centreTypes.${measurement.data.value.orientation_centre}`) }}</dd>
            </div>
          </dl>
        </SectionPanel>

        <CareSection
          v-if="referral.enfant_id"
          :child-id="referral.enfant_id"
          :referral-id="referral.id"
          :csb-id="referral.csb_id"
          :can-write="auth.can('care:write') && referral.status !== 'sortie'"
        />
      </div>

      <aside class="detail__side" :aria-label="t('referral.nextAction')">
        <SectionPanel :title="t('referral.nextAction')">
          <ReferralActions
            :referral="referral"
            :can-update="auth.can('referrals:update')"
            :can-discharge="auth.can('discharge:write')"
          />
        </SectionPanel>
        <InlineAlert tone="info" class="detail__disclaimer">{{ t('referral.disclaimer') }}</InlineAlert>
      </aside>
    </div>
  </div>
</template>

<style scoped>
/* The page heading sits on the page itself: the urgency badge below says how
   urgent it is, with an icon and a word. */
.detail__head {
  margin-bottom: var(--space-5);
}

.detail__label {
  margin: 0;
  font-size: var(--text-sm);
  font-weight: 700;
}

.detail__title {
  margin: var(--space-1) 0 var(--space-3);
}

.detail__title:focus {
  outline: none;
}

.detail__late {
  font-weight: 700;
  color: var(--rouge-ink);
}

.detail__badges {
  display: flex;
  flex-wrap: wrap;
  align-items: center;
  gap: var(--space-3);
}

.detail__grid {
  display: grid;
  grid-template-columns: minmax(0, 1fr) 20rem;
  gap: var(--space-5);
  align-items: start;
}

.detail__side {
  position: sticky;
  top: 6rem;
  display: flex;
  flex-direction: column;
  gap: var(--space-4);
}

.detail__reason {
  font-size: var(--text-md);
}

.detail__child-link {
  display: inline-flex;
  align-items: center;
  min-height: var(--target);
  font-weight: 700;
}

.facts {
  display: grid;
  grid-template-columns: repeat(auto-fit, minmax(11rem, 1fr));
  gap: var(--space-3) var(--space-5);
  margin: 0;
}

.facts dt {
  font-size: var(--text-sm);
  color: var(--ink-muted);
}

.facts dd {
  margin: 0;
  font-weight: 700;
}

.facts--numbers dd {
  font-size: var(--text-lg);
}

@media (max-width: 36rem) {
  .detail__head {
    padding: var(--space-4);
  }
}

@media (max-width: 60rem) {
  .detail__grid {
    grid-template-columns: minmax(0, 1fr);
  }

  /* The next step comes first on small screens: it is the reason to be here. */
  .detail__side {
    position: static;
    order: -1;
  }
}
</style>
