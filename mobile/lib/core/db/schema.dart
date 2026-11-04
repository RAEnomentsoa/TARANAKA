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
];

int get schemaVersion => migrations.length;
