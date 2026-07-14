/// Static, non-localized copy used across the app.
/// (A localization layer can replace this later without touching call sites
/// if values are always referenced through [AppStrings].)
abstract class AppStrings {
  AppStrings._();

  static const String appName = 'FlowFi';
  static const String tagline = 'Your Money. Clearly Managed.';
  static const String taglineShort = 'Track • Split • Save';

  // Common actions
  static const String save = 'Save';
  static const String cancel = 'Cancel';
  static const String delete = 'Delete';
  static const String edit = 'Edit';
  static const String add = 'Add';
  static const String confirm = 'Confirm';
  static const String search = 'Search';
  static const String seeAll = 'See all';
  static const String retry = 'Retry';
  static const String done = 'Done';

  // Empty states
  static const String noTransactions = 'No transactions yet';
  static const String noTransactionsSubtitle =
      'Add your first income or expense to start tracking your money.';
  static const String noResults = 'Nothing found';
  static const String noResultsSubtitle = 'Try a different search term.';

  // Errors
  static const String genericError = 'Something went wrong';
  static const String genericErrorSubtitle = 'Please try again.';
}
