import 'package:flutter/material.dart';

class CategoryService extends ChangeNotifier {
  String _selectedCategory = 'Brekkie';

  String get selectedCategory => _selectedCategory;

  void setSelectedCategory(String category) {
    _selectedCategory = category;
    notifyListeners();
  }

  void resetToDefault() {
    _selectedCategory = 'Brekkie';
    notifyListeners();
  }
}
