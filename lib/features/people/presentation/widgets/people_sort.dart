import '../../domain/person.dart';

/// Sort order applied to the People list, chosen via the list header's
/// sort dropdown.
enum PeopleSort { name, balanceDesc, recentlyAdded }

extension PeopleSortX on PeopleSort {
  String get label {
    switch (this) {
      case PeopleSort.name:
        return 'Name';
      case PeopleSort.balanceDesc:
        return 'Balance';
      case PeopleSort.recentlyAdded:
        return 'Recently added';
    }
  }
}

/// [balances] maps person id → net position (direct ledger + Loans);
/// missing ids fall back to the ledger balance.
List<Person> applyPeopleSort(
  List<Person> people,
  PeopleSort sort, [
  Map<String, double> balances = const {},
]) {
  double balanceOf(Person p) => balances[p.id] ?? p.currentBalance;
  final sorted = [...people];
  switch (sort) {
    case PeopleSort.name:
      sorted.sort(
        (a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()),
      );
    case PeopleSort.balanceDesc:
      sorted.sort(
        (a, b) => balanceOf(b).abs().compareTo(balanceOf(a).abs()),
      );
    case PeopleSort.recentlyAdded:
      sorted.sort((a, b) => b.createdAt.compareTo(a.createdAt));
  }
  return sorted;
}
