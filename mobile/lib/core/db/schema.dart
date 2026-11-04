/// Local schema, one migration per step. Index i upgrades version i to i + 1.
///
/// Every synced row carries `sync_status` (spec §9):
/// `saved` (Enregistré, grey) → `pending` (À synchroniser, orange)
/// → `synced` (Synchronisé, green) → `conflict` (Conflit, red).
const List<List<String>> migrations = [
  // v1 – foundation
  [
    'CREATE TABLE meta (key TEXT PRIMARY KEY, value TEXT)',
  ],
];

int get schemaVersion => migrations.length;
