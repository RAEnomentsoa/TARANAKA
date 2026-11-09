import '../config/clinical_config.dart';

/// What a danger sign means and what to do, in short sentences, for the
/// compact list of "Ma grossesse". The configuration may give its own
/// `explication` and `action` (plain text or `{fr, mg, en}`): they win over
/// these texts, kept in the app so they work offline.
///
/// Content to validate by the health team, like the configuration.
class DangerSignInfo {
  const DangerSignInfo(this.why, this.todo);

  /// `{fr, en, mg}` texts.
  final Map<String, String> why;
  final Map<String, String> todo;

  static String explanation(Map<String, Object?> sign, String lang) =>
      _text(sign['explication'], lang) ?? _pick(_known[sign['code']]?.why, lang) ?? '';

  static String action(Map<String, Object?> sign, String lang) =>
      _text(sign['action'], lang) ?? _pick(_known[sign['code']]?.todo, lang) ?? _pick(_consult, lang)!;

  /// "Vous avez signalé …": the sentence at the top of the red alert. The
  /// configuration may give its own `signale`; null for an unknown sign (the
  /// alert then uses its label).
  static String? reported(Map<String, Object?> sign, String lang) =>
      _text(sign['signale'], lang) ?? _pick(_reported[sign['code']], lang);

  static const Map<String, Map<String, String>> _reported = {
    'saignement_vaginal': {
      'fr': 'Vous avez signalé un saignement vaginal.',
      'en': 'You reported vaginal bleeding.',
      'mg': 'Nilaza ianao fa mandeha ra amin\'ny fivaviana.',
    },
    'saignement_abondant': {
      'fr': 'Vous avez signalé un saignement abondant.',
      'en': 'You reported heavy bleeding.',
      'mg': 'Nilaza ianao fa mandeha ra be.',
    },
    'convulsions': {
      'fr': 'Vous avez signalé des convulsions.',
      'en': 'You reported fits (convulsions).',
      'mg': 'Nilaza ianao fa misy fihovitrovitra.',
    },
    'maux_de_tete_vision': {
      'fr': 'Vous avez signalé des maux de tête violents ou une vision trouble.',
      'en': 'You reported a severe headache or blurred vision.',
      'mg': 'Nilaza ianao fa marary loha mafy na manjavozavo ny maso.',
    },
    'fievre_elevee': {
      'fr': 'Vous avez signalé une fièvre élevée.',
      'en': 'You reported a high fever.',
      'mg': 'Nilaza ianao fa misy tazo mafy.',
    },
    'fievre': {
      'fr': 'Vous avez signalé de la fièvre.',
      'en': 'You reported a fever.',
      'mg': 'Nilaza ianao fa misy tazo.',
    },
    'difficulte_respirer': {
      'fr': 'Vous avez signalé une difficulté à respirer.',
      'en': 'You reported difficulty breathing.',
      'mg': 'Nilaza ianao fa sarotra ny miaina.',
    },
    'douleur_abdominale': {
      'fr': 'Vous avez signalé une douleur abdominale intense.',
      'en': 'You reported severe belly pain.',
      'mg': 'Nilaza ianao fa marary kibo mafy.',
    },
    'douleur_intense': {
      'fr': 'Vous avez signalé une douleur intense.',
      'en': 'You reported severe pain.',
      'mg': 'Nilaza ianao fa misy fanaintainana mafy.',
    },
    'perte_des_eaux': {
      'fr': 'Vous avez signalé une perte des eaux.',
      'en': 'You reported that your waters broke.',
      'mg': 'Nilaza ianao fa nivoaka ny rano.',
    },
    'bebe_bouge_moins': {
      'fr': 'Vous avez signalé que votre bébé bouge moins ou ne bouge plus.',
      'en': 'You reported that your baby moves less or not at all.',
      'mg': 'Nilaza ianao fa mihetsika kely na tsy mihetsika intsony ny zazanao.',
    },
    'gonflement_visage_mains': {
      'fr': 'Vous avez signalé un gonflement soudain du visage ou des mains.',
      'en': 'You reported sudden swelling of the face or hands.',
      'mg': 'Nilaza ianao fa nivonto tampoka ny tarehy na ny tanana.',
    },
    'pertes_malodorantes': {
      'fr': 'Vous avez signalé des pertes qui sentent mauvais.',
      'en': 'You reported bad-smelling discharge.',
      'mg': 'Nilaza ianao fa misy fivoahana maimbo.',
    },
    'tristesse_profonde': {
      'fr': 'Vous avez signalé une tristesse profonde ou des pensées inquiétantes.',
      'en': 'You reported deep sadness or worrying thoughts.',
      'mg': 'Nilaza ianao fa malahelo mafy na manana eritreritra mampanahy.',
    },
    'ne_peut_pas_boire': {
      'fr': 'Vous avez signalé que l\'enfant ne peut pas boire ou téter.',
      'en': 'You reported that the child cannot drink or breastfeed.',
      'mg': 'Nilaza ianao fa tsy afaka misotro na minono ilay zaza.',
    },
    'vomit_tout': {
      'fr': 'Vous avez signalé que l\'enfant vomit tout.',
      'en': 'You reported that the child vomits everything.',
      'mg': 'Nilaza ianao fa mandoa ny zavatra rehetra ilay zaza.',
    },
    'lethargie': {
      'fr': 'Vous avez signalé que l\'enfant est très endormi ou inconscient.',
      'en': 'You reported that the child is very sleepy or unconscious.',
      'mg': 'Nilaza ianao fa matory be na tsy mahatsiaro tena ilay zaza.',
    },
    'oedemes_deux_pieds': {
      'fr': 'Vous avez signalé un gonflement des deux pieds de l\'enfant.',
      'en': 'You reported swelling of both of the child\'s feet.',
      'mg': 'Nilaza ianao fa mivonto ny tongotr\'ilay zaza roa.',
    },
  };

  static String? _text(Object? v, String lang) {
    final t = v == null ? '' : localizedText(v, lang);
    return t.isEmpty ? null : t;
  }

  static String? _pick(Map<String, String>? m, String lang) => m == null ? null : (m[lang] ?? m['fr']);

  static const _now = {
    'fr': 'Allez immédiatement au centre de santé le plus proche.',
    'en': 'Go to the nearest health centre straight away.',
    'mg': "Mankanesa avy hatrany any amin'ny toeram-pitsaboana akaiky indrindra.",
  };

  static const _today = {
    'fr': 'Consultez un agent ou un centre de santé le jour même.',
    'en': 'See a health worker or a health centre the same day.',
    'mg': "Mankanesa amin'ny mpitsabo na toeram-pitsaboana anio ihany.",
  };

  static const _consult = {
    'fr': 'Consultez rapidement un agent ou un centre de santé.',
    'en': 'See a health worker or a health centre quickly.',
    'mg': "Mankanesa haingana amin'ny mpitsabo na toeram-pitsaboana.",
  };

  static const _convulsions = DangerSignInfo(
    {
      'fr': "Les convulsions peuvent être un signe d'éclampsie, grave pour la mère et le bébé.",
      'en': 'Fits can be a sign of eclampsia, serious for the mother and the baby.',
      'mg': "Mety ho famantarana eklampsia ny fihovitrovitra, loza ho an'ny reny sy ny zaza.",
    },
    {
      'fr': 'Allongez-la sur le côté, ne mettez rien dans sa bouche et emmenez-la immédiatement au centre de santé.',
      'en': 'Lay her on her side, put nothing in her mouth and take her to the health centre straight away.',
      'mg': "Ampandrio amin'ny ilany izy, aza misy apetraka am-bavany, ary ento avy hatrany any amin'ny toeram-pitsaboana.",
    },
  );

  static const _breathing = DangerSignInfo({
    'fr': "Peut venir d'une anémie sévère, d'une infection ou d'un problème du cœur.",
    'en': 'Can come from severe anaemia, an infection or a heart problem.',
    'mg': "Mety avy amin'ny tsy fahampian-dra mafy, aretina na olana amin'ny fo.",
  }, _now);

  static const Map<String, DangerSignInfo> _known = {
    // ---- pregnancy
    'saignement_vaginal': DangerSignInfo(
      {
        'fr': 'Un saignement pendant la grossesse peut venir du placenta ou annoncer une fausse couche.',
        'en': 'Bleeding in pregnancy can come from the placenta or be a sign of miscarriage.',
        'mg': "Mety avy amin'ny tavony na famantarana fahafahan-jaza ny fandehanan-dra mandritra ny fitondrana vohoka.",
      },
      {
        'fr': 'Allongez-vous, ne mettez rien dans le vagin et allez immédiatement au centre de santé.',
        'en': 'Lie down, put nothing in the vagina and go to the health centre straight away.',
        'mg': "Mandria, aza misy ampidirina ao amin'ny fivaviana, ary mankanesa avy hatrany any amin'ny toeram-pitsaboana.",
      },
    ),
    'convulsions': _convulsions,
    'maux_de_tete_vision': DangerSignInfo(
      {
        'fr': 'Peut être un signe de tension trop élevée (pré-éclampsie).',
        'en': 'Can be a sign of high blood pressure (pre-eclampsia).',
        'mg': "Mety ho famantarana tosi-dra ambony loatra (pre-eklampsia).",
      },
      {
        'fr': 'Allez au centre de santé le jour même pour faire mesurer votre tension.',
        'en': 'Go to the health centre the same day to have your blood pressure checked.',
        'mg': "Mankanesa any amin'ny toeram-pitsaboana anio ihany handrefesana ny tosidranao.",
      },
    ),
    'fievre_elevee': DangerSignInfo(
      {
        'fr': "Peut signaler une infection (paludisme, infection urinaire…) dangereuse pour le bébé.",
        'en': 'Can be a sign of an infection (malaria, urine infection…) dangerous for the baby.',
        'mg': "Mety ho famantarana aretina (tazomoka, aretin'ny lalan-drano…) mampidi-doza ny zaza.",
      },
      {
        'fr': 'Buvez de l\'eau et consultez le jour même. Ne prenez pas de médicament sans avis.',
        'en': 'Drink water and see a health worker the same day. Take no medicine without advice.',
        'mg': "Misotroa rano ary mankanesa amin'ny mpitsabo anio ihany. Aza mihinana fanafody tsy misy torohevitra.",
      },
    ),
    'difficulte_respirer': _breathing,
    'douleur_abdominale': DangerSignInfo({
      'fr': 'Une douleur forte et continue peut venir du placenta ou d\'un accouchement trop tôt.',
      'en': 'Strong, lasting pain can come from the placenta or a birth starting too early.',
      'mg': "Ny fanaintainana mafy sy maharitra dia mety avy amin'ny tavony na fiterahana aloha loatra.",
    }, _now),
    'perte_des_eaux': DangerSignInfo(
      {
        'fr': 'Un liquide clair qui coule du vagin : la poche des eaux peut être rompue, avec un risque d\'infection.',
        'en': 'Clear fluid from the vagina: the waters may have broken, with a risk of infection.',
        'mg': "Rano madio mivoaka avy amin'ny fivaviana: mety ho vaky ny fonon-drano, ka mety hisy aretina.",
      },
      {
        'fr': 'Mettez une protection propre et allez au centre de santé sans attendre.',
        'en': 'Use a clean pad and go to the health centre without waiting.',
        'mg': "Mampiasà lamba madio ary mankanesa any amin'ny toeram-pitsaboana tsy miandry.",
      },
    ),
    'bebe_bouge_moins': DangerSignInfo(
      {
        'fr': 'Moins de mouvements peut signaler que le bébé souffre.',
        'en': 'Fewer movements can mean the baby is in distress.',
        'mg': "Ny fihenan'ny fihetsiny dia mety ho famantarana fa sahirana ny zaza.",
      },
      {
        'fr': 'Allongez-vous sur le côté gauche et sentez ses mouvements. S\'il bouge peu ou pas, allez immédiatement au centre de santé.',
        'en': 'Lie on your left side and feel the movements. If the baby moves little or not at all, go to the health centre straight away.',
        'mg': "Mandria amin'ny ilany havia ary tsapao ny fihetsiny. Raha kely na tsy mihetsika izy, mankanesa avy hatrany any amin'ny toeram-pitsaboana.",
      },
    ),
    'gonflement_visage_mains': DangerSignInfo(
      {
        'fr': 'Un gonflement soudain peut être un signe de pré-éclampsie.',
        'en': 'Sudden swelling can be a sign of pre-eclampsia.',
        'mg': "Ny fivontosana tampoka dia mety ho famantarana pre-eklampsia.",
      },
      {
        'fr': 'Allez au centre de santé le jour même pour faire mesurer votre tension.',
        'en': 'Go to the health centre the same day to have your blood pressure checked.',
        'mg': "Mankanesa any amin'ny toeram-pitsaboana anio ihany handrefesana ny tosidranao.",
      },
    ),
    // ---- after the delivery
    'saignement_abondant': DangerSignInfo({
      'fr': "Saigner beaucoup après l'accouchement (une serviette trempée en moins d'une heure) est une urgence.",
      'en': 'Heavy bleeding after the birth (a pad soaked in less than an hour) is an emergency.',
      'mg': "Maika ny fandehanan-dra be aorian'ny fiterahana (lamba lena tanteraka latsaky ny adiny iray).",
    }, _now),
    'fievre': DangerSignInfo({
      'fr': "Peut signaler une infection de l'utérus, d'une plaie ou des seins.",
      'en': 'Can be a sign of an infection of the womb, a wound or the breasts.',
      'mg': "Mety ho famantarana aretina ao amin'ny tranon-jaza, ratra na nono.",
    }, _today),
    'douleur_intense': DangerSignInfo({
      'fr': 'Une forte douleur au ventre, au périnée ou au mollet peut signaler une infection ou un caillot.',
      'en': 'Strong pain in the belly, the perineum or the calf can be a sign of infection or a clot.',
      'mg': "Ny fanaintainana mafy amin'ny kibo, ny perine na ny kitrokely dia mety ho aretina na rà mivongana.",
    }, _today),
    'pertes_malodorantes': DangerSignInfo({
      'fr': "Des pertes qui sentent mauvais peuvent signaler une infection de l'utérus.",
      'en': 'Bad-smelling discharge can be a sign of an infection of the womb.',
      'mg': "Ny fivoahana maimbo dia mety ho famantarana aretina ao amin'ny tranon-jaza.",
    }, _today),
    'tristesse_profonde': DangerSignInfo(
      {
        'fr': "Une tristesse qui dure ou des pensées de se faire du mal peuvent être une dépression après l'accouchement. Ce n'est pas votre faute, et cela se soigne.",
        'en': 'Lasting sadness or thoughts of self-harm can be depression after the birth. It is not your fault, and it can be treated.',
        'mg': "Ny alahelo maharitra na ny eritreritra hanimba tena dia mety ho fahaketrahana aorian'ny fiterahana. Tsy hadisoanao izany, ary azo tsaboina.",
      },
      {
        'fr': "Parlez-en aujourd'hui à un proche et à un agent de santé. Si vous pensez à vous faire du mal, demandez de l'aide tout de suite.",
        'en': 'Talk to someone close and to a health worker today. If you think of harming yourself, ask for help right away.',
        'mg': "Resaho anio amin'ny havana sy mpitsabo izany. Raha mieritreritra hanimba tena ianao, mangataha fanampiana avy hatrany.",
      },
    ),
  };
}
