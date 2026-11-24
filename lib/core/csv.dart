// Builds CSV text (opens in Excel / Google Sheets) without a package.
// Every value is put in quotes, and quotes inside a value are doubled,
// so commas or quotes in names never break the columns.
String toCsv(List<String> header, List<List<String>> rows) {
  String cell(String value) => '"${value.replaceAll('"', '""')}"';
  final lines = [
    header.map(cell).join(','),
    for (final row in rows) row.map(cell).join(','),
  ];
  return lines.join('\n');
}
