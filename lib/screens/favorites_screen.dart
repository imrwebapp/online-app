import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/favorite_service.dart';
import '../data/surah_list.dart';
import 'player_screen.dart';
import '../services/audio_service.dart';

class FavoritesScreen extends StatelessWidget {
  const FavoritesScreen({super.key});
  @override
  Widget build(BuildContext context) {
    final fav = Provider.of<FavoriteService>(context);
    final audio = Provider.of<AudioService>(context);
    final favSurahs = fav.favorites.map((n) => surahs.firstWhere((s) => s.number == n, orElse: () => surahs[0])).toList();

    return Scaffold(
      appBar: AppBar(title: Text('Favorites')),
      body: favSurahs.isEmpty ? Center(child: Text('No favorites yet')) : ListView.builder(
        itemCount: favSurahs.length,
        itemBuilder: (ctx, i) {
          final s = favSurahs[i];
          return ListTile(
            leading: CircleAvatar(backgroundColor: Colors.teal.shade700, child: Text('${s.number}', style: TextStyle(color: Colors.white))),
            title: Text(s.nameEn),
            subtitle: Text(s.nameAr),
            trailing: IconButton(icon: Icon(Icons.play_arrow), onPressed: () {
              audio.setSurahAndPlay(s);
              Navigator.push(context, MaterialPageRoute(builder: (_) => PlayerScreen(surah: s)));
            }),
          );
        },
      ),
);
}
}
