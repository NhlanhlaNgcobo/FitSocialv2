/// Parsing for numbers a person typed into a field.
///
/// `double.tryParse` only understands a '.' decimal point, but the numeric
/// keyboard in a comma-decimal locale (South Africa, most of Europe) puts ','
/// on the decimal key. Every field that parsed its text directly rejected a
/// perfectly ordinary "10,01" as no number at all — which on the run log
/// surfaced as "Add a distance and a time before saving" with both filled in.
///
/// Everything a user types goes through here. Values that arrive from Health
/// Connect, Firestore or a GPS trace are machine-formatted and do not.
library;

/// The number in [raw], accepting either decimal separator; null when there
/// is no number to be had.
double? parseTypedDouble(String raw) {
  final trimmed = raw.trim();
  if (trimmed.isEmpty) return null;
  return double.tryParse(trimmed.replaceAll(',', '.'));
}

/// The whole number in [raw], read the same way. "12,0" and "12.0" are both
/// 12; "12,5" rounds to 13, not to nothing.
int? parseTypedInt(String raw) => parseTypedDouble(raw)?.round();

/// A duration typed as minutes, whole or fractional: "50,5" is 50 min 30 s.
///
/// Zero and negative entries come back as [Duration.zero] rather than null so
/// callers can test `> Duration.zero` and nothing else.
Duration parseTypedMinutes(String raw) {
  final minutes = parseTypedDouble(raw);
  if (minutes == null || minutes <= 0 || !minutes.isFinite) {
    return Duration.zero;
  }
  return Duration(seconds: (minutes * 60).round());
}
