import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../../cores/l10n/labels.dart';
import '../../cores/providers/language_provider.dart';
import '../../cores/themes/app_colors.dart';

/// Menu 3 : fiches santé.
class CycleAdviceView extends ConsumerWidget {
  const CycleAdviceView({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final language = ref.watch(languageProvider);
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        for (final sheet in _sheets)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: _SheetCard(language: language, sheet: sheet),
          ),
      ],
    );
  }
}

typedef _Text = ({String mg, String fr});

class _Sheet {
  const _Sheet({
    required this.icon,
    required this.title,
    required this.points,
    this.urgent = false,
  });

  final IconData icon;
  final _Text title;
  final List<_Text> points;

  /// Fiche des signes d'alerte : mise en évidence et ouverte d'office.
  final bool urgent;
}

const List<_Sheet> _sheets = [
  _Sheet(
    icon: Symbols.emergency_home,
    urgent: true,
    title: (
      mg: 'Rahoviana no mankany amin’ny CSB?',
      fr: 'Quand consulter au Centre de Santé de Base (CSB) ?',
    ),
    points: [
      (
        mg: 'Rà be loatra: feno ao anatin’ny adiny iray ny serviette, mandritra ny adiny roa mahery.',
        fr: 'Saignements très abondants : une serviette trempée en une heure, pendant plus de deux heures.',
      ),
      (
        mg: 'Fadimbolana maharitra mihoatra ny 7 andro.',
        fr: 'Règles qui durent plus de 7 jours.',
      ),
      (
        mg: 'Fanaintainana mafy tsy mihena na dia misotro fanafody aza, na manakana anao tsy hanao ny asanao.',
        fr: 'Douleurs fortes qui ne passent pas avec un antidouleur ou qui empêchent les activités quotidiennes.',
      ),
      (
        mg: 'Tazo miaraka amin’ny fanaintainan-kibo, na fivoahana ranon-javatra maimbo.',
        fr: 'Fièvre avec douleurs au ventre, ou pertes malodorantes.',
      ),
      (
        mg: 'Fanina, reraka mafy na torana.',
        fr: 'Vertiges, grande fatigue ou évanouissement.',
      ),
      (
        mg: 'Rà mivoaka eo anelanelan’ny fadimbolana roa, na rehefa bevohoka.',
        fr: 'Saignements entre deux règles, ou pendant une grossesse.',
      ),
      (
        mg: 'Tsy tonga 3 volana ny fadimbolana, na mety ho bevohoka ianao.',
        fr: 'Absence de règles pendant 3 mois, ou possibilité de grossesse.',
      ),
    ],
  ),
  _Sheet(
    icon: Symbols.menstrual_health,
    title: (mg: 'Ny fadimbolana', fr: 'Comprendre ses règles'),
    points: [
      (
        mg: 'Zavatra voajanahary sy ara-pahasalamana ny fadimbolana.',
        fr: 'Les règles sont un phénomène naturel et sain.',
      ),
      (
        mg: 'Matetika 21 ka hatramin’ny 35 andro ny tsingerina, ary 2 ka hatramin’ny 7 andro ny fadimbolana.',
        fr: 'Un cycle dure le plus souvent 21 à 35 jours, et les règles 2 à 7 jours.',
      ),
      (
        mg: 'Mety hiovaova ny tsingerina, indrindra amin’ny taona voalohany.',
        fr: 'Le cycle peut varier, surtout durant les premières années.',
      ),
      (
        mg: 'Mitohy ny fianarana sy ny asa mandritra ny fadimbolana; ilaina ny sakafo ampy sy ny rano.',
        fr: 'L’école et les activités peuvent continuer pendant les règles ; bien manger et boire de l’eau aide.',
      ),
    ],
  ),
  _Sheet(
    icon: Symbols.soap,
    title: (mg: 'Fahadiovana', fr: 'Règles d’hygiène'),
    points: [
      (
        mg: 'Sasao amin’ny savony ny tanana alohan’ny sy aorian’ny fanovana serviette.',
        fr: 'Se laver les mains au savon avant et après avoir changé de protection.',
      ),
      (
        mg: 'Ovay isaky ny adiny 4 ka hatramin’ny 6 ny serviette, na matetika kokoa raha be ny rà.',
        fr: 'Changer de serviette toutes les 4 à 6 heures, plus souvent si les règles sont abondantes.',
      ),
      (
        mg: 'Sasao amin’ny rano madio isan’andro ny taovam-pananahana ivelany. Aza sasana ny ao anatiny.',
        fr: 'Laver la zone intime à l’eau propre chaque jour, uniquement à l’extérieur, sans douche interne.',
      ),
      (
        mg: 'Sasao amin’ny savony ny lamba azo ampiasaina indray, ary hahazo amin’ny masoandro.',
        fr: 'Laver les protections réutilisables au savon et les faire sécher au soleil.',
      ),
    ],
  ),
  _Sheet(
    icon: Symbols.healing,
    title: (mg: 'Fanaintainana', fr: 'Gérer les douleurs'),
    points: [
      (
        mg: 'Apetraho eo amin’ny kibo ambany ny tavoahangy misy rano mafana (tsy mandoro).',
        fr: 'Poser une bouillotte ou une bouteille d’eau chaude (non brûlante) sur le bas du ventre.',
      ),
      (
        mg: 'Mandehandeha na manao fanatanjahan-tena malefaka, ary miala sasatra.',
        fr: 'Marcher ou faire des mouvements doux, et se reposer.',
      ),
      (mg: 'Misotroa rano betsaka.', fr: 'Boire suffisamment d’eau.'),
      (
        mg: 'Raha ilaina, anontanio ny mpitsabo momba ny fanafody fanaintainana toy ny paracétamol, ary arahina ny fatra voasoratra.',
        fr: 'Si besoin, demander conseil au personnel de santé pour un antidouleur comme le paracétamol, en respectant la dose indiquée.',
      ),
    ],
  ),
];

class _SheetCard extends StatelessWidget {
  const _SheetCard({required this.language, required this.sheet});

  final AppLanguage language;
  final _Sheet sheet;

  String _text(_Text text) => language.pick(mg: text.mg, fr: text.fr);

  @override
  Widget build(BuildContext context) {
    final accent = sheet.urgent ? AppColors.warning : AppColors.primaryDark;
    return Card(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: sheet.urgent
            ? const BorderSide(color: AppColors.warning, width: 2)
            : BorderSide.none,
      ),
      child: ExpansionTile(
        initiallyExpanded: sheet.urgent,
        minTileHeight: 56,
        iconColor: accent,
        collapsedIconColor: accent,
        shape: const Border(),
        collapsedShape: const Border(),
        leading: Icon(sheet.icon, color: accent, size: 30),
        title: Text(
          _text(sheet.title),
          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
        ),
        childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        expandedCrossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final point in sheet.points)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  ExcludeSemantics(
                    child: Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: Icon(
                        sheet.urgent ? Symbols.warning : Symbols.check_circle,
                        size: 18,
                        color: accent,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(child: Text(_text(point))),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
