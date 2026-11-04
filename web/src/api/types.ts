/**
 * Types of the TARANAKA REST API, mirroring docs/openapi.yaml
 * (components/schemas). Only the fields the dashboard uses are listed.
 */

export type Uuid = string
export type IsoDate = string // YYYY-MM-DD
export type IsoDateTime = string

// ---------- Accounts and login ----------

export type ProfileCode = 'beneficiaire' | 'asc' | 'agent_csb' | 'superviseur' | 'admin'

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

/** LoginRequest: code_totp only for an account with 2FA turned on. */
export interface LoginRequest {
  identifiant: string
  pin: string
  code_totp?: string
}

/** LoginReponse */
export interface LoginResponse extends TokenPair {
  utilisateur: Utilisateur
  /** true: the token only opens /auth/me/, /auth/changer-pin/ and /auth/2fa/. */
  totp_a_configurer: boolean
}

/** TotpEtat (GET /api/auth/2fa/) */
export interface TotpState {
  active: boolean
  requise_pour_ce_profil: boolean
  obligatoire: boolean
  a_configurer: boolean
}

/** TotpPreparation (POST /api/auth/2fa/setup/) */
export interface TotpSetup {
  secret: string
  uri: string
}

/** ChangerPinReponse (POST /api/auth/2fa/activate/): replace both tokens. */
export interface TokenRenewal extends TokenPair {
  detail: string
}

// ---------- Lists ----------

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

// ---------- Reference lists ----------

export interface Region {
  id: number
  nom: string
  province_id: number
}

export type CentreType = 'csb' | 'crenam' | 'crenas' | 'creni'

export interface Facility {
  id: number
  name: string
  type_centre: CentreType
  region_id: number
  tel: string
}

// ---------- Referrals ----------

export type Priorite = 'urgente' | 'haute' | 'normale'
export type Urgency = 'rouge' | 'orange' | 'jaune'
/** Spec §7: Référé → Reçu → Pris en charge → En suivi → Sortie. */
export type ReferralStatus = 'envoye' | 'recu' | 'pris_en_charge' | 'en_suivi' | 'sortie'
export type Origine = 'enfant' | 'grossesse'
export type DischargeOutcome = 'gueri' | 'transfere' | 'non_repondant' | 'abandon' | 'decede'

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
  urgence: Urgency
  date_referencement: IsoDateTime
  date_reception: IsoDateTime | null
  date_prise_en_charge: IsoDateTime | null
  date_sortie: IsoDateTime | null
  /** "" until the discharge. */
  issue_sortie: DischargeOutcome | ''
  /** Still "envoye" after the delay of the clinical config. */
  en_retard: boolean
  femme: { nom: string; prenom: string } | null
}

/** StatusRequest */
export interface StatusChange {
  status: ReferralStatus
  version: number
  /** Required with "sortie", refused otherwise. */
  issue_sortie?: DischargeOutcome
}

// ---------- Children and measurements ----------

export type Sexe = 'M' | 'F'
export type StatutPriseEnCharge =
  | 'aucun'
  | 'suivi'
  | 'refere'
  | 'pris_en_charge'
  | 'gueri'
  | 'abandon'
  | 'transfere'
  | 'non_repondant'
  | 'decede'

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
export type Classification = 'mas' | 'mam' | 'normal' | 'nourrisson_a_risque'

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
  /** Computed by the server from the published config; "" or null without it. */
  classification: Classification | '' | null
  orientation_centre: CentreType | '' | null
  urgence: Urgency | '' | null
  date_prochain_controle: IsoDate | null
}

/** Body of any 409 on a synced table. */
export interface VersionConflictBody<T> {
  detail: string
  code: 'conflit_version'
  current: T
}

// ---------- Care: consultations and appointments ----------

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

/** ConsultationRequest. A centre agent's csb_id and agent_medical_id are forced by the server. */
export interface ConsultationInput {
  id: Uuid
  enfant_id: Uuid
  referencement_id: Uuid | null
  csb_id?: number
  agent_medical_id?: Uuid
  date: IsoDate
  diagnostic: string
  decision: Decision
  observations: string
}

export type AppointmentType = 'controle' | 'depistage'
export type AppointmentStatus = 'prevu' | 'honore' | 'annule'

export interface Appointment extends SyncFields {
  enfant_id: Uuid
  referencement_id: Uuid | null
  csb_id: number | null
  date_prevue: IsoDate
  type_rendez_vous: AppointmentType
  statut: AppointmentStatus
  motif: string
  /** Still "prevu" after its date. */
  manque: boolean
}

export interface AppointmentInput {
  id: Uuid
  enfant_id: Uuid
  referencement_id: Uuid | null
  date_prevue: IsoDate
  type_rendez_vous: AppointmentType
  motif: string
}

// ---------- Sync conflicts ----------

export type ConflictChoice = 'serveur' | 'telephone' | 'fusion'

export interface SyncConflict {
  id: Uuid
  table_nom: string
  ligne_id: Uuid
  operation: 'create' | 'update' | 'delete'
  version_base: number | null
  version_serveur: number
  donnees_telephone: Record<string, unknown> | null
  donnees_serveur: Record<string, unknown> | null
  user_id: Uuid
  device_id: string
  statut: 'a_verifier' | 'resolu'
  created_at: IsoDateTime
}

/** ResolutionRequest */
export interface ConflictResolution {
  choix: ConflictChoice
  donnees?: Record<string, unknown>
  commentaire?: string
}

// ---------- Aggregated statistics ----------

/** Indicators of /api/stats/ (statistiques/services.py, INDICATEURS). */
export type Indicator =
  | 'depistages'
  | 'enfants_depistes'
  | 'cas_mas'
  | 'cas_mam'
  | 'nourrissons_a_risque'
  | 'referencements'
  | 'referencements_arrives'
  | 'rendez_vous_manques'
  | 'taux_arrivee_pct'
  | 'delai_moyen_arrivee_heures'
  | `sorties_${DischargeOutcome}`

/** Bloc: null = hidden by the server (also listed in "masques"). */
export interface StatsBlock {
  indicateurs: Partial<Record<Indicator, number | null>>
  masques: string[]
}

export interface StatsGroup extends StatsBlock {
  cle: string
  libelle: string
}

export interface StatsResponse {
  periode: { date_debut: IsoDate; date_fin: IsoDate }
  seuil_petits_effectifs: number
  grouper_par: 'region' | 'mois' | null
  total: StatsBlock
  groupes: StatsGroup[]
}

export interface StatsQuery {
  date_debut: IsoDate
  date_fin: IsoDate
  region?: number
  grouper_par?: 'region' | 'mois'
}
