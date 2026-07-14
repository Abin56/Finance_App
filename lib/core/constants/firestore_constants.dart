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
  static const String payments = 'payments'; // subcollection under bills/{billId} and installments/{installmentId}
  static const String loans = 'loans';
  static const String emis = 'emis';
  static const String expenses = 'expenses';
  static const String paymentSchedules = 'paymentSchedules';
  static const String installments = 'installments'; // subcollection under paymentSchedules/{scheduleId}
  static const String creditCards = 'creditCards';
  static const String statements = 'statements'; // subcollection under creditCards/{cardId}
  static const String statementPayments = 'statementPayments'; // subcollection under statements/{statementId}
  static const String paymentBreakdowns = 'paymentBreakdowns'; // subcollection under emis/{emiId}, doc id == paymentId
}
