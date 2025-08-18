import 'package:cloud_firestore/cloud_firestore.dart';

Future<void> initializeFirestore() async {
  final firestore = FirebaseFirestore.instance;

  // Check if playlists collection already has data
  final playlistSnapshot = await firestore.collection('playlists').limit(1).get();
  if (playlistSnapshot.docs.isEmpty) {
    // Create sample public playlists
    await firestore.collection('playlists').add({
      'name': 'Top Hits 2024',
      'description': 'The biggest hits of the year',
      'songs': [],
      'isPublic': true,
      'createdBy': 'system',
      'createdAt': FieldValue.serverTimestamp(),
    });
  }

  // Ensure leaderboard doc exists
  final leaderboardDoc = firestore.collection('leaderboard').doc('global');
  final leaderboardSnapshot = await leaderboardDoc.get();
  if (!leaderboardSnapshot.exists) {
    await leaderboardDoc.set({
      'lastUpdated': FieldValue.serverTimestamp(),
    });
  }
}
