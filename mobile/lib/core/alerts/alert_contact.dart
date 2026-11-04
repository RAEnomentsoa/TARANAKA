import '../db/app_database.dart';

/// Who to go to and who to call from a red alert (spec §5): the reference
/// health centre and a phone number (emergency or community agent), entered
/// by the user in the settings. Stored in the encrypted profile.
class AlertContact {
  const AlertContact({this.centreName = '', this.centrePhone = '', this.agentPhone = ''});

  final String centreName;
  final String centrePhone;
  final String agentPhone;

  bool get isEmpty => centreName.isEmpty && centrePhone.isEmpty && agentPhone.isEmpty;

  /// Number for the call button: the centre first, else the agent.
  String? get callNumber =>
      centrePhone.isNotEmpty ? centrePhone : (agentPhone.isNotEmpty ? agentPhone : null);

  static const _key = 'alert_contact';

  static Future<AlertContact> load(AppDatabase db) async {
    final j = await db.getMetaJson(_key);
    if (j == null) return const AlertContact();
    return AlertContact(
      centreName: (j['centre_name'] as String?) ?? '',
      centrePhone: (j['centre_phone'] as String?) ?? '',
      agentPhone: (j['agent_phone'] as String?) ?? '',
    );
  }

  Future<void> save(AppDatabase db) => db.setMetaJson(_key, {
    'centre_name': centreName.trim(),
    'centre_phone': centrePhone.trim(),
    'agent_phone': agentPhone.trim(),
  });
}
