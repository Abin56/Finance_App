/// Collection names under `users/{userId}/...` in Firestore.
abstract class FirestoreCollections {
  FirestoreCollections._();

  static const String users = 'users';
  static const String accounts = 'accounts';
  static const String transactions = 'transactions';
  static const String categories = 'categories';
  static const String budgets = 'budgets';
  static const String savingsGoals = 'savingsGoals';
  static const String people = 'people'; // creditors & debtors
  static const String ledger = 'ledger'; // subcollection under people/{personId}
  static const String bills = 'bills';
  static const String billOccurrences = 'occurrences'; // subcollection under bills/{billId}
  static const String payments = 'payments'; // subcollection under bills/{billId} and installments/{installmentId}
  static const String loans = 'loans';
  static const String emis = 'emis';
  static const String expenses = 'expenses';
  static const String paymentSchedules = 'paymentSchedules';
  static const String installments = 'installments'; // subcollection under paymentSchedules/{scheduleId}
  static const String creditCards = 'creditCards';
  static const String sharedCreditLimits = 'sharedCreditLimits'; // bank-issued facility shared by multiple creditCards
  static const String statements = 'statements'; // subcollection under creditCards/{cardId}
  static const String statementPayments = 'statementPayments'; // subcollection under statements/{statementId}
  static const String paymentBreakdowns = 'paymentBreakdowns'; // subcollection under emis/{emiId}, doc id == paymentId

  // SMS Transaction Intelligence — Phase 3 (cloud sync foundation). Client
  // (Android)-authored, unlike the Financial Document Intelligence Engine
  // collections below: a client both creates AND deletes these documents
  // directly, so this is plain owner-scoped CRUD like accounts/transactions,
  // not the worker-authored pattern. Doc id == the local `SmsInboxItem.id`
  // (`TransactionCandidate.smsItemId`) that produced it, so re-syncing the
  // same SMS is always an overwrite, never a duplicate — see
  // `SmsCandidateCloudSync`.
  static const String smsTransactionCandidates = 'smsTransactionCandidates';

  // --- Financial Document Intelligence Engine (Architecture v1.0) ---
  // Web-only feature today (flowfi-web/lib/firestore/collections.ts) — no
  // Flutter repository layer reads/writes these yet. Declared here so the
  // names stay byte-identical with the web app the moment Flutter-side work
  // starts, since both apps share one Firestore project (financeapp-585eb)
  // and therefore one set of collection paths.
  static const String financialDocuments = 'financialDocuments';
  static const String importHistory = 'importHistory'; // subcollection under financialDocuments/{documentId}
  static const String versionHistory = 'versionHistory'; // subcollection under financialDocuments/{documentId}
  static const String changeLog = 'changeLog'; // subcollection under financialDocuments/{documentId}
  static const String documentImports = 'documentImports';
  static const String records = 'records'; // subcollection under documentImports/{importId}
  static const String merchantMappings = 'merchantMappings'; // both users/{uid}/merchantMappings and the global top-level collection
  static const String parserHistory = 'parserHistory';
  static const String aiInsights = 'aiInsights';
  static const String documentTypeRegistry = 'documentTypeRegistry'; // global, not under users/{uid}
}
