import 'package:flutter/material.dart';

/// The fixed catalog of icons a category can use, keyed by a stable string
/// (persisted in Firestore) rather than a raw codepoint — codepoints aren't
/// guaranteed constant across Flutter/Material versions, and non-const
/// `IconData` breaks Flutter's icon tree-shaking. [Category.iconKey] always
/// looks itself up here; unknown/legacy keys fall back to [fallback].
abstract class CategoryIcons {
  CategoryIcons._();

  static const Map<String, IconData> catalog = {
    'work': Icons.work_outline_rounded,
    'laptop': Icons.laptop_mac_outlined,
    'restaurant': Icons.restaurant_outlined,
    'car': Icons.directions_car_outlined,
    'shopping_bag': Icons.shopping_bag_outlined,
    'receipt': Icons.receipt_long_outlined,
    'movie': Icons.movie_outlined,
    'health': Icons.favorite_outline_rounded,
    'transfer': Icons.swap_horiz_rounded,
    'other': Icons.more_horiz_rounded,
    'home': Icons.home_outlined,
    'school': Icons.school_outlined,
    'flight': Icons.flight_takeoff_outlined,
    'pets': Icons.pets_outlined,
    'fitness': Icons.fitness_center_outlined,
    'gift': Icons.card_giftcard_outlined,
    'savings': Icons.savings_outlined,
    'groceries': Icons.local_grocery_store_outlined,
    'phone': Icons.phone_iphone_outlined,
    'celebration': Icons.celebration_outlined,
  };

  static const String fallback = 'other';

  static IconData iconFor(String key) => catalog[key] ?? catalog[fallback]!;
}
