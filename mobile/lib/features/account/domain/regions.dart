/// The regions of Madagascar, so a profile created offline can choose hers
/// at once. The server id is found by name at the first connection
/// (`/api/auth/access-request/options/`), see [matchRegion].
const List<String> madagascarRegions = [
  'Alaotra-Mangoro',
  "Amoron'i Mania",
  'Analamanga',
  'Analanjirofo',
  'Androy',
  'Anosy',
  'Atsimo-Andrefana',
  'Atsimo-Atsinanana',
  'Atsinanana',
  'Betsiboka',
  'Boeny',
  'Bongolava',
  'Diana',
  'Fitovinany',
  'Haute Matsiatra',
  'Ihorombe',
  'Itasy',
  'Melaky',
  'Menabe',
  'Sava',
  'Sofia',
  'Vakinankaratra',
  'Vatovavy',
];

/// A name compared without case, accents, apostrophes nor separators.
String regionKey(String name) {
  const from = 'àâäáãèéêëìíîïòóôöõùúûüç';
  const to = 'aaaaaeeeeiiiiooooouuuuc';
  final b = StringBuffer();
  for (final c in name.trim().toLowerCase().split('')) {
    final i = from.indexOf(c);
    final ch = i < 0 ? c : to[i];
    if (RegExp('[a-z0-9]').hasMatch(ch)) b.write(ch);
  }
  return b.toString();
}

/// The server id of [name] among [server] (id, name), or null.
int? matchRegion(String name, Iterable<(int, String)> server) {
  final key = regionKey(name);
  for (final (id, n) in server) {
    if (regionKey(n) == key) return id;
  }
  return null;
}
