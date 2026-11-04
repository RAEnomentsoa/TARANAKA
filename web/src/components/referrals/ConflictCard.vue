<script setup lang="ts">
import { computed, reactive, ref } from 'vue'
import { useI18n } from 'vue-i18n'
import type { ConflictResolution, SyncConflict } from '@/api/types'
import AppButton from '@/components/ui/AppButton.vue'
import ConfirmDialog from '@/components/ui/ConfirmDialog.vue'
import { useFormatters } from '@/composables/useFormatters'
import { buildResolution, differingFields, displayValue, type Side } from '@/utils/conflicts'

/**
 * One sync conflict. Both versions stay visible; the professional picks a
 * side per differing field. Nothing is chosen for them by default.
 */
const props = defineProps<{ conflict: SyncConflict; busy: boolean }>()
const emit = defineEmits<{ resolve: [resolution: ConflictResolution] }>()

const { t, te } = useI18n()
const fmt = useFormatters()
const fields = computed(() => differingFields(props.conflict))
const choices = reactive<Record<string, Side | undefined>>({})
const confirming = ref(false)
const complete = computed(() => fields.value.every((f) => choices[f]))

const tableLabel = computed(() =>
  te(`conflicts.tables.${props.conflict.table_nom}`)
    ? t(`conflicts.tables.${props.conflict.table_nom}`)
    : t('conflicts.tables.other', { name: props.conflict.table_nom }),
)

function chooseAll(side: Side): void {
  for (const field of fields.value) choices[field] = side
}

function confirm(): void {
  confirming.value = false
  emit('resolve', buildResolution(props.conflict, choices as Record<string, Side>))
}
</script>

<template>
  <article class="conflict" :aria-labelledby="`conflict-${conflict.id}`">
    <header class="conflict__head">
      <h2 :id="`conflict-${conflict.id}`" class="conflict__title">{{ tableLabel }}</h2>
      <p class="muted">
        {{ t('conflicts.detectedAt', { date: fmt.dateTime(conflict.date_creation) }) }} —
        {{ t('conflicts.differentFields', fields.length) }}
      </p>
    </header>

    <div class="conflict__quick">
      <AppButton variant="secondary" @click="chooseAll('serveur')">{{ t('conflicts.keepServer') }}</AppButton>
      <AppButton variant="secondary" @click="chooseAll('appareil')">{{ t('conflicts.keepDevice') }}</AppButton>
    </div>

    <div class="table-scroll">
      <table class="conflict__table">
        <caption class="visually-hidden">{{ tableLabel }}</caption>
        <thead>
          <tr>
            <th scope="col">{{ t('conflicts.field') }}</th>
            <th scope="col">
              {{ t('conflicts.serverVersion', { version: conflict.version_serveur.version }) }}
              <span class="conflict__meta">{{ t('conflicts.deviceLabel', { device: conflict.version_serveur.device_id || '—', date: fmt.dateTime(conflict.version_serveur.date) }) }}</span>
            </th>
            <th scope="col">
              {{ t('conflicts.deviceVersion', { version: conflict.version_appareil.version }) }}
              <span class="conflict__meta">{{ t('conflicts.deviceLabel', { device: conflict.version_appareil.device_id || '—', date: fmt.dateTime(conflict.version_appareil.date) }) }}</span>
            </th>
          </tr>
        </thead>
        <tbody>
          <tr v-for="field in fields" :key="field">
            <th scope="row"><code>{{ field }}</code></th>
            <td v-for="side in (['serveur', 'appareil'] as const)" :key="side">
              <label class="choice" :class="{ 'choice--picked': choices[field] === side }">
                <input
                  v-model="choices[field]"
                  type="radio"
                  :name="`conflict-${conflict.id}-${field}`"
                  :value="side"
                  :aria-label="`${t('conflicts.chooseField', { field })} : ${displayValue(side === 'serveur' ? conflict.version_serveur.donnees[field] : conflict.version_appareil.donnees[field])}`"
                />
                <span>{{ displayValue(side === 'serveur' ? conflict.version_serveur.donnees[field] : conflict.version_appareil.donnees[field]) }}</span>
              </label>
            </td>
          </tr>
        </tbody>
      </table>
    </div>

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
  border-top: 6px solid var(--rouge-bar);
  border-radius: var(--radius-md);
  padding: var(--space-5);
}

.conflict__title {
  font-size: var(--text-lg);
  margin-bottom: var(--space-1);
}

.conflict__quick {
  display: flex;
  flex-wrap: wrap;
  gap: var(--space-3);
  margin: var(--space-4) 0;
}

.conflict__meta {
  display: block;
  font-weight: 400;
  color: var(--ink-muted);
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
  border: 2px solid var(--sky-200);
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
  border-color: var(--primary);
  background: var(--sky-50);
  font-weight: 700;
}

.conflict__foot {
  display: flex;
  justify-content: flex-end;
  margin-top: var(--space-4);
}
</style>
