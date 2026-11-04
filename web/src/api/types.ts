/**
 * Types of the TARANAKA REST API.
 *
 * "Existing" types mirror the Django serializers in Backend_serveur/.
 * "Proposed" types describe endpoints the dashboard needs but the backend
 * does not offer yet: see docs/API_ISSUES.md for each of them.
 */

export type Uuid = string
export type IsoDate = string // YYYY-MM-DD
export type IsoDateTime = string

// ---------- Existing: comptes ----------

/** Profile codes known to the backend, plus the proposed "superviseur". */
export type ProfileCode = 'beneficiaire' | 'asc' | 'agent_csb' | 'admin' | 'superviseur'

export interface Profile {
  code: ProfileCode | string
  libelle: string
}

export interface Utilisateur {
  id: Uuid
  nom: string
  prenom: string
  profile: Profile
  region_id: number | null
  csb_id: number | null
}

export interface TokenPair {
  access: string
  refresh: string
}

export interface LoginSuccess extends TokenPair {
  utilisateur: Utilisateur
}

/** Proposed: second step of the login when TOTP is required. */
export interface LoginTotpChallenge {
  double_auth: {
    etape: 'verification' | 'enrolement'
    jeton: string
    /** Only for "enrolement": otpauth:// URI to show as a QR code. */
    otpauth_uri?: string
  }
}

export type LoginResponse = LoginSuccess | LoginTotpChallenge

// ---------- Existing: pagination and sync fields ----------

export interface Paginated<T> {
  count: number
  next: string | null
  previous: string | null
  results: T[]
}

export interface SyncFields {
  id: Uuid
  version: number
  created_at: IsoDateTime
  updated_at: IsoDateTime
  device_id: string
  deleted_at: IsoDateTime | null
}

// ---------- Existing: référentiel ----------

export interface Region {
  id: number
  nom: string
  province_id: number
}

export interface Facility {
  id: number
  name: string
  region_id: number
  tel: string
}

// ---------- Existing: referrals ----------

export type Priorite = 'urgente' | 'haute' | 'normale'
export type ReferralStatus = 'envoye' | 'recu' | 'vu' | 'pris_en_charge' | 'clos'
export type Origine = 'enfant' | 'grossesse'

export interface Referral extends SyncFields {
  code_unique: string
  origine: Origine
  enfant_id: Uuid | null
  grossesse_id: Uuid | null
  mesure_id: Uuid | null
  asc_id: Uuid
  csb_id: number
  priorite: Priorite
  motif: string
  status: ReferralStatus
  femme: { nom: string; prenom: string } | null
  /** Proposed: outcome stored when the referral is closed. */
  issue_sortie?: DischargeOutcome | null
}

/** Proposed outcomes of a discharge (spec section 7). */
export type DischargeOutcome = 'gueri' | 'transfere' | 'non_repondant' | 'abandon' | 'deces'

export interface StatusChange {
  status: ReferralStatus
  version: number
  /** Proposed: only with status "clos". Ignored by the current backend. */
  issue_sortie?: DischargeOutcome
  date_sortie?: IsoDate
  notes?: string
}

// ---------- Existing: children and measurements ----------

export type Sexe = 'M' | 'F'
export type StatutPriseEnCharge =
  | 'aucun'
  | 'suivi'
  | 'refere'
  | 'pris_en_charge'
  | 'gueri'
  | 'abandon'

export interface Child extends SyncFields {
  nom: string
  mere_id: Uuid | null
  asc_id: Uuid
  grossesse_id: Uuid | null
  region_id: number
  date_naissance: IsoDate
  sexe: Sexe
  statut_prise_en_charge: StatutPriseEnCharge
}

export type Alerte = 'vert' | 'orange' | 'rouge'
export type Oedemes = 'aucun' | '+' | '++' | '+++'

export interface Measurement extends SyncFields {
  enfant_id: Uuid
  asc_id: Uuid
  date_mesure: IsoDate
  /** DRF sends decimals as strings. */
  poids_kg: string
  taille_cm: string
  position: 'couche' | 'debout'
  pb_mm: number | null
  oedemes_bilateraux: Oedemes
  age_jour: number
  age_mois: number
  taille_corrigee_cm: string
  waz: string | null
  haz: string | null
  whz: string | null
  flag_aberrant: boolean
  alerte: Alerte
  motif_alerte: string
  ref_oms: string
}

/** Existing on HTTP 409 from any synced table. */
export interface VersionConflictBody<T> {
  detail: string
  code: 'conflit_version'
  current: T
}

// ---------- Proposed: care (consultation_nutritionnelle) ----------

export type Decision = 'conseil' | 'reference' | 'prise_en_charge'

export interface Consultation extends SyncFields {
  enfant_id: Uuid
  mesure_id: Uuid | null
  referencement_id: Uuid | null
  csb_id: number
  agent_medical_id: Uuid
  date: IsoDate
  diagnostic: string
  decision: Decision
  observations: string
}

export interface ConsultationInput {
  id: Uuid
  enfant_id: Uuid
  referencement_id: Uuid | null
  csb_id: number
  date: IsoDate
  diagnostic: string
  decision: Decision
  observations: string
}

// ---------- Proposed: follow-up appointments ----------

export type FollowUpStatus = 'prevu' | 'honore' | 'manque'

export interface FollowUp extends SyncFields {
  enfant_id: Uuid
  referencement_id: Uuid | null
  date_prevue: IsoDate
  motif: string
  statut: FollowUpStatus
}

export interface FollowUpInput {
  id: Uuid
  enfant_id: Uuid
  referencement_id: Uuid | null
  date_prevue: IsoDate
  motif: string
}

// ---------- Proposed: sync conflicts ----------

export interface ConflictVersion {
  version: number
  device_id: string
  date: IsoDateTime
  donnees: Record<string, unknown>
}

export interface SyncConflict {
  id: number
  table_nom: string
  ligne_id: Uuid
  version_serveur: ConflictVersion
  version_appareil: ConflictVersion
  date_creation: IsoDateTime
}

export type ConflictChoice = 'serveur' | 'appareil' | 'fusion'

export interface ConflictResolution {
  choix: ConflictChoice
  /** Only for "fusion": the merged values, field by field. */
  donnees?: Record<string, unknown>
}

// ---------- Proposed: aggregated statistics ----------

/** A count the server may already hide (null) for small groups. */
export type Count = number | null

export interface StatsMetrics {
  depistages: Count
  mam: Count
  mas: Count
  referencements: Count
  referencements_arrives: Count
  /** Mean delay between referral and arrival, in hours. */
  delai_moyen_arrivee_heures: number | null
  rdv_manques: Count
}

export interface StatsZoneRow extends StatsMetrics {
  zone_id: number
  zone_nom: string
}

export interface StatsPeriodRow {
  periode: string // YYYY-MM
  depistages: Count
  mam: Count
  mas: Count
}

export interface StatsResponse {
  periode: { debut: IsoDate; fin: IsoDate }
  totaux: StatsMetrics
  issues_sortie: Record<DischargeOutcome, Count>
  par_zone: StatsZoneRow[]
  par_periode: StatsPeriodRow[]
}

export interface StatsQuery {
  date_debut: IsoDate
  date_fin: IsoDate
  region_id?: number
  csb_id?: number
}
