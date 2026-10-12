/// "Rs. 12,500" / "Rs. 12,500.50" (decimals only when needed).
String formatMoney(double value) {
  final neg = value < 0;
  final a = value.abs();
  final fixed = a.toStringAsFixed(a == a.roundToDouble() ? 0 : 2);
  final parts = fixed.split('.');
  final intPart = parts[0].replaceAllMapped(
    RegExp(r'\B(?=(\d{3})+(?!\d))'),
    (_) => ',',
  );
  final frac = parts.length > 1 ? '.${parts[1]}' : '';
  return 'Rs. ${neg ? '-' : ''}$intPart$frac';
}

const _months = [
  'Jan',
  'Feb',
  'Mar',
  'Apr',
  'May',
  'Jun',
  'Jul',
  'Aug',
  'Sep',
  'Oct',
  'Nov',
  'Dec',
];

/// "03 Oct 2026, 7:45 PM"
String formatDateTime(DateTime d) {
  final hour12 = d.hour % 12 == 0 ? 12 : d.hour % 12;
  final minute = d.minute.toString().padLeft(2, '0');
  final ampm = d.hour >= 12 ? 'PM' : 'AM';
  final day = d.day.toString().padLeft(2, '0');
  return '$day ${_months[d.month - 1]} ${d.year}, $hour12:$minute $ampm';
}

/// "03 Oct 2026"
String formatDate(DateTime d) =>
    '${d.day.toString().padLeft(2, '0')} ${_months[d.month - 1]} ${d.year}';
