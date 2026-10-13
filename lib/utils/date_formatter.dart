String formatOrderDate(String value) {
  final parsed = DateTime.tryParse(value)?.toLocal();
  if (parsed == null) return value.split('T').first;

  const months = [
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
  return '${months[parsed.month - 1]} ${parsed.day}, ${parsed.year}';
}
