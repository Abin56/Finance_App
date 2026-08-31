import '../../people/domain/person.dart';
import 'loan.dart';
import 'loan_category.dart';

/// The display title every loan surface (tile, detail, dashboard row, search
/// result) falls back to when [Loan.name] is blank — category-aware so an
/// institutional loan (no linked [Person]) never reads as "Loan to unknown".
String loanDisplayTitle(Loan loan, Person? person) {
  if (loan.name?.isNotEmpty == true) return loan.name!;
  if (loan.category == LoanCategory.personal) {
    return 'Loan to ${person?.name ?? 'unknown'}';
  }
  return loan.institutionName ?? 'Institutional Loan';
}
