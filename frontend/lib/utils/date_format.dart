const monthNames = [
  'January', 'February', 'March', 'April', 'May', 'June', //
  'July', 'August', 'September', 'October', 'November', 'December',
];
const weekdayNames = [
  'Monday',
  'Tuesday',
  'Wednesday',
  'Thursday',
  'Friday',
  'Saturday',
  'Sunday',
];

String shortMonth(DateTime date) => monthNames[date.month - 1].substring(0, 3);

String shortWeekday(DateTime date) =>
    weekdayNames[date.weekday - 1].substring(0, 3);

DateTime dateOnly(DateTime date) => DateTime(date.year, date.month, date.day);

/// Whole days from [from] to [to]. Uses UTC so a DST change doesn't shave
/// an hour off and round the count down.
int daysBetween(DateTime from, DateTime to) => DateTime.utc(
  to.year,
  to.month,
  to.day,
).difference(DateTime.utc(from.year, from.month, from.day)).inDays;

bool isSameDay(DateTime a, DateTime b) =>
    a.year == b.year && a.month == b.month && a.day == b.day;

/// "Wednesday, November 26, 2026"
String formatLongDate(DateTime date) =>
    '${weekdayNames[date.weekday - 1]}, ${monthNames[date.month - 1]} '
    '${date.day}, ${date.year}';

/// "Nov 26" or "Nov 26 – Nov 29, 2026" style ranges, omitting repeated parts.
String formatDateRange(DateTime start, DateTime end, {bool withYear = true}) {
  final year = withYear ? ', ${end.year}' : '';
  if (isSameDay(start, end)) {
    return '${shortWeekday(start)}, ${shortMonth(start)} ${start.day}$year';
  }
  if (start.year != end.year) {
    return '${shortMonth(start)} ${start.day}, ${start.year} – '
        '${shortMonth(end)} ${end.day}, ${end.year}';
  }
  if (start.month == end.month) {
    return '${shortMonth(start)} ${start.day} – ${end.day}$year';
  }
  return '${shortMonth(start)} ${start.day} – ${shortMonth(end)} ${end.day}$year';
}

/// "16:30" -> "4:30 PM"
String formatTime(String time24) {
  final [hourText, minute] = time24.split(':');
  final hour = int.parse(hourText);
  final suffix = hour < 12 ? 'AM' : 'PM';
  final hour12 = hour % 12 == 0 ? 12 : hour % 12;
  return '$hour12:$minute $suffix';
}

/// "Today", "Tomorrow", "In 12 days", "In 3 weeks" or "Happening now".
String formatCountdown(DateTime start, DateTime end, DateTime today) {
  if (!today.isBefore(start) && !today.isAfter(end)) return 'Happening now';
  final days = daysBetween(today, start);
  if (days == 0) return 'Today';
  if (days == 1) return 'Tomorrow';
  if (days < 21) return 'In $days days';
  if (days < 60) return 'In ${(days / 7).round()} weeks';
  return 'In ${(days / 30.4).round()} months';
}
