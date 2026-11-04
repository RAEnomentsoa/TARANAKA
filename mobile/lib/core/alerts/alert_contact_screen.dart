import 'package:flutter/material.dart';

import '../../app/app_scope.dart';
import '../i18n/l10n.dart';
import '../theme/tokens.dart';
import '../widgets/screen.dart';
import '../widgets/status_pill.dart';
import 'alert_contact.dart';

class AlertContactScreen extends StatefulWidget {
  const AlertContactScreen({super.key});

  @override
  State<AlertContactScreen> createState() => _AlertContactScreenState();
}

class _AlertContactScreenState extends State<AlertContactScreen> {
  final _name = TextEditingController();
  final _phone = TextEditingController();
  final _agent = TextEditingController();

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    AlertContact.load(AppScope.read(context).session.active!.db).then((c) {
      if (!mounted) return;
      _name.text = c.centreName;
      _phone.text = c.centrePhone;
      _agent.text = c.agentPhone;
    });
  }

  @override
  void dispose() {
    _name.dispose();
    _phone.dispose();
    _agent.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return AppScreen(
      title: l10n.contactTitle,
      bottomAction: FilledButton(
        key: const ValueKey('contact-save'),
        onPressed: () async {
          final messenger = ScaffoldMessenger.of(context);
          final navigator = Navigator.of(context);
          await AlertContact(
            centreName: _name.text,
            centrePhone: _phone.text,
            agentPhone: _agent.text,
          ).save(AppScope.read(context).session.active!.db);
          messenger.showSnackBar(SnackBar(content: Text(l10n.saved)));
          navigator.pop();
        },
        child: Text(l10n.save),
      ),
      children: [
        NoticeBox(icon: Icons.info_outline, text: l10n.contactHelp),
        const Gap(Space.l),
        TextField(
          key: const ValueKey('contact-name'),
          controller: _name,
          decoration: InputDecoration(
            labelText: l10n.contactCentreName,
            prefixIcon: const Icon(Icons.local_hospital_outlined),
          ),
        ),
        const Gap(Space.m),
        TextField(
          key: const ValueKey('contact-phone'),
          controller: _phone,
          keyboardType: TextInputType.phone,
          decoration: InputDecoration(
            labelText: l10n.contactCentrePhone,
            prefixIcon: const Icon(Icons.call_outlined),
          ),
        ),
        const Gap(Space.m),
        TextField(
          key: const ValueKey('contact-agent'),
          controller: _agent,
          keyboardType: TextInputType.phone,
          decoration: InputDecoration(
            labelText: l10n.contactAgentPhone,
            prefixIcon: const Icon(Icons.support_agent),
          ),
        ),
      ],
    );
  }
}
