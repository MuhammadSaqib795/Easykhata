import 'dart:convert';

import 'package:crypto/crypto.dart';

String fingerprintLocalTables(Map<String, List<Map<String, Object?>>> tables) {
  final canonicalTables = tables.keys.toList()..sort();
  final snapshot = [
    for (final table in canonicalTables)
      {
        'table': table,
        'rows': [
          for (final row in tables[table]!)
            Map.fromEntries(
              row.entries.toList()..sort((a, b) => a.key.compareTo(b.key)),
            ),
        ],
      },
  ];
  return sha256.convert(utf8.encode(jsonEncode(snapshot))).toString();
}
