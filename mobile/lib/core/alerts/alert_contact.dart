import '../db/app_database.dart';

/// Who to go to and who to call from a red alert (spec §5): the reference
/// health centre and a phone number (emergency or community agent), entered
/// by the user in the settings, with how to get to the centre. Stored in the
/// encrypted profile database on the phone: available offline; the call goes
/// through the phone network.
class AlertContact {
  const AlertContact({
    this.centreName = '',
    this.centrePhone = '',
    this.agentPhone = '',
    this.centreDirections = '',
  });

  final String centreName;
  final String centrePhone;
  final String agentPhone;

  /// How to get there, in the user's words (e.g. "après le marché").
  final String centreDirections;

  bool get isEmpty =>
      centreName.isEmpty && centrePhone.isEmpty && agentPhone.isEmpty && centreDirections.isEmpty;

  bool get hasCentre => centreName.isNotEmpty || centrePhone.isNotEmpty || centreDirections.isNotEmpty;

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
      centreDirections: (j['centre_directions'] as String?) ?? '',
    );
  }

  Future<void> save(AppDatabase db) => db.setMetaJson(_key, {
    'centre_name': centreName.trim(),
    'centre_phone': centrePhone.trim(),
    'agent_phone': agentPhone.trim(),
    'centre_directions': centreDirections.trim(),
  });
}
