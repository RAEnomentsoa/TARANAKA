/// Local schema, one migration per step. Index i upgrades version i to i + 1.
///
/// Every synced row carries `sync_status` (spec §9):
/// `saved` (Enregistré, grey) → `pending` (À synchroniser, orange)
/// → `synced` (Synchronisé, green) → `conflict` (Conflit, red).
const List<List<String>> migrations = [
  // v1 – foundation
  ['CREATE TABLE meta (key TEXT PRIMARY KEY, value TEXT)'],
  // v2 – agent mode: children, measurements, referrals, centres, outbox
  [
    '''CREATE TABLE enfant (
      id TEXT PRIMARY KEY,
      nom TEXT NOT NULL,
      sexe TEXT NOT NULL,
      date_naissance TEXT NOT NULL,
      region_id INTEGER,
      asc_id TEXT,
      mere_id TEXT,
      grossesse_id TEXT,
      statut_prise_en_charge TEXT NOT NULL DEFAULT 'aucun',
      version INTEGER NOT NULL DEFAULT 1,
      sync_status TEXT NOT NULL DEFAULT 'saved',
      created_at TEXT NOT NULL,
      updated_at TEXT NOT NULL
    )''',
    '''CREATE TABLE mesure (
      id TEXT PRIMARY KEY,
      enfant_id TEXT NOT NULL REFERENCES enfant(id) ON DELETE CASCADE,
      date_mesure TEXT NOT NULL,
      poids_kg REAL NOT NULL,
      taille_cm REAL NOT NULL,
      position TEXT NOT NULL,
      pb_mm INTEGER,
      oedemes_bilateraux TEXT NOT NULL DEFAULT 'aucun',
      signes_danger TEXT NOT NULL DEFAULT '[]',
      complications_medicales INTEGER NOT NULL DEFAULT 0,
      appetit TEXT NOT NULL DEFAULT 'non_teste',
      difficultes_allaitement INTEGER NOT NULL DEFAULT 0,
      age_jour INTEGER,
      age_mois INTEGER,
      taille_corrigee_cm REAL,
      waz REAL, haz REAL, whz REAL,
      flag_aberrant INTEGER NOT NULL DEFAULT 0,
      classification TEXT,
      orientation_centre TEXT,
      urgence TEXT,
      date_prochain_controle TEXT,
      config_version INTEGER,
      alerte TEXT NOT NULL DEFAULT 'vert',
      motif_alerte TEXT NOT NULL DEFAULT '',
      version INTEGER NOT NULL DEFAULT 1,
      sync_status TEXT NOT NULL DEFAULT 'saved',
      created_at TEXT NOT NULL,
      updated_at TEXT NOT NULL
    )''',
    'CREATE INDEX mesure_enfant ON mesure(enfant_id, date_mesure)',
    '''CREATE TABLE referencement (
      id TEXT PRIMARY KEY,
      code_unique TEXT NOT NULL,
      origine TEXT NOT NULL,
      enfant_id TEXT,
      grossesse_id TEXT,
      mesure_id TEXT,
      csb_id INTEGER,
      priorite TEXT NOT NULL,
      urgence TEXT,
      motif TEXT NOT NULL,
      date_referencement TEXT NOT NULL,
      status TEXT NOT NULL DEFAULT 'envoye',
      date_reception TEXT,
      date_prise_en_charge TEXT,
      date_suivi TEXT,
      date_sortie TEXT,
      issue_sortie TEXT,
      transmis INTEGER NOT NULL DEFAULT 0,
      ancien_code TEXT,
      version INTEGER NOT NULL DEFAULT 1,
      sync_status TEXT NOT NULL DEFAULT 'saved',
      created_at TEXT NOT NULL,
      updated_at TEXT NOT NULL
    )''',
    'CREATE INDEX referencement_enfant ON referencement(enfant_id)',
    '''CREATE TABLE rendez_vous (
      id TEXT PRIMARY KEY,
      enfant_id TEXT,
      referencement_id TEXT,
      csb_id INTEGER,
      date_prevue TEXT NOT NULL,
      type_rendez_vous TEXT,
      statut TEXT,
      motif TEXT,
      version INTEGER NOT NULL DEFAULT 1,
      sync_status TEXT NOT NULL DEFAULT 'synced',
      created_at TEXT,
      updated_at TEXT
    )''',
    '''CREATE TABLE centre (
      id INTEGER PRIMARY KEY,
      name TEXT NOT NULL,
      type_centre TEXT NOT NULL,
      region_id INTEGER,
      tel TEXT
    )''',
    '''CREATE TABLE outbox (
      seq INTEGER PRIMARY KEY AUTOINCREMENT,
      cle_idempotence TEXT NOT NULL UNIQUE,
      table_name TEXT NOT NULL,
      operation TEXT NOT NULL,
      row_id TEXT NOT NULL,
      version INTEGER,
      payload TEXT NOT NULL,
      created_at TEXT NOT NULL,
      attempts INTEGER NOT NULL DEFAULT 0,
      last_status TEXT,
      last_error TEXT
    )''',
    'CREATE INDEX outbox_row ON outbox(table_name, row_id)',
    '''CREATE TABLE conflit (
      id TEXT PRIMARY KEY,
      table_name TEXT NOT NULL,
      ligne_id TEXT NOT NULL,
      statut TEXT NOT NULL,
      resolution TEXT,
      updated_at TEXT
    )''',
  ],
  // v3 – "Mon enfant" (personal mode): birth weight, feeding log, vaccines
  [
    'ALTER TABLE enfant ADD COLUMN poids_naissance_kg REAL',
    '''CREATE TABLE journal_alimentaire (
      id TEXT PRIMARY KEY,
      enfant_id TEXT NOT NULL REFERENCES enfant(id) ON DELETE CASCADE,
      date_jour TEXT NOT NULL,
      type_allaitement TEXT NOT NULL DEFAULT 'aucun',
      aliments TEXT NOT NULL DEFAULT '[]',
      repas INTEGER NOT NULL DEFAULT 0,
      laits INTEGER NOT NULL DEFAULT 0,
      tetees INTEGER,
      version INTEGER NOT NULL DEFAULT 1,
      sync_status TEXT NOT NULL DEFAULT 'saved',
      created_at TEXT NOT NULL,
      updated_at TEXT NOT NULL,
      UNIQUE (enfant_id, date_jour)
    )''',
    '''CREATE TABLE vaccin_fait (
      enfant_id TEXT NOT NULL REFERENCES enfant(id) ON DELETE CASCADE,
      code TEXT NOT NULL,
      date_faite TEXT NOT NULL,
      created_at TEXT NOT NULL,
      PRIMARY KEY (enfant_id, code)
    )''',
  ],
  // v4 – "Ma grossesse": pregnancy, contacts attended, follow-up, movements,
  // danger signals, women's dietary diversity
  [
    '''CREATE TABLE grossesse (
      id TEXT PRIMARY KEY,
      ddr TEXT,
      terme_confirme_date TEXT,
      terme_confirme_jours INTEGER,
      dpa TEXT,
      date_accouchement TEXT,
      mode_allaitement TEXT,
      terminee INTEGER NOT NULL DEFAULT 0,
      version INTEGER NOT NULL DEFAULT 1,
      sync_status TEXT NOT NULL DEFAULT 'saved',
      created_at TEXT NOT NULL,
      updated_at TEXT NOT NULL
    )''',
    '''CREATE TABLE contact_soin (
      grossesse_id TEXT NOT NULL REFERENCES grossesse(id) ON DELETE CASCADE,
      type TEXT NOT NULL,
      numero INTEGER NOT NULL,
      date_faite TEXT NOT NULL,
      PRIMARY KEY (grossesse_id, type, numero)
    )''',
    '''CREATE TABLE suivi_grossesse (
      id TEXT PRIMARY KEY,
      grossesse_id TEXT NOT NULL REFERENCES grossesse(id) ON DELETE CASCADE,
      date_jour TEXT NOT NULL,
      poids_kg REAL,
      notes TEXT NOT NULL DEFAULT '',
      created_at TEXT NOT NULL
    )''',
    '''CREATE TABLE mouvement_bebe (
      grossesse_id TEXT NOT NULL REFERENCES grossesse(id) ON DELETE CASCADE,
      date_jour TEXT NOT NULL,
      mouvements INTEGER NOT NULL,
      PRIMARY KEY (grossesse_id, date_jour)
    )''',
    '''CREATE TABLE danger_grossesse (
      id TEXT PRIMARY KEY,
      grossesse_id TEXT NOT NULL REFERENCES grossesse(id) ON DELETE CASCADE,
      code TEXT NOT NULL,
      periode TEXT NOT NULL,
      date_signalement TEXT NOT NULL,
      version INTEGER NOT NULL DEFAULT 1,
      sync_status TEXT NOT NULL DEFAULT 'saved',
      created_at TEXT NOT NULL,
      updated_at TEXT NOT NULL
    )''',
    '''CREATE TABLE alimentation_femme (
      date_jour TEXT PRIMARY KEY,
      groupes TEXT NOT NULL
    )''',
  ],
  // v5 – "Mon cycle": never synced unless the user explicitly enables it.
  [
    '''CREATE TABLE cycle (
      id TEXT PRIMARY KEY,
      date_debut TEXT NOT NULL,
      date_fin TEXT,
      intensite TEXT NOT NULL DEFAULT 'moyenne',
      douleur INTEGER NOT NULL DEFAULT 0,
      humeur INTEGER,
      notes TEXT NOT NULL DEFAULT '',
      version INTEGER NOT NULL DEFAULT 1,
      sync_status TEXT NOT NULL DEFAULT 'saved',
      created_at TEXT NOT NULL,
      updated_at TEXT NOT NULL
    )''',
    'CREATE INDEX cycle_debut ON cycle(date_debut)',
  ],
  // v6 – due date entered directly (past or future), dated health
  // parameters of the pregnancy follow-up, baby movements by type and time.
  [
    'ALTER TABLE grossesse ADD COLUMN dpa_saisie TEXT',
    'ALTER TABLE suivi_grossesse ADD COLUMN tension_sys INTEGER',
    'ALTER TABLE suivi_grossesse ADD COLUMN tension_dia INTEGER',
    'ALTER TABLE suivi_grossesse ADD COLUMN hauteur_uterine_cm REAL',
    'ALTER TABLE suivi_grossesse ADD COLUMN hemoglobine_g_dl REAL',
    'ALTER TABLE suivi_grossesse ADD COLUMN glycemie_g_l REAL',
    'ALTER TABLE suivi_grossesse ADD COLUMN temperature_c REAL',
    '''CREATE TABLE mouvement_evenement (
      id TEXT PRIMARY KEY,
      grossesse_id TEXT NOT NULL REFERENCES grossesse(id) ON DELETE CASCADE,
      horodatage TEXT NOT NULL,
      type TEXT NOT NULL,
      created_at TEXT NOT NULL
    )''',
    'CREATE INDEX mouvement_evenement_g ON mouvement_evenement(grossesse_id, horodatage)',
  ],
  // v7 – "Mon cycle": symptoms (JSON list of codes) and periods marked
  // irregular by the user.
  [
    "ALTER TABLE cycle ADD COLUMN symptomes TEXT NOT NULL DEFAULT '[]'",
    'ALTER TABLE cycle ADD COLUMN irreguliere INTEGER NOT NULL DEFAULT 0',
  ],
  // v8 – "Allaitement": what else the baby received (water, infant formula,
  // food, other), and each feed with its time, duration or quantity of
  // expressed breast milk. Kept on the phone only.
  [
    "ALTER TABLE journal_alimentaire ADD COLUMN autres_recus TEXT NOT NULL DEFAULT '[]'",
    '''CREATE TABLE tetee (
      id TEXT PRIMARY KEY,
      enfant_id TEXT NOT NULL REFERENCES enfant(id) ON DELETE CASCADE,
      horodatage TEXT NOT NULL,
      type TEXT NOT NULL,
      duree_min INTEGER,
      quantite_ml INTEGER,
      created_at TEXT NOT NULL
    )''',
    'CREATE INDEX tetee_enfant ON tetee(enfant_id, horodatage)',
  ],
  // v9 – "Mon suivi de grossesse": where the measurement was taken (at home
  // or by a health professional), whether the blood sugar was taken fasting,
  // and when an entry was corrected.
  [
    "ALTER TABLE suivi_grossesse ADD COLUMN source TEXT NOT NULL DEFAULT 'domicile'",
    'ALTER TABLE suivi_grossesse ADD COLUMN glycemie_a_jeun INTEGER',
    'ALTER TABLE suivi_grossesse ADD COLUMN updated_at TEXT',
  ],
  // v10 – "Vaccins" (PEV Madagascar): where and by whom each dose was given,
  // whether it was checked on the vaccination card, when it was corrected;
  // codes of the former schedule renamed (VPI → VPI 1, RR → VAR).
  [
    'ALTER TABLE vaccin_fait ADD COLUMN centre TEXT',
    'ALTER TABLE vaccin_fait ADD COLUMN professionnel TEXT',
    'ALTER TABLE vaccin_fait ADD COLUMN confirme_carnet INTEGER',
    'ALTER TABLE vaccin_fait ADD COLUMN updated_at TEXT',
    "UPDATE OR IGNORE vaccin_fait SET code = 'vpi1' WHERE code = 'vpi'",
    "UPDATE OR IGNORE vaccin_fait SET code = 'var1' WHERE code = 'rr1'",
    "UPDATE OR IGNORE vaccin_fait SET code = 'var2' WHERE code = 'rr2'",
  ],
];
