/**
 * Types of the TARANAKA REST API, mirroring docs/openapi.yaml
 * (components/schemas). Only the fields the dashboard uses are listed.
 */

/** @typedef {string} Uuid */
/** @typedef {string} IsoDate */ // YYYY-MM-DD
/** @typedef {string} IsoDateTime */

// ---------- Accounts and login ----------

/** @typedef {'beneficiaire' | 'asc' | 'agent_csb' | 'superviseur' | 'admin'} ProfileCode */

/**
 * @typedef {Object} Profile
 * @property {ProfileCode | string} code
 * @property {string} libelle
 */

/**
 * @typedef {Object} Utilisateur
 * @property {Uuid} id
 * @property {string} nom
 * @property {string} prenom
 * @property {Profile} profile
 * @property {number | null} region_id
 * @property {number | null} csb_id
 */

/**
 * @typedef {Object} TokenPair
 * @property {string} access
 * @property {string} refresh
 */

/**
 * LoginRequest: code_totp only for an account with 2FA turned on.
 * @typedef {Object} LoginRequest
 * @property {string} identifiant
 * @property {string} pin
 * @property {string} [code_totp]
 */

/**
 * LoginReponse
 * - totp_a_configurer: true: the token only opens /auth/me/, /auth/changer-pin/ and /auth/2fa/.
 * @typedef {TokenPair & { utilisateur: Utilisateur, totp_a_configurer: boolean }} LoginResponse
 */

/**
 * TotpEtat (GET /api/auth/2fa/)
 * @typedef {Object} TotpState
 * @property {boolean} active
 * @property {boolean} requise_pour_ce_profil
 * @property {boolean} obligatoire
 * @property {boolean} a_configurer
 */

/**
 * TotpPreparation (POST /api/auth/2fa/setup/)
 * @typedef {Object} TotpSetup
 * @property {string} secret
 * @property {string} uri
 */

/**
 * ChangerPinReponse (POST /api/auth/2fa/activate/): replace both tokens.
 * @typedef {TokenPair & { detail: string }} TokenRenewal
 */

// ---------- Lists ----------

/**
 * @typedef {Object} Paginated
 * @property {number} count
 * @property {string | null} next
 * @property {string | null} previous
 * @property {T[]} results
 */

/**
 * @typedef {Object} SyncFields
 * @property {Uuid} id
 * @property {number} version
 * @property {IsoDateTime} created_at
 * @property {IsoDateTime} updated_at
 * @property {string} device_id
 * @property {IsoDateTime | null} deleted_at
 */

// ---------- Reference lists ----------

/**
 * @typedef {Object} Region
 * @property {number} id
 * @property {string} nom
 * @property {number} province_id
 */

/** @typedef {'csb' | 'crenam' | 'crenas' | 'creni'} CentreType */

/**
 * @typedef {Object} Facility
 * @property {number} id
 * @property {string} name
 * @property {CentreType} type_centre
 * @property {number} region_id
 * @property {string} tel
 */

// ---------- Referrals ----------

/** @typedef {'urgente' | 'haute' | 'normale'} Priorite */
/** @typedef {'rouge' | 'orange' | 'jaune'} Urgency */
/**
 * Spec §7: Référé → Reçu → Pris en charge → En suivi → Sortie.
 * @typedef {'envoye' | 'recu' | 'pris_en_charge' | 'en_suivi' | 'sortie'} ReferralStatus
 */
/** @typedef {'enfant' | 'grossesse'} Origine */
/**
 * @typedef {'gueri' | 'transfere' | 'non_repondant' | 'abandon' | 'decede'} DischargeOutcome
 */

/**
 * - issue_sortie: "" until the discharge.
 * - en_retard: Still "envoye" after the delay of the clinical config.
 * @typedef {SyncFields & { code_unique: string, origine: Origine, enfant_id: Uuid | null, grossesse_id: Uuid | null, mesure_id: Uuid | null, asc_id: Uuid, csb_id: number, priorite: Priorite, motif: string, status: ReferralStatus, urgence: Urgency, date_referencement: IsoDateTime, date_reception: IsoDateTime | null, date_prise_en_charge: IsoDateTime | null, date_sortie: IsoDateTime | null, issue_sortie: DischargeOutcome | '', en_retard: boolean, femme: { nom: string, prenom: string } | null }} Referral
 */

/**
 * StatusRequest
 * @typedef {Object} StatusChange
 * @property {ReferralStatus} status
 * @property {number} version
 * @property {DischargeOutcome} [issue_sortie] Required with "sortie", refused otherwise.
 */

// ---------- Children and measurements ----------

/** @typedef {'M' | 'F'} Sexe */
/**
 * @typedef {(
 *   | 'aucun'
 *   | 'suivi'
 *   | 'refere'
 *   | 'pris_en_charge'
 *   | 'gueri'
 *   | 'abandon'
 *   | 'transfere'
 *   | 'non_repondant'
 *   | 'decede'
 * )} StatutPriseEnCharge
 */

/**
 * @typedef {SyncFields & { nom: string, mere_id: Uuid | null, asc_id: Uuid, grossesse_id: Uuid | null, region_id: number, date_naissance: IsoDate, sexe: Sexe, statut_prise_en_charge: StatutPriseEnCharge }} Child
 */

/** @typedef {'vert' | 'orange' | 'rouge'} Alerte */
/** @typedef {'aucun' | '+' | '++' | '+++'} Oedemes */
/** @typedef {'mas' | 'mam' | 'normal' | 'nourrisson_a_risque'} Classification */

/**
 * - poids_kg: DRF sends decimals as strings.
 * - classification: Computed by the server from the published config; "" or null without it.
 * @typedef {SyncFields & { enfant_id: Uuid, asc_id: Uuid, date_mesure: IsoDate, poids_kg: string, taille_cm: string, position: 'couche' | 'debout', pb_mm: number | null, oedemes_bilateraux: Oedemes, age_jour: number, age_mois: number, taille_corrigee_cm: string, waz: string | null, haz: string | null, whz: string | null, flag_aberrant: boolean, alerte: Alerte, classification: Classification | '' | null, orientation_centre: CentreType | '' | null, urgence: Urgency | '' | null, date_prochain_controle: IsoDate | null }} Measurement
 */

/**
 * Body of any 409 on a synced table.
 * @typedef {Object} VersionConflictBody
 * @property {string} detail
 * @property {'conflit_version'} code
 * @property {T} current
 */

// ---------- Care: consultations and appointments ----------

/** @typedef {'conseil' | 'reference' | 'prise_en_charge'} Decision */

/**
 * @typedef {SyncFields & { enfant_id: Uuid, mesure_id: Uuid | null, referencement_id: Uuid | null, csb_id: number, agent_medical_id: Uuid, date: IsoDate, diagnostic: string, decision: Decision, observations: string }} Consultation
 */

/**
 * ConsultationRequest. A centre agent's csb_id and agent_medical_id are forced by the server.
 * @typedef {Object} ConsultationInput
 * @property {Uuid} id
 * @property {Uuid} enfant_id
 * @property {Uuid | null} referencement_id
 * @property {number} [csb_id]
 * @property {Uuid} [agent_medical_id]
 * @property {IsoDate} date
 * @property {string} diagnostic
 * @property {Decision} decision
 * @property {string} observations
 */

/** @typedef {'controle' | 'depistage'} AppointmentType */
/** @typedef {'prevu' | 'honore' | 'annule'} AppointmentStatus */

/**
 * - manque: Still "prevu" after its date.
 * @typedef {SyncFields & { enfant_id: Uuid, referencement_id: Uuid | null, csb_id: number | null, date_prevue: IsoDate, type_rendez_vous: AppointmentType, statut: AppointmentStatus, motif: string, manque: boolean }} Appointment
 */

/**
 * @typedef {Object} AppointmentInput
 * @property {Uuid} id
 * @property {Uuid} enfant_id
 * @property {Uuid | null} referencement_id
 * @property {IsoDate} date_prevue
 * @property {AppointmentType} type_rendez_vous
 * @property {string} motif
 */

// ---------- Sync conflicts ----------

/** @typedef {'serveur' | 'telephone' | 'fusion'} ConflictChoice */

/**
 * @typedef {Object} SyncConflict
 * @property {Uuid} id
 * @property {string} table_nom
 * @property {Uuid} ligne_id
 * @property {'create' | 'update' | 'delete'} operation
 * @property {number | null} version_base
 * @property {number} version_serveur
 * @property {Record<string, unknown> | null} donnees_telephone
 * @property {Record<string, unknown> | null} donnees_serveur
 * @property {Uuid} user_id
 * @property {string} device_id
 * @property {'a_verifier' | 'resolu'} statut
 * @property {IsoDateTime} created_at
 */

/**
 * ResolutionRequest
 * @typedef {Object} ConflictResolution
 * @property {ConflictChoice} choix
 * @property {Record<string, unknown>} [donnees]
 * @property {string} [commentaire]
 */

// ---------- Aggregated statistics ----------

/**
 * Indicators of /api/stats/ (statistiques/services.py, INDICATEURS).
 * @typedef {(
 *   | 'depistages'
 *   | 'enfants_depistes'
 *   | 'cas_mas'
 *   | 'cas_mam'
 *   | 'nourrissons_a_risque'
 *   | 'referencements'
 *   | 'referencements_arrives'
 *   | 'rendez_vous_manques'
 *   | 'taux_arrivee_pct'
 *   | 'delai_moyen_arrivee_heures'
 *   | `sorties_${DischargeOutcome}`
 * )} Indicator
 */

/**
 * Bloc: null = hidden by the server (also listed in "masques").
 * @typedef {Object} StatsBlock
 * @property {Partial<Record<Indicator, number | null>>} indicateurs
 * @property {string[]} masques
 */

/** @typedef {StatsBlock & { cle: string, libelle: string }} StatsGroup */

/**
 * @typedef {Object} StatsResponse
 * @property {{ date_debut: IsoDate, date_fin: IsoDate }} periode
 * @property {number} seuil_petits_effectifs
 * @property {'region' | 'mois' | null} grouper_par
 * @property {StatsBlock} total
 * @property {StatsGroup[]} groupes
 */

/**
 * @typedef {Object} StatsQuery
 * @property {IsoDate} date_debut
 * @property {IsoDate} date_fin
 * @property {number} [region]
 * @property {'region' | 'mois'} [grouper_par]
 */
