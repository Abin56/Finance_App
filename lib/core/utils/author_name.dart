/// Derives a display name for the signed-in user — for contexts (like a PDF
/// export's "Paid By" column) that need their name but may only have an
/// email on hand.
///
/// [displayName] (Google/Firebase's own account name, e.g. "Abin John") wins
/// whenever it's non-empty — it already has real word spacing, so nothing
/// needs to be guessed. Only when it's null/empty does this fall back to
/// [email]'s local part (before "@"), with trailing digits (a common
/// Gmail-suggested-alias artifact) stripped and the first letter capitalized
/// — e.g. "abinjohn8089@gmail.com" -> "Abinjohn", "rahul123@gmail.com" ->
/// "Rahul". Deliberately never splits a no-separator local part into guessed
/// words ("abinjohn" is never turned into "Abin John") — there is no
/// reliable signal for where one word ends and the next begins, and a wrong
/// guess is worse than a single run-on word. Falls back to [fallback] when
/// neither [displayName] nor [email] yields anything usable.
String authorNameFromEmail(String? email, {String? displayName, String fallback = 'You'}) {
  if (displayName != null && displayName.trim().isNotEmpty) return displayName.trim();

  if (email == null || email.isEmpty) return fallback;

  final atIndex = email.indexOf('@');
  final localPart = atIndex == -1 ? email : email.substring(0, atIndex);

  final withoutTrailingDigits = localPart.replaceAll(RegExp(r'\d+$'), '');
  if (withoutTrailingDigits.isEmpty) return fallback;

  return withoutTrailingDigits[0].toUpperCase() + withoutTrailingDigits.substring(1);
}
