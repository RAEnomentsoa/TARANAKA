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
 * ContactAgent: name and phone of a health worker, for staff only
 * (null for a beneficiary).
 * @typedef {Object} AgentContact
 * @property {string} nom
 * @property {string} prenom
 * @property {string} phone
 */

/**
 * @typedef {SyncFields & ReferralFields} Referral
 */

/**
 * @typedef {Object} ReferralFields
 * @property {string} code_unique
 * @property {Origine} origine
 * @property {Uuid | null} enfant_id
 * @property {Uuid | null} grossesse_id
 * @property {Uuid | null} mesure_id
 * @property {Uuid} asc_id
 * @property {AgentContact | null} asc The community agent who referred, to call back.
 * @property {number} csb_id
 * @property {Priorite} priorite
 * @property {string} motif
 * @property {ReferralStatus} status
 * @property {Urgency} urgence
 * @property {IsoDateTime} date_referencement
 * @property {IsoDateTime | null} date_reception
 * @property {IsoDateTime | null} date_prise_en_charge
 * @property {IsoDateTime | null} date_suivi Null after a discharge means the case skipped "en suivi".
 * @property {IsoDateTime | null} date_sortie
 * @property {DischargeOutcome | ''} issue_sortie "" until the discharge.
 * @property {boolean} en_retard Still "envoye" after the delay of the clinical config.
 * @property {{ nom: string, prenom: string } | null} femme
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
 * @typedef {SyncFields & ChildFields} Child
 */

/**
 * @typedef {Object} ChildFields
 * @property {string} nom
 * @property {Uuid | null} mere_id
 * @property {Uuid} asc_id
 * @property {Uuid | null} grossesse_id
 * @property {number} region_id
 * @property {IsoDate} date_naissance
 * @property {Sexe} sexe
 * @property {StatutPriseEnCharge} statut_prise_en_charge
 */

/** @typedef {'vert' | 'orange' | 'rouge'} Alerte */
/** @typedef {'aucun' | '+' | '++' | '+++'} Oedemes */
/** @typedef {'mas' | 'mam' | 'normal' | 'nourrisson_a_risque'} Classification */

/**
 * @typedef {SyncFields & MeasurementFields} Measurement
 */

/**
 * @typedef {Object} MeasurementFields
 * @property {Uuid} enfant_id
 * @property {Uuid} asc_id
 * @property {IsoDate} date_mesure
 * @property {string} poids_kg DRF sends decimals as strings.
 * @property {string} taille_cm
 * @property {'couche' | 'debout'} position
 * @property {number | null} pb_mm
 * @property {Oedemes} oedemes_bilateraux
 * @property {number} age_jour
 * @property {number} age_mois
 * @property {string} taille_corrigee_cm
 * @property {string | null} waz
 * @property {string | null} haz
 * @property {string | null} whz
 * @property {boolean} flag_aberrant
 * @property {Alerte} alerte
 * @property {Classification | '' | null} classification Computed by the server from the published config; "" or null without it.
 * @property {CentreType | '' | null} orientation_centre
 * @property {Urgency | '' | null} urgence
 * @property {IsoDate | null} date_prochain_controle
 */

/**
 * Body of any 409 on a synced table.
 * @template T
 * @typedef {Object} VersionConflictBody
 * @property {string} detail
 * @property {'conflit_version'} code
 * @property {T} current
 */

// ---------- Care: consultations and appointments ----------

/** @typedef {'conseil' | 'reference' | 'prise_en_charge'} Decision */

/**
 * @typedef {SyncFields & ConsultationFields} Consultation
 */

/**
 * @typedef {Object} ConsultationFields
 * @property {Uuid} enfant_id
 * @property {Uuid | null} mesure_id
 * @property {Uuid | null} referencement_id
 * @property {number} csb_id
 * @property {Uuid} agent_medical_id
 * @property {IsoDate} date
 * @property {string} diagnostic
 * @property {Decision} decision
 * @property {string} observations
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
 * @typedef {SyncFields & AppointmentFields} Appointment
 */

/**
 * @typedef {Object} AppointmentFields
 * @property {Uuid} enfant_id
 * @property {Uuid | null} referencement_id
 * @property {number | null} csb_id
 * @property {IsoDate} date_prevue
 * @property {AppointmentType} type_rendez_vous
 * @property {AppointmentStatus} statut
 * @property {string} motif
 * @property {boolean} manque Still "prevu" after its date.
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
 * @property {Record<string, unknown>} donnees_telephone Empty object for a deletion.
 * @property {Record<string, unknown>} donnees_serveur
 * @property {Uuid} user_id
 * @property {AgentContact | null} expediteur Who sent the phone's version.
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

// ---------- WHO growth standards (GET /api/who-reference/) ----------

/**
 * wfa: weight for age, lhfa: length/height for age (keys in days);
 * wfl: weight for length, wfh: weight for height (keys in cm).
 * @typedef {'wfa' | 'lhfa' | 'wfl' | 'wfh'} WhoIndicator
 */

/**
 * PointOms. openapi.yaml describes the keys and LMS values as decimal
 * strings, the server sends numbers: both are read with Number().
 * "courbes" maps a z-score ("-3", "-2", "0", "2", "3") to its value.
 * @typedef {Object} WhoPoint
 * @property {string | number} cle
 * @property {string | number} l
 * @property {string | number} m
 * @property {string | number} s
 * @property {string} mesure_type
 * @property {Record<string, number>} courbes
 */

/**
 * ReferenceOms
 * @typedef {Object} WhoReference
 * @property {string} source
 * @property {WhoIndicator} indicateur
 * @property {Sexe} sexe
 * @property {string} unite_cle "jours" or "cm"
 * @property {string} unite_valeur "kg" or "cm"
 * @property {WhoPoint[]} points
 */

/**
 * @typedef {Object} WhoReferenceQuery
 * @property {WhoIndicator} indicateur
 * @property {Sexe} sexe
 * @property {number} [cle_min]
 * @property {number} [cle_max]
 * @property {number} [pas] Keep one key every `pas` (days or cm).
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
