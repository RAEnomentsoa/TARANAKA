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
 * @property {{ id: Uuid, nom: string, prenom: string } | null} femme
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
 * @property {{ id: Uuid, nom: string, prenom: string } | null} mere
 * @property {Uuid | null} asc_id
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
 *   | 'beneficiaires_actives'
 *   | 'grossesses_suivies'
 *   | 'signes_danger'
 *   | 'referencements_grossesse'
 *   | 'referencements_grossesse_arrives'
 *   | 'enfants_vaccines'
 *   | 'taux_arrivee_pct'
 *   | 'taux_arrivee_grossesse_pct'
 *   | 'couverture_vaccinale_pct'
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

// ---------- Accounts: access requests (D15) and community agents ----------

/** @typedef {'agent_csb' | 'superviseur'} RequestedProfile */
/** @typedef {'en_attente' | 'approuvee' | 'refusee'} AccessRequestStatus */

/**
 * Public form of the login page.
 * @typedef {Object} AccessRequestForm
 * @property {string} nom
 * @property {string} prenom
 * @property {string} email
 * @property {string} phone
 * @property {string} identifiant
 * @property {string} pin
 * @property {RequestedProfile} profil_demande
 * @property {number | null} csb_id Required for agent_csb.
 * @property {number | null} region_id Supervisor: null = national.
 * @property {string} fonction
 * @property {string} message
 */

/**
 * What the admin reviews. Never the PIN.
 * @typedef {Object} AccessRequest
 * @property {Uuid} id
 * @property {string} nom
 * @property {string} prenom
 * @property {string} email
 * @property {string} phone
 * @property {string} identifiant
 * @property {RequestedProfile} profil_demande
 * @property {number | null} region_id
 * @property {string | null} [region_nom]
 * @property {number | null} csb_id
 * @property {string | null} [csb_nom]
 * @property {CentreType | null} [csb_type]
 * @property {string} fonction
 * @property {string} message
 * @property {AccessRequestStatus} statut
 * @property {string} [motif_refus]
 * @property {{ id: Uuid, nom: string, prenom: string } | null} [traitee_par]
 * @property {IsoDateTime | null} [date_traitement]
 * @property {Uuid | null} [utilisateur_id]
 * @property {IsoDateTime} date_creation
 */

/**
 * @typedef {Object} AccessRequestCorrections
 * @property {RequestedProfile} [profil_demande]
 * @property {number | null} [csb_id]
 * @property {number | null} [region_id]
 */

/**
 * @typedef {Object} AccessRequestOptions
 * @property {{ id: number, nom: string }[]} regions
 * @property {{ id: number, name: string, type_centre: CentreType, region_id: number }[]} centres
 */

/**
 * An account from /api/profiles/ (for a supervisor: the ASCs of their region).
 * @typedef {Object} AgentAccount
 * @property {Uuid} id
 * @property {string} identifiant
 * @property {string} nom
 * @property {string} prenom
 * @property {string} email
 * @property {string} phone
 * @property {Profile} profile
 * @property {number | null} region_id
 * @property {boolean} is_active
 * @property {IsoDateTime} date_creation
 */

/**
 * @typedef {Object} NewAgent
 * @property {string} identifiant
 * @property {string} nom
 * @property {string} prenom
 * @property {string} phone
 * @property {string} pin
 */

// ---------- Connected beneficiaries (D16) ----------

/**
 * One line of /api/beneficiaries/: enough to recognise her, no health data.
 * @typedef {Object} BeneficiaryRow
 * @property {Uuid} id
 * @property {string} prenom
 * @property {string} nom
 * @property {string} phone
 * @property {number | null} region_id
 * @property {string | null} code_beneficiaire
 * @property {boolean} suivie
 * @property {boolean} grossesse_en_cours
 * @property {number} nb_enfants
 */

/**
 * @typedef {SyncFields & PregnancyFields} Pregnancy
 */
/**
 * @typedef {Object} PregnancyFields
 * @property {Uuid} user_id
 * @property {IsoDate | null} ddr Last period.
 * @property {IsoDate | null} dpa Due date (computed).
 * @property {IsoDate | null} dpa_saisie Due date typed directly.
 * @property {IsoDate | null} terme_confirme_date Ultrasound date…
 * @property {number | null} terme_confirme_jours …and the term, in days, on that date.
 * @property {IsoDate | null} date_accouchement
 * @property {string} mode_allaitement
 * @property {boolean} terminee
 */

/**
 * @typedef {SyncFields & {
 *   grossesse_id: Uuid,
 *   code: string,
 *   periode: 'grossesse' | 'post_partum' | '',
 *   date_signalement: IsoDateTime,
 * }} DangerSign
 */

/**
 * A pregnancy contact attended: type 'cpn' (prenatal) or 'pn' (postnatal).
 * @typedef {SyncFields & {
 *   grossesse_id: Uuid,
 *   type: string,
 *   numero: number,
 *   date_faite: IsoDate,
 * }} CareContact
 */

/**
 * @typedef {SyncFields & {
 *   enfant_id: Uuid,
 *   code: string,
 *   date_faite: IsoDate,
 *   centre: string,
 *   professionnel: string,
 *   confirme_carnet: boolean,
 * }} Vaccination
 */

/** @typedef {'exclusif' | 'mixte' | 'aucun'} Allaitement */

/**
 * The mother's daily food log for a child ("Mon enfant").
 * @typedef {SyncFields & {
 *   enfant_id: Uuid,
 *   date_jour: IsoDate,
 *   type_allaitement: Allaitement,
 *   score_diversite: number,
 *   diversite_minimale_atteinte: boolean,
 *   repas: number,
 *   laits: number,
 *   tetees: number | null,
 * }} FoodLog
 */

/**
 * Her whole file, as /api/beneficiaries/{id}/ and /lookup/ return it.
 * Cycle rows stay empty unless she shares her cycle (option a).
 * @typedef {Object} BeneficiaryDossier
 * @property {{
 *   id: Uuid,
 *   identifiant: string,
 *   prenom: string,
 *   nom: string,
 *   phone: string,
 *   region_id: number | null,
 *   code_beneficiaire: string | null,
 *   partage_cycle: boolean,
 * }} beneficiaire
 * @property {Pregnancy[]} grossesses
 * @property {DangerSign[]} signes_danger
 * @property {CareContact[]} contacts_soin
 * @property {Record<string, unknown>[]} suivis_grossesse
 * @property {Record<string, unknown>[]} mouvements_bebe
 * @property {Record<string, unknown>[]} mouvements_evenements
 * @property {Record<string, unknown>[]} alimentations
 * @property {Record<string, unknown>[]} cycles
 * @property {Record<string, unknown>[]} cycle_jours
 * @property {Child[]} enfants
 * @property {Measurement[]} mesures
 * @property {FoodLog[]} journaux_alimentaires
 * @property {Vaccination[]} vaccins
 * @property {Record<string, unknown>[]} tetees
 * @property {Appointment[]} rendez_vous
 * @property {Referral[]} referencements
 */
