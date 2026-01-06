import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

class FavoriteService extends ChangeNotifier {
  List<int> favorites = [];

  Future<void> loadFavorites() async {
    final prefs = await SharedPreferences.getInstance();
    final list = prefs.getStringList('favorites') ?? [];
    favorites = list.map((e) => int.tryParse(e) ?? 0).where((n) => n > 0).toList();
    notifyListeners();
  }

  bool isFav(int surahNo) => favorites.contains(surahNo);

  Future<void> toggle(int surahNo) async {
    if (isFav(surahNo)) {
      favorites.remove(surahNo);
    } else {
      favorites.add(surahNo);
    }
    final prefs = await SharedPreferences.getInstance();
    prefs.setStringList('favorites', favorites.map((e) => e.toString()).toList());
    notifyListeners();
}
}