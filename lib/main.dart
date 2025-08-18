import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'firebase_options.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:provider/provider.dart';
import 'package:just_audio/just_audio.dart';
import 'package:audio_video_progress_bar/audio_video_progress_bar.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:share_plus/share_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:http/http.dart' as http;
import 'package:google_fonts/google_fonts.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'dart:convert';
import 'dart:async';
import 'dart:math';
import 'helper.dart';
import 'pages.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );
  await initializeFirestore();
  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => ThemeProvider()),
        ChangeNotifierProvider(create: (_) => AuthProvider()),
        ChangeNotifierProvider(create: (_) => UserStatsProvider()),
        ChangeNotifierProvider(create: (_) => MusicProvider()),
        ChangeNotifierProvider(create: (_) => PlaylistProvider()),
        ChangeNotifierProvider(create: (_) => GameProvider()),
        ChangeNotifierProvider(create: (_) => SocialProvider()),
      ],
      child: const MyApp(),
    ),
  );
}

// Theme Provider for Dark/Light Mode
class ThemeProvider extends ChangeNotifier {
  ThemeMode _themeMode = ThemeMode.dark;
  SharedPreferences? _prefs;

  ThemeMode get themeMode => _themeMode;

  ThemeProvider() {
    _loadTheme();
  }

  Future<void> _loadTheme() async {
    _prefs = await SharedPreferences.getInstance();
    final isDark = _prefs?.getBool('isDarkMode') ?? true;
    _themeMode = isDark ? ThemeMode.dark : ThemeMode.light;
    notifyListeners();
  }

  void toggleTheme() {
    _themeMode = _themeMode == ThemeMode.light ? ThemeMode.dark : ThemeMode.light;
    _prefs?.setBool('isDarkMode', _themeMode == ThemeMode.dark);
    notifyListeners();
  }
}

// Auth Provider for Firebase Authentication
class AuthProvider extends ChangeNotifier {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final GoogleSignIn _googleSignIn = GoogleSignIn();
  User? _user;

  User? get user => _user;
  bool get isAuthenticated => _user != null;

  AuthProvider() {
    _auth.authStateChanges().listen((User? user) {
      _user = user;
      notifyListeners();
    });
  }

  Future<void> signInWithEmail(String email, String password) async {
    try {
      await _auth.signInWithEmailAndPassword(email: email, password: password);
    } catch (e) {
      throw e;
    }
  }

  Future<void> signUpWithEmail(String email, String password, String username) async {
    try {
      UserCredential result = await _auth.createUserWithEmailAndPassword(
        email: email,
        password: password,
      );

      // Create user profile in Firestore
      await FirebaseFirestore.instance.collection('users').doc(result.user!.uid).set({
        'username': username,
        'email': email,
        'xp': 0,
        'level': 1,
        'badges': [],
        'achievements': [],
        'joinedAt': FieldValue.serverTimestamp(),
        'avatar': 'https://ui-avatars.com/api/?name=$username&background=random',
        'stats': {
          'songsPlayed': 0,
          'totalListeningTime': 0,
          'favoriteGenre': '',
          'streak': 0,
          'lastPlayedDate': null,
        },
        'friends': [],
        'playlists': [],
      });
    } catch (e) {
      throw e;
    }
  }

  Future<void> signInWithGoogle() async {
    try {
      final GoogleSignInAccount? googleUser = await _googleSignIn.signIn();
      if (googleUser == null) return;

      final GoogleSignInAuthentication googleAuth = await googleUser.authentication;
      final credential = GoogleAuthProvider.credential(
        accessToken: googleAuth.accessToken,
        idToken: googleAuth.idToken,
      );

      UserCredential result = await _auth.signInWithCredential(credential);

      // Check if user profile exists, if not create one
      final userDoc = await FirebaseFirestore.instance
          .collection('users')
          .doc(result.user!.uid)
          .get();

      if (!userDoc.exists) {
        await FirebaseFirestore.instance.collection('users').doc(result.user!.uid).set({
          'username': result.user!.displayName ?? 'User',
          'email': result.user!.email,
          'xp': 0,
          'level': 1,
          'badges': [],
          'achievements': [],
          'joinedAt': FieldValue.serverTimestamp(),
          'avatar': result.user!.photoURL ??
              'https://ui-avatars.com/api/?name=${result.user!.displayName}&background=random',
          'stats': {
            'songsPlayed': 0,
            'totalListeningTime': 0,
            'favoriteGenre': '',
            'streak': 0,
            'lastPlayedDate': null,
          },
          'friends': [],
          'playlists': [],
        });
      }
    } catch (e) {
      throw e;
    }
  }

  Future<void> signOut() async {
    await _auth.signOut();
    await _googleSignIn.signOut();
  }

  Future<void> updateProfile(String username, String? avatarUrl) async {
    if (_user == null) return;

    await FirebaseFirestore.instance
        .collection('users')
        .doc(_user!.uid)
        .update({
      'username': username,
      if (avatarUrl != null) 'avatar': avatarUrl,
    });
  }
}

// User Stats Provider for XP, Badges, Leaderboard
class UserStatsProvider extends ChangeNotifier {
  int _xp = 0;
  int _level = 1;
  List<String> _badges = [];
  List<Achievement> _achievements = [];
  Map<String, dynamic> _stats = {
    'songsPlayed': 0,
    'totalListeningTime': 0,
    'favoriteGenre': '',
    'streak': 0,
    'lastPlayedDate': null,
  };

  int get xp => _xp;
  int get level => _level;
  List<String> get badges => _badges;
  List<Achievement> get achievements => _achievements;
  Map<String, dynamic> get stats => _stats;

  void addXP(int amount) {
    _xp += amount;
    _checkLevelUp();
    _saveStats();
    notifyListeners();
  }

  void _checkLevelUp() {
    int newLevel = (_xp / 1000).floor() + 1;
    if (newLevel > _level) {
      _level = newLevel;
      _addBadge('Level $newLevel');
      _checkAchievements();
    }
  }

  void _addBadge(String badge) {
    if (!_badges.contains(badge)) {
      _badges.add(badge);
    }
  }

  void addAchievement(Achievement achievement) {
    if (!_achievements.any((a) => a.id == achievement.id)) {
      _achievements.add(achievement);
      addXP(achievement.xpReward);
      _saveStats();
    }
  }

  void _checkAchievements() {
    // Check for various achievements
    if (_stats['songsPlayed'] >= 10 && !hasAchievement('first_10_songs')) {
      addAchievement(Achievement(
        id: 'first_10_songs',
        name: 'Music Lover',
        description: 'Played 10 songs',
        icon: Icons.music_note,
        xpReward: 50,
      ));
    }

    if (_stats['songsPlayed'] >= 100 && !hasAchievement('100_songs')) {
      addAchievement(Achievement(
        id: '100_songs',
        name: 'Audiophile',
        description: 'Played 100 songs',
        icon: Icons.headphones,
        xpReward: 200,
      ));
    }

    if (_level >= 5 && !hasAchievement('level_5')) {
      addAchievement(Achievement(
        id: 'level_5',
        name: 'Rising Star',
        description: 'Reached Level 5',
        icon: Icons.star,
        xpReward: 100,
      ));
    }

    if (_stats['streak'] >= 7 && !hasAchievement('week_streak')) {
      addAchievement(Achievement(
        id: 'week_streak',
        name: 'Dedicated Listener',
        description: '7 day streak',
        icon: Icons.local_fire_department,
        xpReward: 150,
      ));
    }
  }

  bool hasAchievement(String id) {
    return _achievements.any((a) => a.id == id);
  }

  void updateStats(String key, dynamic value) {
    _stats[key] = value;
    _checkAchievements();
    _saveStats();
    notifyListeners();
  }

  void incrementSongsPlayed() {
    _stats['songsPlayed'] = (_stats['songsPlayed'] ?? 0) + 1;
    _checkAchievements();
    _saveStats();
    notifyListeners();
  }

  void updateStreak() {
    final now = DateTime.now();
    final lastPlayed = _stats['lastPlayedDate'] != null
        ? (_stats['lastPlayedDate'] as Timestamp).toDate()
        : null;

    if (lastPlayed == null) {
      _stats['streak'] = 1;
    } else {
      final difference = now.difference(lastPlayed).inDays;
      if (difference == 1) {
        _stats['streak'] = (_stats['streak'] ?? 0) + 1;
      } else if (difference > 1) {
        _stats['streak'] = 1;
      }
    }

    _stats['lastPlayedDate'] = Timestamp.now();
    _checkAchievements();
    _saveStats();
    notifyListeners();
  }

  Future<void> loadUserStats(String userId) async {
    final doc = await FirebaseFirestore.instance
        .collection('users')
        .doc(userId)
        .get();

    if (doc.exists) {
      final data = doc.data()!;
      _xp = data['xp'] ?? 0;
      _level = data['level'] ?? 1;
      _badges = List<String>.from(data['badges'] ?? []);
      _stats = data['stats'] ?? {};

      // Load achievements
      final achievementsList = data['achievements'] ?? [];
      _achievements = achievementsList.map<Achievement>((a) => Achievement(
        id: a['id'],
        name: a['name'],
        description: a['description'],
        icon: IconData(a['iconCode'], fontFamily: 'MaterialIcons'),
        xpReward: a['xpReward'],
      )).toList();

      notifyListeners();
    }
  }

  Future<void> _saveStats() async {
    final userId = FirebaseAuth.instance.currentUser?.uid;
    if (userId == null) return;

    await FirebaseFirestore.instance
        .collection('users')
        .doc(userId)
        .update({
      'xp': _xp,
      'level': _level,
      'badges': _badges,
      'stats': _stats,
      'achievements': _achievements.map((a) => {
        'id': a.id,
        'name': a.name,
        'description': a.description,
        'iconCode': a.icon.codePoint,
        'xpReward': a.xpReward,
      }).toList(),
    });
  }
}

// Achievement Model
class Achievement {
  final String id;
  final String name;
  final String description;
  final IconData icon;
  final int xpReward;

  Achievement({
    required this.id,
    required this.name,
    required this.description,
    required this.icon,
    required this.xpReward,
  });
}

// Music Provider with Queue Management
class MusicProvider extends ChangeNotifier {
  final AudioPlayer _audioPlayer = AudioPlayer();
  Song? _currentSong;
  List<Song> _queue = [];
  List<Song> _recentlyPlayed = [];
  bool _isPlaying = false;
  Duration _duration = Duration.zero;
  Duration _position = Duration.zero;
  LoopMode _loopMode = LoopMode.off;
  bool _shuffleMode = false;
  List<Song> _originalQueue = [];

  Song? get currentSong => _currentSong;
  List<Song> get queue => _queue;
  List<Song> get recentlyPlayed => _recentlyPlayed;
  bool get isPlaying => _isPlaying;
  Duration get duration => _duration;
  Duration get position => _position;
  AudioPlayer get audioPlayer => _audioPlayer;
  LoopMode get loopMode => _loopMode;
  bool get shuffleMode => _shuffleMode;

  MusicProvider() {
    _audioPlayer.durationStream.listen((duration) {
      _duration = duration ?? Duration.zero;
      notifyListeners();
    });

    _audioPlayer.positionStream.listen((position) {
      _position = position;
      notifyListeners();
    });

    _audioPlayer.playerStateStream.listen((state) {
      _isPlaying = state.playing;
      if (state.processingState == ProcessingState.completed) {
        playNext();
      }
      notifyListeners();
    });
  }

  Future<void> playSong(Song song) async {
    _currentSong = song;
    _addToRecentlyPlayed(song);
    await _audioPlayer.setUrl(song.previewUrl);
    await _audioPlayer.play();
    notifyListeners();
  }

  void _addToRecentlyPlayed(Song song) {
    _recentlyPlayed.removeWhere((s) => s.id == song.id);
    _recentlyPlayed.insert(0, song);
    if (_recentlyPlayed.length > 50) {
      _recentlyPlayed.removeLast();
    }
  }

  Future<void> playPause() async {
    if (_isPlaying) {
      await _audioPlayer.pause();
    } else {
      await _audioPlayer.play();
    }
  }

  void seekTo(Duration position) {
    _audioPlayer.seek(position);
  }

  void addToQueue(Song song) {
    _queue.add(song);
    if (_shuffleMode) {
      _originalQueue.add(song);
    }
    notifyListeners();
  }

  void removeFromQueue(int index) {
    if (index < _queue.length) {
      final song = _queue[index];
      _queue.removeAt(index);
      if (_shuffleMode) {
        _originalQueue.remove(song);
      }
      notifyListeners();
    }
  }

  void clearQueue() {
    _queue.clear();
    _originalQueue.clear();
    notifyListeners();
  }

  void playNext() {
    if (_loopMode == LoopMode.one && _currentSong != null) {
      playSong(_currentSong!);
    } else if (_queue.isNotEmpty) {
      final nextSong = _queue.removeAt(0);
      playSong(nextSong);
    } else if (_loopMode == LoopMode.all && _currentSong != null) {
      // Restart queue
      playSong(_currentSong!);
    }
  }

  void playPrevious() {
    if (_recentlyPlayed.length > 1) {
      final previousSong = _recentlyPlayed[1];
      playSong(previousSong);
    }
  }

  void toggleLoopMode() {
    switch (_loopMode) {
      case LoopMode.off:
        _loopMode = LoopMode.all;
        break;
      case LoopMode.all:
        _loopMode = LoopMode.one;
        break;
      case LoopMode.one:
        _loopMode = LoopMode.off;
        break;
    }
    notifyListeners();
  }

  void toggleShuffle() {
    _shuffleMode = !_shuffleMode;
    if (_shuffleMode) {
      _originalQueue = List.from(_queue);
      _queue.shuffle();
    } else {
      _queue = List.from(_originalQueue);
    }
    notifyListeners();
  }

  @override
  void dispose() {
    _audioPlayer.dispose();
    super.dispose();
  }
}

// Playlist Provider
class PlaylistProvider extends ChangeNotifier {
  List<Playlist> _playlists = [];
  List<Playlist> _publicPlaylists = [];

  List<Playlist> get playlists => _playlists;
  List<Playlist> get publicPlaylists => _publicPlaylists;

  Future<void> loadPlaylists(String userId) async {
    // Load user's playlists
    final userDoc = await FirebaseFirestore.instance
        .collection('users')
        .doc(userId)
        .collection('playlists')
        .get();

    _playlists = userDoc.docs.map((doc) {
      final data = doc.data();
      return Playlist(
        id: doc.id,
        name: data['name'],
        description: data['description'],
        coverUrl: data['coverUrl'],
        songs: List<Song>.from(data['songs']?.map((s) => Song(
          id: s['id'],
          title: s['title'],
          artist: s['artist'],
          albumArt: s['albumArt'],
          previewUrl: s['previewUrl'],
          albumName: s['albumName'],
        )) ?? []),
        createdBy: userId,
        isPublic: data['isPublic'] ?? false,
        createdAt: data['createdAt']?.toDate() ?? DateTime.now(),
      );
    }).toList();

    // Load public playlists
    final publicDoc = await FirebaseFirestore.instance
        .collection('playlists')
        .where('isPublic', isEqualTo: true)
        .limit(20)
        .get();

    _publicPlaylists = publicDoc.docs.map((doc) {
      final data = doc.data();
      return Playlist(
        id: doc.id,
        name: data['name'],
        description: data['description'],
        coverUrl: data['coverUrl'],
        songs: List<Song>.from(data['songs']?.map((s) => Song(
          id: s['id'],
          title: s['title'],
          artist: s['artist'],
          albumArt: s['albumArt'],
          previewUrl: s['previewUrl'],
          albumName: s['albumName'],
        )) ?? []),
        createdBy: data['createdBy'],
        isPublic: true,
        createdAt: data['createdAt']?.toDate() ?? DateTime.now(),
      );
    }).toList();

    notifyListeners();
  }

  Future<void> createPlaylist(String name, String description, String userId) async {
    final playlist = Playlist(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      name: name,
      description: description,
      coverUrl: 'https://via.placeholder.com/300',
      songs: [],
      createdBy: userId,
      isPublic: false,
      createdAt: DateTime.now(),
    );

    // Save to Firestore
    final docRef = await FirebaseFirestore.instance
        .collection('users')
        .doc(userId)
        .collection('playlists')
        .add({
      'name': name,
      'description': description,
      'coverUrl': playlist.coverUrl,
      'songs': [],
      'isPublic': false,
      'createdAt': FieldValue.serverTimestamp(),
    });

    playlist.id = docRef.id;
    _playlists.add(playlist);
    notifyListeners();
  }

  Future<void> addSongToPlaylist(String playlistId, Song song, String userId) async {
    final playlistIndex = _playlists.indexWhere((p) => p.id == playlistId);
    if (playlistIndex != -1) {
      _playlists[playlistIndex].songs.add(song);

      // Update Firestore
      await FirebaseFirestore.instance
          .collection('users')
          .doc(userId)
          .collection('playlists')
          .doc(playlistId)
          .update({
        'songs': FieldValue.arrayUnion([{
          'id': song.id,
          'title': song.title,
          'artist': song.artist,
          'albumArt': song.albumArt,
          'previewUrl': song.previewUrl,
          'albumName': song.albumName,
        }]),
      });

      notifyListeners();
    }
  }

  Future<void> deletePlaylist(String playlistId, String userId) async {
    _playlists.removeWhere((p) => p.id == playlistId);

    await FirebaseFirestore.instance
        .collection('users')
        .doc(userId)
        .collection('playlists')
        .doc(playlistId)
        .delete();

    notifyListeners();
  }

  Future<void> togglePlaylistVisibility(String playlistId, String userId) async {
    final playlist = _playlists.firstWhere((p) => p.id == playlistId);
    playlist.isPublic = !playlist.isPublic;

    await FirebaseFirestore.instance
        .collection('users')
        .doc(userId)
        .collection('playlists')
        .doc(playlistId)
        .update({'isPublic': playlist.isPublic});

    if (playlist.isPublic) {
      // Add to public playlists collection
      await FirebaseFirestore.instance
          .collection('playlists')
          .doc(playlistId)
          .set({
        'name': playlist.name,
        'description': playlist.description,
        'coverUrl': playlist.coverUrl,
        'songs': playlist.songs.map((s) => {
          'id': s.id,
          'title': s.title,
          'artist': s.artist,
          'albumArt': s.albumArt,
          'previewUrl': s.previewUrl,
          'albumName': s.albumName,
        }).toList(),
        'createdBy': userId,
        'isPublic': true,
        'createdAt': playlist.createdAt,
      });
    } else {
      // Remove from public playlists collection
      await FirebaseFirestore.instance
          .collection('playlists')
          .doc(playlistId)
          .delete();
    }

    notifyListeners();
  }
}

// Game Provider
class GameProvider extends ChangeNotifier {
  GameMode? _currentGame;
  int _gameScore = 0;
  Timer? _gameTimer;
  List<Challenge> _dailyChallenges = [];
  DateTime? _lastChallengeDate;

  GameMode? get currentGame => _currentGame;
  int get gameScore => _gameScore;
  List<Challenge> get dailyChallenges => _dailyChallenges;

  GameProvider() {
    _loadDailyChallenges();
  }

  void _loadDailyChallenges() {
    final now = DateTime.now();
    if (_lastChallengeDate == null ||
        !_isSameDay(_lastChallengeDate!, now)) {
      _generateDailyChallenges();
      _lastChallengeDate = now;
    }
  }

  bool _isSameDay(DateTime a, DateTime b) {
    return a.year == b.year && a.month == b.month && a.day == b.day;
  }

  void _generateDailyChallenges() {
    _dailyChallenges = [
      Challenge(
        id: 'daily_1',
        title: 'Music Explorer',
        description: 'Play 10 different songs',
        xpReward: 100,
        progress: 0,
        target: 10,
        type: ChallengeType.playSongs,
      ),
      Challenge(
        id: 'daily_2',
        title: 'Genre Master',
        description: 'Listen to 3 different genres',
        xpReward: 150,
        progress: 0,
        target: 3,
        type: ChallengeType.genres,
      ),
      Challenge(
        id: 'daily_3',
        title: 'Marathon Listener',
        description: 'Listen for 30 minutes total',
        xpReward: 200,
        progress: 0,
        target: 30,
        type: ChallengeType.listeningTime,
      ),
    ];
    notifyListeners();
  }

  void updateChallengeProgress(ChallengeType type, int value) {
    for (var challenge in _dailyChallenges) {
      if (challenge.type == type && !challenge.completed) {
        challenge.progress = min(challenge.progress + value, challenge.target);
        if (challenge.progress >= challenge.target) {
          challenge.completed = true;
          // Award XP through provider
        }
      }
    }
    notifyListeners();
  }

  void startGame(GameMode mode) {
    _currentGame = mode;
    _gameScore = 0;

    switch (mode) {
      case GameMode.quickPlay:
      // Quick play: earn XP for each song
        break;
      case GameMode.challenge:
      // Time-based challenge
        _startChallengeMode();
        break;
      case GameMode.marathon:
      // Long listening session
        _startMarathonMode();
        break;
      case GameMode.battle:
      // PvP mode
        _startBattleMode();
        break;
    }

    notifyListeners();
  }

  void _startChallengeMode() {
    _gameTimer = Timer.periodic(const Duration(minutes: 1), (timer) {
      _gameScore += 10;
      notifyListeners();
    });
  }

  void _startMarathonMode() {
    _gameTimer = Timer.periodic(const Duration(seconds: 30), (timer) {
      _gameScore += 5;
      notifyListeners();
    });
  }

  void _startBattleMode() {
    // Implement PvP logic
  }

  void endGame() {
    _gameTimer?.cancel();
    _currentGame = null;
    notifyListeners();
  }

  @override
  void dispose() {
    _gameTimer?.cancel();
    super.dispose();
  }
}

// Social Provider
class SocialProvider extends ChangeNotifier {
  List<String> _friends = [];
  List<Activity> _feed = [];

  List<String> get friends => _friends;
  List<Activity> get feed => _feed;

  Future<void> loadFriends(String userId) async {
    final doc = await FirebaseFirestore.instance
        .collection('users')
        .doc(userId)
        .get();

    if (doc.exists) {
      _friends = List<String>.from(doc.data()?['friends'] ?? []);
      await _loadFeed(userId);
      notifyListeners();
    }
  }

  Future<void> _loadFeed(String userId) async {
    // Load activities from friends
    if (_friends.isEmpty) return;

    final activities = await FirebaseFirestore.instance
        .collection('activities')
        .where('userId', whereIn: _friends)
        .orderBy('timestamp', descending: true)
        .limit(50)
        .get();

    _feed = activities.docs.map((doc) {
      final data = doc.data();
      return Activity(
        id: doc.id,
        userId: data['userId'],
        username: data['username'],
        type: data['type'],
        content: data['content'],
        timestamp: data['timestamp']?.toDate() ?? DateTime.now(),
      );
    }).toList();
  }

  Future<void> addFriend(String friendId, String userId) async {
    if (!_friends.contains(friendId)) {
      _friends.add(friendId);

      await FirebaseFirestore.instance
          .collection('users')
          .doc(userId)
          .update({
        'friends': FieldValue.arrayUnion([friendId]),
      });

      await _loadFeed(userId);
      notifyListeners();
    }
  }

  Future<void> removeFriend(String friendId, String userId) async {
    _friends.remove(friendId);

    await FirebaseFirestore.instance
        .collection('users')
        .doc(userId)
        .update({
      'friends': FieldValue.arrayRemove([friendId]),
    });

    await _loadFeed(userId);
    notifyListeners();
  }

  Future<void> shareActivity(String userId, String username, String type, String content) async {
    await FirebaseFirestore.instance.collection('activities').add({
      'userId': userId,
      'username': username,
      'type': type,
      'content': content,
      'timestamp': FieldValue.serverTimestamp(),
    });
  }
}

// Models
class Song {
  final String id;
  final String title;
  final String artist;
  final String? albumArt;
  final String previewUrl;
  final String? albumName;
  final Duration? duration;

  Song({
    required this.id,
    required this.title,
    required this.artist,
    this.albumArt,
    required this.previewUrl,
    this.albumName,
    this.duration,
  });
}

class Playlist {
  String id;
  final String name;
  final String description;
  final String coverUrl;
  final List<Song> songs;
  final String createdBy;
  bool isPublic;
  final DateTime createdAt;

  Playlist({
    required this.id,
    required this.name,
    required this.description,
    required this.coverUrl,
    required this.songs,
    required this.createdBy,
    required this.isPublic,
    required this.createdAt,
  });
}

class Challenge {
  final String id;
  final String title;
  final String description;
  final int xpReward;
  int progress;
  final int target;
  final ChallengeType type;
  bool completed;

  Challenge({
    required this.id,
    required this.title,
    required this.description,
    required this.xpReward,
    required this.progress,
    required this.target,
    required this.type,
    this.completed = false,
  });
}

class Activity {
  final String id;
  final String userId;
  final String username;
  final String type;
  final String content;
  final DateTime timestamp;

  Activity({
    required this.id,
    required this.userId,
    required this.username,
    required this.type,
    required this.content,
    required this.timestamp,
  });
}

// Enums
enum GameMode { quickPlay, challenge, marathon, battle }
enum ChallengeType { playSongs, genres, listeningTime }

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer<ThemeProvider>(
      builder: (context, themeProvider, child) {
        return MaterialApp(
          title: 'Music Stream Pro',
          debugShowCheckedModeBanner: false,
          themeMode: themeProvider.themeMode,
          theme: ThemeData(
            colorScheme: ColorScheme.fromSeed(
              seedColor: Colors.purple,
              brightness: Brightness.light,
            ),
            textTheme: GoogleFonts.poppinsTextTheme(),
            useMaterial3: true,
          ),
          darkTheme: ThemeData(
            colorScheme: ColorScheme.fromSeed(
              seedColor: Colors.purple,
              brightness: Brightness.dark,
            ),
            textTheme: GoogleFonts.poppinsTextTheme(
              ThemeData.dark().textTheme,
            ),
            useMaterial3: true,
          ),
          home: const AuthWrapper(),
        );
      },
    );
  }
}

// Auth Wrapper
class AuthWrapper extends StatelessWidget {
  const AuthWrapper({super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer<AuthProvider>(
      builder: (context, authProvider, child) {
        if (authProvider.isAuthenticated) {
          return const MainApp();
        } else {
          return const LandingPage();
        }
      },
    );
  }
}

// Landing Page with Hero Section
class LandingPage extends StatefulWidget {
  const LandingPage({super.key});

  @override
  State<LandingPage> createState() => _LandingPageState();
}

class _LandingPageState extends State<LandingPage> with TickerProviderStateMixin {
  late AnimationController _animationController;
  late Animation<double> _fadeAnimation;

  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(
      duration: const Duration(seconds: 2),
      vsync: this,
    );
    _fadeAnimation = CurvedAnimation(
      parent: _animationController,
      curve: Curves.easeIn,
    );
    _animationController.forward();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              Theme.of(context).colorScheme.primary.withOpacity(0.8),
              Theme.of(context).colorScheme.secondary.withOpacity(0.6),
              Theme.of(context).colorScheme.tertiary.withOpacity(0.4),
            ],
          ),
        ),
        child: SafeArea(
          child: Column(
            children: [
              // Hero Section
              Expanded(
                child: Center(
                  child: FadeTransition(
                    opacity: _fadeAnimation,
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.music_note_rounded,
                          size: 120,
                          color: Colors.white,
                        ).animate()
                            .scale(duration: 600.ms)
                            .then(delay: 200.ms)
                            .shake(),
                        const SizedBox(height: 20),
                        Text(
                          'Music Stream Pro',
                          style: GoogleFonts.poppins(
                            fontSize: 36,
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                          ),
                        ).animate()
                            .fadeIn(duration: 800.ms)
                            .slideY(begin: 0.3, end: 0),
                        const SizedBox(height: 10),
                        Text(
                          'Listen • Play • Compete',
                          style: GoogleFonts.poppins(
                            fontSize: 18,
                            color: Colors.white70,
                          ),
                        ).animate()
                            .fadeIn(delay: 400.ms, duration: 800.ms),
                        const SizedBox(height: 50),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            ElevatedButton.icon(
                              onPressed: () {
                                Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (context) => const LoginPage(),
                                  ),
                                );
                              },
                              icon: const Icon(Icons.login),
                              label: const Text('Login'),
                              style: ElevatedButton.styleFrom(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 30,
                                  vertical: 15,
                                ),
                                textStyle: const TextStyle(fontSize: 18),
                              ),
                            ).animate()
                                .fadeIn(delay: 600.ms, duration: 600.ms)
                                .slideX(begin: -0.2, end: 0),
                            const SizedBox(width: 20),
                            OutlinedButton.icon(
                              onPressed: () {
                                Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (context) => const SignUpPage(),
                                  ),
                                );
                              },
                              icon: const Icon(Icons.person_add, color: Colors.white),
                              label: const Text('Sign Up',
                                  style: TextStyle(color: Colors.white)),
                              style: OutlinedButton.styleFrom(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 30,
                                  vertical: 15,
                                ),
                                textStyle: const TextStyle(fontSize: 18),
                                side: const BorderSide(color: Colors.white),
                              ),
                            ).animate()
                                .fadeIn(delay: 600.ms, duration: 600.ms)
                                .slideX(begin: 0.2, end: 0),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              // Features Section
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.surface,
                  borderRadius: const BorderRadius.only(
                    topLeft: Radius.circular(30),
                    topRight: Radius.circular(30),
                  ),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    _buildFeature(Icons.playlist_play, 'Playlists'),
                    _buildFeature(Icons.leaderboard, 'Compete'),
                    _buildFeature(Icons.badge, 'Earn Badges'),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildFeature(IconData icon, String label) {
    return Column(
      children: [
        Icon(icon, size: 40, color: Theme.of(context).colorScheme.primary),
        const SizedBox(height: 5),
        Text(label, style: const TextStyle(fontSize: 14)),
      ],
    ).animate()
        .fadeIn(delay: 800.ms, duration: 600.ms)
        .scale(begin: const Offset(0.8, 0.8), end: const Offset(1, 1));
  }

  @override
  void dispose() {
    _animationController.dispose();
    super.dispose();
  }
}

// Login Page
class LoginPage extends StatefulWidget {
  const LoginPage({super.key});

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _isLoading = false;
  bool _obscurePassword = true;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Login'),
        backgroundColor: Colors.transparent,
        elevation: 0,
      ),
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              Theme.of(context).colorScheme.primary.withOpacity(0.1),
              Theme.of(context).colorScheme.surface,
            ],
          ),
        ),
        child: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: Form(
                key: _formKey,
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      Icons.lock_outline,
                      size: 80,
                      color: Theme.of(context).colorScheme.primary,
                    ).animate()
                        .fadeIn(duration: 600.ms)
                        .scale(),
                    const SizedBox(height: 30),
                    Text(
                      'Welcome Back!',
                      style: GoogleFonts.poppins(
                        fontSize: 28,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 10),
                    Text(
                      'Login to continue your music journey',
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.onSurface.withOpacity(0.6),
                      ),
                    ),
                    const SizedBox(height: 40),
                    TextFormField(
                      controller: _emailController,
                      decoration: InputDecoration(
                        labelText: 'Email',
                        prefixIcon: const Icon(Icons.email_outlined),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      validator: (value) {
                        if (value == null || value.isEmpty) {
                          return 'Please enter your email';
                        }
                        if (!value.contains('@')) {
                          return 'Please enter a valid email';
                        }
                        return null;
                      },
                    ),
                    const SizedBox(height: 20),
                    TextFormField(
                      controller: _passwordController,
                      obscureText: _obscurePassword,
                      decoration: InputDecoration(
                        labelText: 'Password',
                        prefixIcon: const Icon(Icons.lock_outline),
                        suffixIcon: IconButton(
                          icon: Icon(
                            _obscurePassword
                                ? Icons.visibility_off
                                : Icons.visibility,
                          ),
                          onPressed: () {
                            setState(() {
                              _obscurePassword = !_obscurePassword;
                            });
                          },
                        ),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      validator: (value) {
                        if (value == null || value.isEmpty) {
                          return 'Please enter your password';
                        }
                        if (value.length < 6) {
                          return 'Password must be at least 6 characters';
                        }
                        return null;
                      },
                    ),
                    const SizedBox(height: 30),
                    SizedBox(
                      width: double.infinity,
                      height: 50,
                      child: ElevatedButton(
                        onPressed: _isLoading ? null : _handleLogin,
                        style: ElevatedButton.styleFrom(
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        child: _isLoading
                            ? const CircularProgressIndicator()
                            : const Text('Login', style: TextStyle(fontSize: 18)),
                      ),
                    ),
                    const SizedBox(height: 20),
                    const Text('OR'),
                    const SizedBox(height: 20),
                    SizedBox(
                      width: double.infinity,
                      height: 50,
                      child: OutlinedButton.icon(
                        onPressed: _isLoading ? null : _handleGoogleSignIn,
                        icon: const Icon(Icons.g_mobiledata, size: 30),
                        label: const Text('Sign in with Google'),
                        style: OutlinedButton.styleFrom(
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 20),
                    TextButton(
                      onPressed: () {
                        Navigator.pushReplacement(
                          context,
                          MaterialPageRoute(
                            builder: (context) => const SignUpPage(),
                          ),
                        );
                      },
                      child: const Text("Don't have an account? Sign Up"),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _handleLogin() async {
    if (_formKey.currentState!.validate()) {
      setState(() {
        _isLoading = true;
      });

      try {
        await context.read<AuthProvider>().signInWithEmail(
          _emailController.text,
          _passwordController.text,
        );

        if (mounted) {
          Navigator.pushAndRemoveUntil(
            context,
            MaterialPageRoute(builder: (context) => const MainApp()),
                (route) => false,
          );
        }
      } catch (e) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Login failed: ${e.toString()}')),
        );
      } finally {
        if (mounted) {
          setState(() {
            _isLoading = false;
          });
        }
      }
    }
  }

  Future<void> _handleGoogleSignIn() async {
    setState(() {
      _isLoading = true;
    });

    try {
      await context.read<AuthProvider>().signInWithGoogle();

      if (mounted) {
        Navigator.pushAndRemoveUntil(
          context,
          MaterialPageRoute(builder: (context) => const MainApp()),
              (route) => false,
        );
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Google sign in failed: ${e.toString()}')),
      );
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }
}

// Sign Up Page
class SignUpPage extends StatefulWidget {
  const SignUpPage({super.key});

  @override
  State<SignUpPage> createState() => _SignUpPageState();
}

class _SignUpPageState extends State<SignUpPage> {
  final _formKey = GlobalKey<FormState>();
  final _usernameController = TextEditingController();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _isLoading = false;
  bool _obscurePassword = true;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Sign Up'),
        backgroundColor: Colors.transparent,
        elevation: 0,
      ),
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              Theme.of(context).colorScheme.primary.withOpacity(0.1),
              Theme.of(context).colorScheme.surface,
            ],
          ),
        ),
        child: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: Form(
                key: _formKey,
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      Icons.person_add_outlined,
                      size: 80,
                      color: Theme.of(context).colorScheme.primary,
                    ).animate()
                        .fadeIn(duration: 600.ms)
                        .scale(),
                    const SizedBox(height: 30),
                    Text(
                      'Create Account',
                      style: GoogleFonts.poppins(
                        fontSize: 28,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 10),
                    Text(
                      'Start your musical journey today',
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.onSurface.withOpacity(0.6),
                      ),
                    ),
                    const SizedBox(height: 40),
                    TextFormField(
                      controller: _usernameController,
                      decoration: InputDecoration(
                        labelText: 'Username',
                        prefixIcon: const Icon(Icons.person_outline),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      validator: (value) {
                        if (value == null || value.isEmpty) {
                          return 'Please enter a username';
                        }
                        if (value.length < 3) {
                          return 'Username must be at least 3 characters';
                        }
                        return null;
                      },
                    ),
                    const SizedBox(height: 20),
                    TextFormField(
                      controller: _emailController,
                      decoration: InputDecoration(
                        labelText: 'Email',
                        prefixIcon: const Icon(Icons.email_outlined),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      validator: (value) {
                        if (value == null || value.isEmpty) {
                          return 'Please enter your email';
                        }
                        if (!value.contains('@')) {
                          return 'Please enter a valid email';
                        }
                        return null;
                      },
                    ),
                    const SizedBox(height: 20),
                    TextFormField(
                      controller: _passwordController,
                      obscureText: _obscurePassword,
                      decoration: InputDecoration(
                        labelText: 'Password',
                        prefixIcon: const Icon(Icons.lock_outline),
                        suffixIcon: IconButton(
                          icon: Icon(
                            _obscurePassword
                                ? Icons.visibility_off
                                : Icons.visibility,
                          ),
                          onPressed: () {
                            setState(() {
                              _obscurePassword = !_obscurePassword;
                            });
                          },
                        ),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      validator: (value) {
                        if (value == null || value.isEmpty) {
                          return 'Please enter a password';
                        }
                        if (value.length < 6) {
                          return 'Password must be at least 6 characters';
                        }
                        return null;
                      },
                    ),
                    const SizedBox(height: 30),
                    SizedBox(
                      width: double.infinity,
                      height: 50,
                      child: ElevatedButton(
                        onPressed: _isLoading ? null : _handleSignUp,
                        style: ElevatedButton.styleFrom(
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        child: _isLoading
                            ? const CircularProgressIndicator()
                            : const Text('Sign Up', style: TextStyle(fontSize: 18)),
                      ),
                    ),
                    const SizedBox(height: 20),
                    TextButton(
                      onPressed: () {
                        Navigator.pushReplacement(
                          context,
                          MaterialPageRoute(
                            builder: (context) => const LoginPage(),
                          ),
                        );
                      },
                      child: const Text('Already have an account? Login'),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _handleSignUp() async {
    if (_formKey.currentState!.validate()) {
      setState(() {
        _isLoading = true;
      });

      try {
        await context.read<AuthProvider>().signUpWithEmail(
          _emailController.text,
          _passwordController.text,
          _usernameController.text,
        );

        if (mounted) {
          Navigator.pushAndRemoveUntil(
            context,
            MaterialPageRoute(builder: (context) => const MainApp()),
                (route) => false,
          );
        }
      } catch (e) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Sign up failed: ${e.toString()}')),
        );
      } finally {
        if (mounted) {
          setState(() {
            _isLoading = false;
          });
        }
      }
    }
  }

  @override
  void dispose() {
    _usernameController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }
}

// Main App with Navigation
class MainApp extends StatefulWidget {
  const MainApp({super.key});

  @override
  State<MainApp> createState() => _MainAppState();
}

class _MainAppState extends State<MainApp> {
  int _selectedIndex = 0;

  final List<Widget> _pages = [
    const HomePage(),
    const SearchPage(),
    const PlaylistsPage(),
    const GameCenterPage(),
    const ProfilePage(),
  ];

  @override
  void initState() {
    super.initState();
    // Load user data
    final userId = context.read<AuthProvider>().user?.uid;
    if (userId != null) {
      context.read<UserStatsProvider>().loadUserStats(userId);
      context.read<PlaylistProvider>().loadPlaylists(userId);
      context.read<SocialProvider>().loadFriends(userId);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          _pages[_selectedIndex],
          // Full Music Player
          Positioned(
            bottom: 0,
            left: 0,
            right: 0,
            child: Consumer<MusicProvider>(
              builder: (context, musicProvider, child) {
                if (musicProvider.currentSong == null) return const SizedBox.shrink();

                return GestureDetector(
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => const FullPlayerPage(),
                      ),
                    );
                  },
                  child: Container(
                    margin: const EdgeInsets.only(bottom: 80),
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.surface,
                      borderRadius: BorderRadius.circular(12),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.1),
                          blurRadius: 10,
                          offset: const Offset(0, -5),
                        ),
                      ],
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        ListTile(
                          leading: ClipRRect(
                            borderRadius: BorderRadius.circular(8),
                            child: musicProvider.currentSong!.albumArt != null
                                ? CachedNetworkImage(
                              imageUrl: musicProvider.currentSong!.albumArt!,
                              width: 50,
                              height: 50,
                              fit: BoxFit.cover,
                            )
                                : Container(
                              width: 50,
                              height: 50,
                              color: Colors.grey[800],
                              child: const Icon(Icons.music_note),
                            ),
                          ),
                          title: Text(
                            musicProvider.currentSong!.title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          subtitle: Text(
                            musicProvider.currentSong!.artist,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          trailing: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              IconButton(
                                icon: const Icon(Icons.skip_previous),
                                onPressed: () => musicProvider.playPrevious(),
                              ),
                              IconButton(
                                icon: Icon(
                                  musicProvider.isPlaying ? Icons.pause : Icons.play_arrow,
                                ),
                                onPressed: () => musicProvider.playPause(),
                              ),
                              IconButton(
                                icon: const Icon(Icons.skip_next),
                                onPressed: () => musicProvider.playNext(),
                              ),
                            ],
                          ),
                        ),
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 16.0),
                          child: ProgressBar(
                            progress: musicProvider.position,
                            total: musicProvider.duration,
                            progressBarColor: Theme.of(context).colorScheme.primary,
                            baseBarColor: Theme.of(context).colorScheme.primary.withOpacity(0.3),
                            barHeight: 3.0,
                            thumbRadius: 5.0,
                            onSeek: musicProvider.seekTo,
                            timeLabelLocation: TimeLabelLocation.none,
                          ),
                        ),
                        const SizedBox(height: 8),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _selectedIndex,
        onDestinationSelected: (index) {
          setState(() {
            _selectedIndex = index;
          });
        },
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.home_outlined),
            selectedIcon: Icon(Icons.home),
            label: 'Home',
          ),
          NavigationDestination(
            icon: Icon(Icons.search_outlined),
            selectedIcon: Icon(Icons.search),
            label: 'Search',
          ),
          NavigationDestination(
            icon: Icon(Icons.library_music_outlined),
            selectedIcon: Icon(Icons.library_music),
            label: 'Library',
          ),
          NavigationDestination(
            icon: Icon(Icons.sports_esports_outlined),
            selectedIcon: Icon(Icons.sports_esports),
            label: 'Games',
          ),
          NavigationDestination(
            icon: Icon(Icons.person_outline),
            selectedIcon: Icon(Icons.person),
            label: 'Profile',
          ),
        ],
      ),
    );
  }
}

// Home Page with Daily Challenges
class HomePage extends StatelessWidget {
  const HomePage({super.key});

  @override
  Widget build(BuildContext context) {
    final userStats = context.watch<UserStatsProvider>();
    final gameProvider = context.watch<GameProvider>();

    return CustomScrollView(
      slivers: [
        SliverAppBar(
          expandedHeight: 200,
          floating: false,
          pinned: true,
          actions: [
            IconButton(
              icon: const Icon(Icons.notifications_outlined),
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => const NotificationsPage(),
                  ),
                );
              },
            ),
            Consumer<ThemeProvider>(
              builder: (context, themeProvider, child) {
                return IconButton(
                  icon: Icon(
                    themeProvider.themeMode == ThemeMode.light
                        ? Icons.dark_mode
                        : Icons.light_mode,
                  ),
                  onPressed: () => themeProvider.toggleTheme(),
                );
              },
            ),
          ],
          flexibleSpace: FlexibleSpaceBar(
            title: const Text('Music Stream Pro'),
            background: Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    Theme.of(context).colorScheme.primary,
                    Theme.of(context).colorScheme.secondary,
                  ],
                ),
              ),
              child: Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const SizedBox(height: 40),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        _buildQuickStat('XP', '${userStats.xp}'),
                        const SizedBox(width: 40),
                        _buildQuickStat('Level', '${userStats.level}'),
                        const SizedBox(width: 40),
                        _buildQuickStat('Streak', '${userStats.stats['streak'] ?? 0}'),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Daily Challenges
                Text(
                  'Daily Challenges',
                  style: GoogleFonts.poppins(
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 16),
                ...gameProvider.dailyChallenges.map((challenge) =>
                    _buildChallengeCard(context, challenge)
                ),
                const SizedBox(height: 30),

                // Quick Actions
                Text(
                  'Quick Actions',
                  style: GoogleFonts.poppins(
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 16),
                GridView.count(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  crossAxisCount: 2,
                  mainAxisSpacing: 16,
                  crossAxisSpacing: 16,
                  childAspectRatio: 1.5,
                  children: [
                    _buildActionCard(
                      context,
                      'Discover',
                      Icons.explore,
                      Colors.purple,
                          () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (context) => const DiscoverPage(),
                          ),
                        );
                      },
                    ),
                    _buildActionCard(
                      context,
                      'Friends',
                      Icons.people,
                      Colors.blue,
                          () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (context) => const FriendsPage(),
                          ),
                        );
                      },
                    ),
                    _buildActionCard(
                      context,
                      'Top Charts',
                      Icons.trending_up,
                      Colors.orange,
                          () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (context) => const TopChartsPage(),
                          ),
                        );
                      },
                    ),
                    _buildActionCard(
                      context,
                      'Achievements',
                      Icons.emoji_events,
                      Colors.green,
                          () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (context) => const AchievementsPage(),
                          ),
                        );
                      },
                    ),
                  ],
                ),
                const SizedBox(height: 100), // Space for mini player
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildQuickStat(String label, String value) {
    return Column(
      children: [
        Text(
          value,
          style: const TextStyle(
            fontSize: 24,
            fontWeight: FontWeight.bold,
            color: Colors.white,
          ),
        ),
        Text(
          label,
          style: const TextStyle(
            fontSize: 14,
            color: Colors.white70,
          ),
        ),
      ],
    );
  }

  Widget _buildChallengeCard(BuildContext context, Challenge challenge) {
    final progress = challenge.progress / challenge.target;

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        challenge.title,
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      Text(
                        challenge.description,
                        style: TextStyle(
                          fontSize: 14,
                          color: Theme.of(context).colorScheme.onSurface.withOpacity(0.6),
                        ),
                      ),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: challenge.completed
                        ? Colors.green.withOpacity(0.2)
                        : Theme.of(context).colorScheme.primary.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    challenge.completed ? 'Completed' : '+${challenge.xpReward} XP',
                    style: TextStyle(
                      color: challenge.completed
                          ? Colors.green
                          : Theme.of(context).colorScheme.primary,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            LinearProgressIndicator(
              value: progress,
              backgroundColor: Theme.of(context).colorScheme.primary.withOpacity(0.2),
              valueColor: AlwaysStoppedAnimation<Color>(
                challenge.completed ? Colors.green : Theme.of(context).colorScheme.primary,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              '${challenge.progress}/${challenge.target}',
              style: TextStyle(
                fontSize: 12,
                color: Theme.of(context).colorScheme.onSurface.withOpacity(0.6),
              ),
            ),
          ],
        ),
      ),
    ).animate()
        .fadeIn(duration: 600.ms)
        .slideX(begin: 0.1, end: 0);
  }

  Widget _buildActionCard(
      BuildContext context,
      String title,
      IconData icon,
      Color color,
      VoidCallback onTap,
      ) {
    return Container(
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: color.withOpacity(0.3),
          width: 2,
        ),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(16),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(icon, size: 40, color: color),
                const SizedBox(height: 8),
                Text(
                  title,
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: color,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    ).animate()
        .fadeIn(duration: 600.ms)
        .scale(begin: const Offset(0.8, 0.8), end: const Offset(1, 1));
  }
}

// Continue with remaining pages (SearchPage, PlaylistsPage, GameCenterPage, ProfilePage, etc.)
// Due to length constraints, I'll add the key functional pages...

// Playlists Page
class PlaylistsPage extends StatelessWidget {
  const PlaylistsPage({super.key});

  @override
  Widget build(BuildContext context) {
    final playlistProvider = context.watch<PlaylistProvider>();
    final userId = context.read<AuthProvider>().user?.uid;

    return Scaffold(
      appBar: AppBar(
        title: const Text('My Library'),
        actions: [
          IconButton(
            icon: const Icon(Icons.add),
            onPressed: () {
              _showCreatePlaylistDialog(context, userId!);
            },
          ),
        ],
      ),
      body: DefaultTabController(
        length: 2,
        child: Column(
          children: [
            const TabBar(
              tabs: [
                Tab(text: 'My Playlists'),
                Tab(text: 'Public Playlists'),
              ],
            ),
            Expanded(
              child: TabBarView(
                children: [
                  // My Playlists
                  _buildPlaylistGrid(playlistProvider.playlists, context, true),
                  // Public Playlists
                  _buildPlaylistGrid(playlistProvider.publicPlaylists, context, false),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPlaylistGrid(List<Playlist> playlists, BuildContext context, bool isOwned) {
    if (playlists.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.library_music_outlined,
              size: 100,
              color: Colors.grey[400],
            ),
            const SizedBox(height: 20),
            Text(
              isOwned ? 'No playlists yet' : 'No public playlists available',
              style: TextStyle(
                fontSize: 18,
                color: Colors.grey[400],
              ),
            ),
          ],
        ),
      );
    }

    return GridView.builder(
      padding: const EdgeInsets.all(16),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        crossAxisSpacing: 16,
        mainAxisSpacing: 16,
        childAspectRatio: 0.8,
      ),
      itemCount: playlists.length,
      itemBuilder: (context, index) {
        final playlist = playlists[index];
        return GestureDetector(
          onTap: () {
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (context) => PlaylistDetailPage(playlist: playlist),
              ),
            );
          },
          child: Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  Colors.primaries[index % Colors.primaries.length],
                  Colors.primaries[index % Colors.primaries.length].withOpacity(0.6),
                ],
              ),
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(
                  Icons.playlist_play,
                  size: 60,
                  color: Colors.white,
                ),
                const SizedBox(height: 16),
                Text(
                  playlist.name,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                  textAlign: TextAlign.center,
                ),
                Text(
                  '${playlist.songs.length} songs',
                  style: const TextStyle(
                    color: Colors.white70,
                    fontSize: 14,
                  ),
                ),
              ],
            ),
          ),
        ).animate()
            .fadeIn(delay: Duration(milliseconds: index * 100))
            .scale();
      },
    );
  }

  void _showCreatePlaylistDialog(BuildContext context, String userId) {
    final nameController = TextEditingController();
    final descriptionController = TextEditingController();

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Create Playlist'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: nameController,
              decoration: const InputDecoration(
                labelText: 'Playlist Name',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: descriptionController,
              decoration: const InputDecoration(
                labelText: 'Description',
                border: OutlineInputBorder(),
              ),
              maxLines: 3,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () {
              if (nameController.text.isNotEmpty) {
                context.read<PlaylistProvider>().createPlaylist(
                  nameController.text,
                  descriptionController.text,
                  userId,
                );
                Navigator.pop(context);
              }
            },
            child: const Text('Create'),
          ),
        ],
      ),
    );
  }
}

// Game Center Page
class GameCenterPage extends StatelessWidget {
  const GameCenterPage({super.key});

  @override
  Widget build(BuildContext context) {
    final gameProvider = context.watch<GameProvider>();
    final userStats = context.watch<UserStatsProvider>();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Game Center'),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Current Game Status
            if (gameProvider.currentGame != null)
              Card(
                color: Theme.of(context).colorScheme.primaryContainer,
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            'Active Game: ${gameProvider.currentGame.toString().split('.').last}',
                            style: const TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          Text(
                            'Score: ${gameProvider.gameScore}',
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton(
                          onPressed: () {
                            userStats.addXP(gameProvider.gameScore);
                            gameProvider.endGame();
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text('Game ended! +${gameProvider.gameScore} XP earned'),
                              ),
                            );
                          },
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.red,
                          ),
                          child: const Text('End Game'),
                        ),
                      ),
                    ],
                  ),
                ),
              ),

            // Game Modes
            Text(
              'Game Modes',
              style: GoogleFonts.poppins(
                fontSize: 24,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 16),
            _buildGameModeCard(
              context,
              'Quick Play',
              'Earn 10 XP per song played',
              Icons.play_circle_filled,
              Colors.purple,
              GameMode.quickPlay,
            ),
            _buildGameModeCard(
              context,
              'Challenge Mode',
              'Complete timed challenges for bonus XP',
              Icons.timer,
              Colors.orange,
              GameMode.challenge,
            ),
            _buildGameModeCard(
              context,
              'Marathon',
              'Listen continuously to earn increasing rewards',
              Icons.all_inclusive,
              Colors.blue,
              GameMode.marathon,
            ),
            _buildGameModeCard(
              context,
              'Battle Mode',
              'Compete with friends in real-time',
              Icons.sports_esports,
              Colors.red,
              GameMode.battle,
            ),

            const SizedBox(height: 30),

            // Leaderboard Preview
            Text(
              'Top Players',
              style: GoogleFonts.poppins(
                fontSize: 24,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 16),
            StreamBuilder<QuerySnapshot>(
              stream: FirebaseFirestore.instance
                  .collection('users')
                  .orderBy('xp', descending: true)
                  .limit(5)
                  .snapshots(),
              builder: (context, snapshot) {
                if (!snapshot.hasData) {
                  return const Center(child: CircularProgressIndicator());
                }

                final users = snapshot.data!.docs;
                return Column(
                  children: users.asMap().entries.map((entry) {
                    final index = entry.key;
                    final user = entry.value.data() as Map<String, dynamic>;
                    return ListTile(
                      leading: CircleAvatar(
                        backgroundImage: NetworkImage(
                          user['avatar'] ?? 'https://ui-avatars.com/api/?name=User',
                        ),
                      ),
                      title: Text(user['username'] ?? 'Unknown'),
                      subtitle: Text('Level ${user['level'] ?? 1}'),
                      trailing: Text(
                        '#${index + 1}',
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    );
                  }).toList(),
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildGameModeCard(
      BuildContext context,
      String title,
      String description,
      IconData icon,
      Color color,
      GameMode mode,
      ) {
    final gameProvider = context.read<GameProvider>();
    final userStats = context.read<UserStatsProvider>();

    return Card(
      margin: const EdgeInsets.only(bottom: 16),
      child: InkWell(
        onTap: () {
          if (gameProvider.currentGame == null) {
            gameProvider.startGame(mode);
            userStats.updateStreak();
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('$title started!'),
                backgroundColor: color,
              ),
            );
          }
        },
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: color.withOpacity(0.2),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(icon, color: color, size: 30),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    Text(
                      description,
                      style: TextStyle(
                        fontSize: 14,
                        color: Theme.of(context).colorScheme.onSurface.withOpacity(0.6),
                      ),
                    ),
                  ],
                ),
              ),
              const Icon(Icons.arrow_forward_ios),
            ],
          ),
        ),
      ),
    );
  }
}

// Other essential pages would continue here...
// Including: SearchPage, ProfilePage, FullPlayerPage, PlaylistDetailPage,
// DiscoverPage, FriendsPage, TopChartsPage, AchievementsPage, NotificationsPage, etc.