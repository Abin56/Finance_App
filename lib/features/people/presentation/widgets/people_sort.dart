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

List<Person> applyPeopleSort(List<Person> people, PeopleSort sort) {
  final sorted = [...people];
  switch (sort) {
    case PeopleSort.name:
      sorted.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    case PeopleSort.balanceDesc:
      sorted.sort((a, b) => b.currentBalance.abs().compareTo(a.currentBalance.abs()));
    case PeopleSort.recentlyAdded:
      sorted.sort((a, b) => b.createdAt.compareTo(a.createdAt));
  }
  return sorted;
}
