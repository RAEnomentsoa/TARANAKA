/// Instructions de création du schéma, dans l'ordre des dépendances.
///
/// `PRAGMA foreign_keys` n'est volontairement pas ici : il est sans effet dans
/// une transaction, or `onCreate` en est une. Voir [DatabaseHelper].
const List<String> createTableStatements = [
  '''
  CREATE TABLE IF NOT EXISTS Province (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    nom TEXT NOT NULL
  )
  ''',
  '''
  CREATE TABLE IF NOT EXISTS profile (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    type TEXT NOT NULL,
    consentement INTEGER
  )
  ''',
  '''
  CREATE TABLE IF NOT EXISTS Region (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    nom TEXT NOT NULL,
    id_province INTEGER,
    FOREIGN KEY (id_province) REFERENCES Province(id) ON DELETE SET NULL
  )
  ''',
  '''
  CREATE TABLE IF NOT EXISTS CSB (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    name TEXT NOT NULL,
    id_region INTEGER,
    FOREIGN KEY (id_region) REFERENCES Region(id) ON DELETE SET NULL
  )
  ''',
  '''
  CREATE TABLE IF NOT EXISTS User (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    nom TEXT,
    prenom TEXT,
    email TEXT,
    phone TEXT,
    role TEXT,
    pin_hash TEXT,
    dateCreation TEXT,
    id_profile INTEGER,
    id_region INTEGER,
    version INTEGER DEFAULT 1,
    updated_at TEXT,
    device_id TEXT,
    deleted_at TEXT,
    sync_status TEXT DEFAULT 'pending',
    FOREIGN KEY (id_profile) REFERENCES profile(id) ON DELETE SET NULL,
    FOREIGN KEY (id_region) REFERENCES Region(id) ON DELETE SET NULL
  )
  ''',
  '''
  CREATE TABLE IF NOT EXISTS Grossesse (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    DDR TEXT,
    DpA TEXT,
    User_id INTEGER,
    version INTEGER DEFAULT 1,
    updated_at TEXT,
    device_id TEXT,
    deleted_at TEXT,
    sync_status TEXT DEFAULT 'pending',
    FOREIGN KEY (User_id) REFERENCES User(id) ON DELETE CASCADE
  )
  ''',
  '''
  CREATE TABLE IF NOT EXISTS Type_Danger_Grossesse (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    Desc TEXT
  )
  ''',
  '''
  CREATE TABLE IF NOT EXISTS Danger_Grossesse (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    id_grossesse INTEGER,
    Type_danger_Grossesse_id INTEGER,
    version INTEGER DEFAULT 1,
    updated_at TEXT,
    device_id TEXT,
    deleted_at TEXT,
    sync_status TEXT DEFAULT 'pending',
    FOREIGN KEY (id_grossesse) REFERENCES Grossesse(id) ON DELETE CASCADE,
    FOREIGN KEY (Type_danger_Grossesse_id) REFERENCES Type_Danger_Grossesse(id) ON DELETE CASCADE
  )
  ''',
  '''
  CREATE TABLE IF NOT EXISTS Cycle (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    date_debut TEXT,
    date_fin TEXT,
    intensite TEXT,
    dure_cycle INTEGER,
    dure_regle INTEGER,
    symptome TEXT,
    estimationProchain TEXT,
    User_id INTEGER,
    version INTEGER DEFAULT 1,
    updated_at TEXT,
    device_id TEXT,
    deleted_at TEXT,
    sync_status TEXT DEFAULT 'pending',
    FOREIGN KEY (User_id) REFERENCES User(id) ON DELETE CASCADE
  )
  ''',
  '''
  CREATE TABLE IF NOT EXISTS Enfant (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    id_User INTEGER,
    id_Grossesse INTEGER,
    date_de_naissance TEXT,
    sexe TEXT,
    statut_prise_en_charge TEXT,
    nom TEXT,
    version INTEGER DEFAULT 1,
    updated_at TEXT,
    device_id TEXT,
    deleted_at TEXT,
    sync_status TEXT DEFAULT 'pending',
    FOREIGN KEY (id_User) REFERENCES User(id) ON DELETE SET NULL,
    FOREIGN KEY (id_Grossesse) REFERENCES Grossesse(id) ON DELETE SET NULL
  )
  ''',
  '''
  CREATE TABLE IF NOT EXISTS reference_oms (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    Indicateur TEXT,
    sexe TEXT,
    cLe TEXT,
    M REAL,
    L REAL,
    S REAL,
    Measure_Type TEXT
  )
  ''',
  '''
  CREATE TABLE IF NOT EXISTS Mesure (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    enfant_id INTEGER,
    date_mesure TEXT,
    poids_kg REAL,
    taille_cm REAL,
    position TEXT,
    pb_mm REAL,
    oedemes_bilateraux TEXT,
    whz REAL,
    alerte TEXT,
    age_jour INTEGER,
    age_mois INTEGER,
    taille_corrigee_en_cm REAL,
    waz REAL,
    haz REAL,
    flag_aberrant TEXT,
    motif_alerte TEXT,
    ref_oms TEXT,
    aisc_id TEXT,
    version INTEGER DEFAULT 1,
    updated_at TEXT,
    device_id TEXT,
    deleted_at TEXT,
    sync_status TEXT DEFAULT 'pending',
    FOREIGN KEY (enfant_id) REFERENCES Enfant(id) ON DELETE CASCADE
  )
  ''',
  '''
  CREATE TABLE IF NOT EXISTS journal_alimentaire (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    enfant_id INTEGER,
    date_jour TEXT,
    type_allaitement TEXT,
    g1_to_g8 TEXT,
    score_diversite INTEGER,
    notes TEXT,
    version INTEGER DEFAULT 1,
    updated_at TEXT,
    device_id TEXT,
    deleted_at TEXT,
    sync_status TEXT DEFAULT 'pending',
    FOREIGN KEY (enfant_id) REFERENCES Enfant(id) ON DELETE CASCADE
  )
  ''',
  '''
  CREATE TABLE IF NOT EXISTS referencement (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    code_Unique TEXT,
    origine TEXT,
    id_enfant INTEGER,
    id_grossesse INTEGER,
    id_mesure INTEGER,
    asc_id TEXT,
    csb_id INTEGER,
    priorite TEXT,
    motif TEXT,
    status TEXT,
    version INTEGER DEFAULT 1,
    updated_at TEXT,
    device_id TEXT,
    deleted_at TEXT,
    sync_status TEXT DEFAULT 'pending',
    FOREIGN KEY (id_enfant) REFERENCES Enfant(id) ON DELETE CASCADE,
    FOREIGN KEY (id_grossesse) REFERENCES Grossesse(id) ON DELETE SET NULL,
    FOREIGN KEY (id_mesure) REFERENCES Mesure(id) ON DELETE SET NULL,
    FOREIGN KEY (csb_id) REFERENCES CSB(id) ON DELETE SET NULL
  )
  ''',
  '''
  CREATE TABLE IF NOT EXISTS consultation_nutritionnelle (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    id_mesure INTEGER,
    enfant_id INTEGER,
    date TEXT,
    decision TEXT,
    csb_id INTEGER,
    diagnostic TEXT,
    referencement_id INTEGER,
    Agent_medical_id INTEGER,
    observations TEXT,
    version INTEGER DEFAULT 1,
    updated_at TEXT,
    device_id TEXT,
    deleted_at TEXT,
    sync_status TEXT DEFAULT 'pending',
    FOREIGN KEY (id_mesure) REFERENCES Mesure(id) ON DELETE SET NULL,
    FOREIGN KEY (enfant_id) REFERENCES Enfant(id) ON DELETE CASCADE,
    FOREIGN KEY (csb_id) REFERENCES CSB(id) ON DELETE SET NULL,
    FOREIGN KEY (referencement_id) REFERENCES referencement(id) ON DELETE SET NULL,
    FOREIGN KEY (Agent_medical_id) REFERENCES User(id) ON DELETE SET NULL
  )
  ''',
];
