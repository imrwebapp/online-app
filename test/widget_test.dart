import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:al_quran_mp3/services/favorite_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test('FavoriteService toggles favorites', () async {
    final service = FavoriteService();
    await service.loadFavorites();

    expect(service.isFav(1), isFalse);

    await service.toggle(1);
    expect(service.isFav(1), isTrue);

    await service.toggle(1);
    expect(service.isFav(1), isFalse);
  });
}
