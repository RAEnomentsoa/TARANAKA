/// "Semaine par semaine": how the baby grows and how the body changes, by
/// stage of the pregnancy (SA). General landmarks in short sentences, stored
/// in the app so they work offline; every pregnancy is different.
///
/// Content to validate by the health team, like the configuration.
class PregnancyWeekInfo {
  const PregnancyWeekInfo({
    required this.fromWeek,
    required this.baby,
    required this.body,
    required this.tip,
  });

  /// First SA of the stage (the stage lasts until the next one).
  final int fromWeek;

  /// `{fr, en, mg}` texts.
  final Map<String, String> baby;
  final Map<String, String> body;
  final Map<String, String> tip;

  String babyIn(String lang) => baby[lang] ?? baby['fr']!;
  String bodyIn(String lang) => body[lang] ?? body['fr']!;
  String tipIn(String lang) => tip[lang] ?? tip['fr']!;
}

/// First and last SA that the weekly follow-up shows.
const int pregnancyWeekMin = 4;
const int pregnancyWeekMax = 42;

/// The stage of [weeks] SA (before 4 SA: the first stage, after 42: the last).
PregnancyWeekInfo pregnancyWeekInfo(int weeks) {
  var info = pregnancyWeeks.first;
  for (final w in pregnancyWeeks) {
    if (weeks >= w.fromWeek) info = w;
  }
  return info;
}

const List<PregnancyWeekInfo> pregnancyWeeks = [
  PregnancyWeekInfo(
    fromWeek: 4,
    baby: {
      'fr': "L'embryon s'installe dans l'utérus. Son cœur commence à battre.",
      'en': 'The embryo settles in the womb. Its heart starts to beat.',
      'mg': "Miorina ao an-kibo ilay zaza vao miforona. Manomboka mitempo ny fony.",
    },
    body: {
      'fr': 'Les règles s\'arrêtent. Nausées, fatigue et seins sensibles sont fréquents.',
      'en': 'Periods stop. Nausea, tiredness and tender breasts are common.',
      'mg': "Mijanona ny fadim-bolana. Matetika ny maloiloy, ny havizanana ary ny nono marary.",
    },
    tip: {
      'fr': 'Prenez le fer et l\'acide folique, et prévoyez votre première consultation prénatale.',
      'en': 'Take iron and folic acid, and plan your first antenatal visit.',
      'mg': "Mihinàna ny fer sy ny asidra folika, ary kasao ny fizahana voalohany.",
    },
  ),
  PregnancyWeekInfo(
    fromWeek: 8,
    baby: {
      'fr': 'Tous ses organes se forment. Il ne mesure encore que quelques centimètres.',
      'en': 'All the organs are forming. The baby is only a few centimetres long.',
      'mg': "Miforona avokoa ny taova rehetra. Santimetatra vitsivitsy monja ny halavany.",
    },
    body: {
      'fr': 'Les nausées peuvent être fortes. Le ventre ne se voit pas encore.',
      'en': 'Nausea can be strong. The bump does not show yet.',
      'mg': "Mety ho mafy ny maloiloy. Mbola tsy hita ny kibo.",
    },
    tip: {
      'fr': 'Mangez de petits repas souvent et buvez de l\'eau propre.',
      'en': 'Eat small meals often and drink clean water.',
      'mg': "Mihinàna kely nefa matetika ary misotroa rano madio.",
    },
  ),
  PregnancyWeekInfo(
    fromWeek: 14,
    baby: {
      'fr': 'Il grandit vite et bouge déjà, mais vous ne le sentez pas encore.',
      'en': 'The baby grows fast and already moves, but you cannot feel it yet.',
      'mg': "Mitombo haingana izy ary efa mihetsika, saingy mbola tsy tsapanao.",
    },
    body: {
      'fr': 'Les nausées diminuent souvent. Le ventre commence à s\'arrondir.',
      'en': 'Nausea often eases. The bump starts to show.',
      'mg': "Matetika mihena ny maloiloy. Manomboka miboiboika ny kibo.",
    },
    tip: {
      'fr': 'Dormez sous une moustiquaire et continuez le fer chaque jour.',
      'en': 'Sleep under a mosquito net and keep taking iron every day.',
      'mg': "Matoria ao anaty lay ary tohizo isan'andro ny fer.",
    },
  ),
  PregnancyWeekInfo(
    fromWeek: 18,
    baby: {
      'fr': 'Il entend les bruits. Vous pouvez sentir ses premiers mouvements.',
      'en': 'The baby can hear sounds. You may feel the first movements.',
      'mg': "Maheno feo izy. Mety ho tsapanao ny fihetsiny voalohany.",
    },
    body: {
      'fr': 'Le ventre grossit. Des douleurs au dos peuvent apparaître.',
      'en': 'The bump grows. Back pain may start.',
      'mg': "Mihalehibe ny kibo. Mety hanomboka marary ny lamosina.",
    },
    tip: {
      'fr': 'Évitez de porter des charges lourdes et reposez-vous dans la journée.',
      'en': 'Avoid carrying heavy loads and rest during the day.',
      'mg': "Aza mitondra entana mavesatra ary miala sasatra antoandro.",
    },
  ),
  PregnancyWeekInfo(
    fromWeek: 23,
    baby: {
      'fr': 'Il prend du poids, réagit à votre voix et a des moments d\'éveil et de sommeil.',
      'en': 'The baby gains weight, reacts to your voice and has times awake and asleep.',
      'mg': "Mitombo lanja izy, mihaino ny feonao, ary manana fotoana mifoha sy matory.",
    },
    body: {
      'fr': 'Jambes lourdes, crampes ou brûlures d\'estomac sont possibles.',
      'en': 'Heavy legs, cramps or heartburn are possible.',
      'mg': "Mety ho mavesatra ny tongotra, misy fikentrona na fahamaizan'ny vavony.",
    },
    tip: {
      'fr': 'Reposez-vous allongée sur le côté gauche et surélevez les jambes.',
      'en': 'Rest lying on your left side and raise your legs.',
      'mg': "Miala sasatra mandry amin'ny ilany havia ary asandrato ny tongotra.",
    },
  ),
  PregnancyWeekInfo(
    fromWeek: 28,
    baby: {
      'fr': 'Il ouvre les yeux, grossit et bouge beaucoup.',
      'en': 'The baby opens the eyes, grows and moves a lot.',
      'mg': "Manokatra ny masony izy, mihalehibe ary mihetsika be.",
    },
    body: {
      'fr': 'Essoufflement et fatigue reviennent souvent.',
      'en': 'Shortness of breath and tiredness often come back.',
      'mg': "Matetika miverina ny sempotra sy ny havizanana.",
    },
    tip: {
      'fr': 'Notez ses mouvements chaque jour dans « Mouvements du bébé ».',
      'en': 'Note the movements every day in "Baby movements".',
      'mg': "Soraty isan'andro ny fihetsiny ao amin'ny « Fihetsiky ny zaza ».",
    },
  ),
  PregnancyWeekInfo(
    fromWeek: 32,
    baby: {
      'fr': 'Ses poumons mûrissent. Il se met souvent la tête en bas.',
      'en': 'The lungs mature. The baby often turns head down.',
      'mg': "Matanjaka ny havokavony. Matetika mitodika ambany ny lohany.",
    },
    body: {
      'fr': 'Le ventre est lourd et l\'envie d\'uriner est fréquente.',
      'en': 'The bump is heavy and you need to pass urine often.',
      'mg': "Mavesatra ny kibo ary matetika te hamany.",
    },
    tip: {
      'fr': 'Préparez l\'accouchement : lieu, transport, argent et accompagnant.',
      'en': 'Plan the birth: place, transport, money and a companion.',
      'mg': "Omano ny fiterahana: toerana, fitaterana, vola ary mpiaraka.",
    },
  ),
  PregnancyWeekInfo(
    fromWeek: 37,
    baby: {
      'fr': 'Il est prêt à naître.',
      'en': 'The baby is ready to be born.',
      'mg': "Vonona ho teraka izy.",
    },
    body: {
      'fr': 'Le ventre se durcit par moments. Des contractions régulières annoncent le travail.',
      'en': 'The bump tightens at times. Regular contractions mean labour is starting.',
      'mg': "Mihamafy indraindray ny kibo. Ny fikentrona miverimberina dia mampahafantatra ny fiterahana.",
    },
    tip: {
      'fr': 'Allez au centre de santé dès des contractions régulières ou la perte des eaux.',
      'en': 'Go to the health centre as soon as contractions are regular or the waters break.',
      'mg': "Mankanesa any amin'ny toeram-pitsaboana raha miverimberina ny fikentrona na mivoaka ny rano.",
    },
  ),
  PregnancyWeekInfo(
    fromWeek: 41,
    baby: {
      'fr': 'Le terme est atteint ou dépassé : le bébé doit être surveillé.',
      'en': 'The due date is reached or passed: the baby needs to be checked.',
      'mg': "Tonga na mihoatra ny fe-potoana: tsy maintsy arahi-maso ny zaza.",
    },
    body: {
      'fr': 'L\'attente peut être fatigante. Continuez à sentir ses mouvements.',
      'en': 'Waiting can be tiring. Keep feeling the movements.',
      'mg': "Mety handreraka ny fiandrasana. Tohizo ny fanaraha-maso ny fihetsiny.",
    },
    tip: {
      'fr': 'Consultez sans attendre pour décider avec le soignant de la suite.',
      'en': 'See a health worker now to decide together what comes next.',
      'mg': "Mankanesa mpitsabo avy hatrany hifampiresaka ny manaraka.",
    },
  ),
];
