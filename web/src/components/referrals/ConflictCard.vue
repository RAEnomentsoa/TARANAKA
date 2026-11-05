<script setup>
import { computed, reactive, ref, useId } from 'vue'
import { useI18n } from 'vue-i18n'
import AppButton from '@/components/ui/AppButton.vue'
import AppField from '@/components/ui/AppField.vue'
import AgentContact from '@/components/ui/AgentContact.vue'
import ConfirmDialog from '@/components/ui/ConfirmDialog.vue'
import { useFormatters } from '@/composables/useFormatters'
import { buildResolution, differingFields, displayValue, sideData } from '@/utils/conflicts'

/** @typedef {import('@/api/types').ConflictResolution} ConflictResolution */
/** @typedef {import('@/api/types').SyncConflict} SyncConflict */
/** @typedef {import('@/utils/conflicts').Side} Side */

/**
 * One sync conflict. Both versions stay visible; the professional picks a
 * side per differing field. Nothing is chosen for them by default (D10).
 */
const props = defineProps({
  /** @type {import('vue').PropType<SyncConflict>} */
  conflict: { type: Object, required: true },
  busy: { type: Boolean, required: true },
})
/** resolve(resolution: ConflictResolution) */
const emit = defineEmits(['resolve'])

/** @type {Side[]} */
const SIDES = ['serveur', 'telephone']
const { t, te } = useI18n()
const fmt = useFormatters()
const id = useId()
const isDeletion = computed(() => props.conflict.operation === 'delete')
const fields = computed(() => (isDeletion.value ? [] : differingFields(props.conflict)))
/** @type {Record<string, Side | undefined>} */
const choices = reactive({})
/** @type {import('vue').Ref<Side | null>} */
const deletionChoice = ref(null)
const comment = ref('')
const confirming = ref(false)
const complete = computed(() =>
  isDeletion.value ? deletionChoice.value !== null : fields.value.every((f) => choices[f]),
)

const tableLabel = computed(() =>
  te(`conflicts.tables.${props.conflict.table_nom}`)
    ? t(`conflicts.tables.${props.conflict.table_nom}`)
    : t('conflicts.tables.other', { name: props.conflict.table_nom }),
)

/**
 * @param {Side} side
 * @param {string} field
 * @returns {string}
 */
function value(side, field) {
  return displayValue(sideData(props.conflict, side)[field])
}

/** @param {Side} side */
function chooseAll(side) {
  if (isDeletion.value) deletionChoice.value = side
  for (const field of fields.value) choices[field] = side
}

function confirm() {
  confirming.value = false
  emit(
    'resolve',
    isDeletion.value && deletionChoice.value
      ? { choix: deletionChoice.value, ...(comment.value.trim() ? { commentaire: comment.value.trim() } : {}) }
      : buildResolution(props.conflict, choices, comment.value),
  )
}
</script>

<template>
  <article class="conflict" :aria-labelledby="`${id}-title`">
    <header class="conflict__head">
      <h2 :id="`${id}-title`" class="conflict__title">{{ tableLabel }}</h2>
      <p class="muted">
        {{ t(`conflicts.operations.${conflict.operation}`) }} —
        {{ t('conflicts.detectedAt', { date: fmt.dateTime(conflict.created_at) }) }} —
        {{ t('conflicts.deviceLabel', { device: conflict.device_id || '—' }) }}
      </p>
      <div class="conflict__sender">
        <span class="muted">{{ t('conflicts.sentBy') }}</span>
        <AgentContact :contact="conflict.expediteur" />
      </div>
      <p v-if="!isDeletion" class="muted">{{ t('conflicts.differentFields', fields.length) }}</p>
    </header>

    <div class="conflict__quick">
      <AppButton variant="secondary" :aria-pressed="isDeletion ? deletionChoice === 'serveur' : undefined" @click="chooseAll('serveur')">
        {{ t('conflicts.keepServer') }}
      </AppButton>
      <AppButton variant="secondary" :aria-pressed="isDeletion ? deletionChoice === 'telephone' : undefined" @click="chooseAll('telephone')">
        {{ t('conflicts.keepDevice') }}
      </AppButton>
    </div>

    <div v-if="!isDeletion" class="table-scroll">
      <table class="conflict__table stack-on-mobile">
        <caption class="visually-hidden">{{ tableLabel }}</caption>
        <thead>
          <tr>
            <th scope="col">{{ t('conflicts.field') }}</th>
            <th scope="col">{{ t('conflicts.serverVersion', { version: conflict.version_serveur }) }}</th>
            <th scope="col">{{ t('conflicts.deviceVersion') }}</th>
          </tr>
        </thead>
        <tbody>
          <tr v-for="field in fields" :key="field">
            <th scope="row"><code>{{ field }}</code></th>
            <td
              v-for="side in SIDES"
              :key="side"
              :data-label="side === 'serveur' ? t('conflicts.serverVersion', { version: conflict.version_serveur }) : t('conflicts.deviceVersion')"
            >
              <label class="choice" :class="{ 'choice--picked': choices[field] === side }">
                <input
                  v-model="choices[field]"
                  type="radio"
                  :name="`${id}-${field}`"
                  :value="side"
                  :aria-label="`${t('conflicts.chooseField', { field })} : ${value(side, field)}`"
                />
                <span>{{ value(side, field) }}</span>
              </label>
            </td>
          </tr>
        </tbody>
      </table>
    </div>

    <AppField v-slot="{ id: fieldId, describedBy }" class="conflict__comment" :label="t('conflicts.comment')" :hint="t('conflicts.commentHelp')" optional>
      <textarea :id="fieldId" v-model="comment" maxlength="500" :aria-describedby="describedBy" />
    </AppField>

    <footer class="conflict__foot">
      <AppButton :disabled="!complete" :loading="busy" @click="confirming = true">{{ t('conflicts.resolve') }}</AppButton>
    </footer>

    <ConfirmDialog
      :open="confirming"
      :title="t('conflicts.resolve')"
      :message="t('conflicts.confirm')"
      :busy="busy"
      @confirm="confirm"
      @cancel="confirming = false"
    />
  </article>
</template>

<style scoped>
.conflict {
  background: var(--white);
  border: 1px solid var(--sky-200);
  border-left: 6px solid var(--rouge-bar);
  border-radius: var(--radius-md);
  padding: var(--space-5);
}

.conflict__title {
  font-size: var(--text-lg);
  margin-bottom: var(--space-1);
}

.conflict__head p {
  margin-bottom: var(--space-1);
}

.conflict__sender {
  display: flex;
  flex-wrap: wrap;
  align-items: baseline;
  gap: var(--space-2);
  margin-bottom: var(--space-1);
}

.conflict__quick {
  display: flex;
  flex-wrap: wrap;
  gap: var(--space-3);
  margin: var(--space-4) 0;
}

.conflict__quick :deep([aria-pressed='true']) {
  background: var(--sky-100);
  border-width: 3px;
}

.conflict__table td {
  padding: var(--space-1);
}

.choice {
  display: flex;
  align-items: center;
  gap: var(--space-3);
  min-height: var(--target);
  padding: var(--space-2) var(--space-3);
  border: 1px solid var(--field-border);
  border-radius: var(--radius-sm);
  cursor: pointer;
  word-break: break-word;
}

.choice input {
  flex: none;
  width: 1.25rem;
  height: 1.25rem;
  accent-color: var(--primary);
}

.choice--picked {
  border: 2px solid var(--primary);
  background: var(--sky-50);
  font-weight: 700;
}

.conflict__comment {
  margin-top: var(--space-4);
}

.conflict__foot {
  display: flex;
  justify-content: flex-end;
  margin-top: var(--space-4);
}

@media (max-width: 40rem) {
  .conflict {
    padding: var(--space-4);
  }
}
</style>
