import '../../../core/sync/outbox.dart';
import '../../../core/sync/sync_engine.dart';
import '../../../core/sync/sync_tables.dart';
import '../domain/referral_code.dart';

/// Tables the agent mode syncs, parents first: its own screenings and
/// referrals, and the clinical file of the women it follows (D16).
List<TableAdapter> agentAdapters() => [for (final t in SyncTables.agentPull) t.adapter];

/// The server refuses a referral code already used by another phone: draw a
/// new install prefix, give the referral a new code (the old one is kept to
/// be shown), and retry.
ErrorFixer referralCodeFixer(ReferralCodeGenerator codes) => (db, op, errors) async {
  if (op.operation != 'create' || errors is! Map || !errors.containsKey('code_unique')) {
    return false;
  }
  await codes.rotatePrefix();
  final code = await codes.next();
  await db.rawUpdate(
    'UPDATE referencement SET ancien_code = coalesce(ancien_code, code_unique), code_unique = ? WHERE id = ?',
    [code, op.rowId],
  );
  await Outbox.replacePayloadField(db, op.seq, 'code_unique', code);
  return true;
};
