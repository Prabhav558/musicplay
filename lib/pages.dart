// Save this as lib/pages.dart and import it in main.dart

import 'package:flutter/material.dart';
import 'package:just_audio/just_audio.dart';
import 'package:provider/provider.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:audio_video_progress_bar/audio_video_progress_bar.dart';
import 'package:share_plus/share_plus.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'dart:math';

// Import your main.dart classes
import 'main.dart';

// Search Page with enhanced functionality
class SearchPage extends StatefulWidget {
  const SearchPage({super.key});

  @override
  State<SearchPage> createState() => _SearchPageState();
}

class _SearchPageState extends State<SearchPage> {
  final TextEditingController _searchController = TextEditingController();
  List<Song> _searchResults = [];
  List<String> _recentSearches = [];
  List<String> _genres = ['Pop', 'Rock', 'Jazz', 'Classical', 'Hip Hop', 'Electronic', 'Country', 'R&B'];
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _loadRecentSearches();
  }

  Future<void> _loadRecentSearches() async {
    // Load from shared preferences
    setState(() {
      _recentSearches = ['Taylor Swift', 'Ed Sheeran', 'Coldplay']; // Mock data
    });
  }

  Future<void> _searchSongs(String query) async {
    if (query.isEmpty) return;

    setState(() {
      _isLoading = true;
    });

    // Add to recent searches
    if (!_recentSearches.contains(query)) {
      _recentSearches.insert(0, query);
      if (_recentSearches.length > 10) {
        _recentSearches.removeLast();
      }
    }

    try {
      final response = await http.get(
        Uri.parse(
          'https://itunes.apple.com/search?term=${Uri.encodeComponent(query)}&media=music&limit=50',
        ),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final results = data['results'] as List;

        setState(() {
          _searchResults = results
              .where((track) => track['previewUrl'] != null)
              .map((track) => Song(
            id: track['trackId'].toString(),
            title: track['trackName'] ?? 'Unknown Title',
            artist: track['artistName'] ?? 'Unknown Artist',
            albumArt: track['artworkUrl100']?.replaceAll('100x100', '600x600'),
            previewUrl: track['previewUrl'],
            albumName: track['collectionName'],
            duration: track['trackTimeMillis'] != null
                ? Duration(milliseconds: track['trackTimeMillis'])
                : null,
          ))
              .toList();
        });

        // Update challenge progress
        context.read<GameProvider>().updateChallengeProgress(
          ChallengeType.playSongs,
          1,
        );
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error searching: $e')),
      );
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Search'),
      ),
      body: Column(
        children: [
          // Search Bar
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: TextField(
              controller: _searchController,
              decoration: InputDecoration(
                hintText: 'Search for songs, artists, albums...',
                prefixIcon: const Icon(Icons.search),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(30),
                ),
                filled: true,
                suffixIcon: _searchController.text.isNotEmpty
                    ? IconButton(
                  icon: const Icon(Icons.clear),
                  onPressed: () {
                    _searchController.clear();
                    setState(() {
                      _searchResults.clear();
                    });
                  },
                )
                    : null,
              ),
              onSubmitted: _searchSongs,
              onChanged: (value) {
                setState(() {});
              },
            ),
          ),

          // Content
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : _searchResults.isNotEmpty
                ? _buildSearchResults()
                : _buildSearchSuggestions(),
          ),
        ],
      ),
    );
  }

  Widget _buildSearchResults() {
    return ListView.builder(
      itemCount: _searchResults.length,
      itemBuilder: (context, index) {
        final song = _searchResults[index];
        return ListTile(
          leading: ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: song.albumArt != null
                ? CachedNetworkImage(
              imageUrl: song.albumArt!,
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
          title: Text(song.title),
          subtitle: Text(song.artist),
          trailing: PopupMenuButton<String>(
            onSelected: (value) {
              if (value == 'play') {
                context.read<MusicProvider>().playSong(song);
                context.read<UserStatsProvider>().addXP(10);
                context.read<UserStatsProvider>().incrementSongsPlayed();
              } else if (value == 'queue') {
                context.read<MusicProvider>().addToQueue(song);
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Added to queue')),
                );
              } else if (value == 'playlist') {
                _showAddToPlaylistDialog(context, song);
              }
            },
            itemBuilder: (context) => [
              const PopupMenuItem(value: 'play', child: Text('Play')),
              const PopupMenuItem(value: 'queue', child: Text('Add to Queue')),
              const PopupMenuItem(value: 'playlist', child: Text('Add to Playlist')),
            ],
          ),
          onTap: () {
            context.read<MusicProvider>().playSong(song);
            context.read<UserStatsProvider>().addXP(10);
            context.read<UserStatsProvider>().incrementSongsPlayed();
          },
        );
      },
    );
  }

  Widget _buildSearchSuggestions() {
    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Recent Searches
          if (_recentSearches.isNotEmpty) ...[
            Padding(
              padding: const EdgeInsets.all(16.0),
              child: Text(
                'Recent Searches',
                style: GoogleFonts.poppins(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            ...(_recentSearches.map((search) => ListTile(
              leading: const Icon(Icons.history),
              title: Text(search),
              trailing: IconButton(
                icon: const Icon(Icons.close),
                onPressed: () {
                  setState(() {
                    _recentSearches.remove(search);
                  });
                },
              ),
              onTap: () {
                _searchController.text = search;
                _searchSongs(search);
              },
            ))),
          ],

          // Browse by Genre
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: Text(
              'Browse by Genre',
              style: GoogleFonts.poppins(
                fontSize: 20,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16.0),
            child: Wrap(
              spacing: 8.0,
              runSpacing: 8.0,
              children: _genres.map((genre) => ActionChip(
                label: Text(genre),
                onPressed: () {
                  _searchController.text = genre;
                  _searchSongs(genre);
                },
                backgroundColor: Colors.primaries[_genres.indexOf(genre) % Colors.primaries.length].withOpacity(0.2),
              )).toList(),
            ),
          ),
        ],
      ),
    );
  }

  void _showAddToPlaylistDialog(BuildContext context, Song song) {
    final playlists = context.read<PlaylistProvider>().playlists;
    final userId = context.read<AuthProvider>().user?.uid;

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Add to Playlist'),
        content: SizedBox(
          width: double.maxFinite,
          child: ListView.builder(
            shrinkWrap: true,
            itemCount: playlists.length,
            itemBuilder: (context, index) {
              return ListTile(
                leading: const Icon(Icons.playlist_play),
                title: Text(playlists[index].name),
                subtitle: Text('${playlists[index].songs.length} songs'),
                onTap: () {
                  context.read<PlaylistProvider>().addSongToPlaylist(
                    playlists[index].id,
                    song,
                    userId!,
                  );
                  Navigator.pop(context);
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('Added to ${playlists[index].name}')),
                  );
                },
              );
            },
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }
}

// Full Player Page
class FullPlayerPage extends StatelessWidget {
  const FullPlayerPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer<MusicProvider>(
      builder: (context, musicProvider, child) {
        final song = musicProvider.currentSong;
        if (song == null) {
          Navigator.pop(context);
          return const SizedBox.shrink();
        }

        return Scaffold(
          body: Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  Theme.of(context).colorScheme.primary.withOpacity(0.8),
                  Theme.of(context).colorScheme.surface,
                ],
              ),
            ),
            child: SafeArea(
              child: Column(
                children: [
                  // App Bar
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      IconButton(
                        icon: const Icon(Icons.keyboard_arrow_down, size: 30),
                        onPressed: () => Navigator.pop(context),
                      ),
                      Text(
                        'Now Playing',
                        style: GoogleFonts.poppins(
                          fontSize: 18,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      PopupMenuButton<String>(
                        onSelected: (value) {
                          if (value == 'share') {
                            Share.share('Check out ${song.title} by ${song.artist}');
                          } else if (value == 'playlist') {
                            // Add to playlist
                          }
                        },
                        itemBuilder: (context) => [
                          const PopupMenuItem(value: 'share', child: Text('Share')),
                          const PopupMenuItem(value: 'playlist', child: Text('Add to Playlist')),
                        ],
                      ),
                    ],
                  ),

                  const Spacer(),

                  // Album Art
                  Container(
                    margin: const EdgeInsets.all(32),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(20),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.3),
                          blurRadius: 30,
                          offset: const Offset(0, 20),
                        ),
                      ],
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(20),
                      child: song.albumArt != null
                          ? CachedNetworkImage(
                        imageUrl: song.albumArt!,
                        width: 300,
                        height: 300,
                        fit: BoxFit.cover,
                      )
                          : Container(
                        width: 300,
                        height: 300,
                        color: Colors.grey[800],
                        child: const Icon(Icons.music_note, size: 100),
                      ),
                    ),
                  ).animate()
                      .scale(duration: 600.ms)
                      .fadeIn(),

                  const Spacer(),

                  // Song Info
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 32),
                    child: Column(
                      children: [
                        Text(
                          song.title,
                          style: GoogleFonts.poppins(
                            fontSize: 24,
                            fontWeight: FontWeight.bold,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 8),
                        Text(
                          song.artist,
                          style: TextStyle(
                            fontSize: 18,
                            color: Theme.of(context).colorScheme.onSurface.withOpacity(0.7),
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        if (song.albumName != null) ...[
                          const SizedBox(height: 4),
                          Text(
                            song.albumName!,
                            style: TextStyle(
                              fontSize: 14,
                              color: Theme.of(context).colorScheme.onSurface.withOpacity(0.5),
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ],
                    ),
                  ),

                  const SizedBox(height: 32),

                  // Progress Bar
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 32),
                    child: ProgressBar(
                      progress: musicProvider.position,
                      total: musicProvider.duration,
                      progressBarColor: Theme.of(context).colorScheme.primary,
                      baseBarColor: Theme.of(context).colorScheme.primary.withOpacity(0.3),
                      bufferedBarColor: Theme.of(context).colorScheme.primary.withOpacity(0.5),
                      thumbColor: Theme.of(context).colorScheme.primary,
                      barHeight: 4.0,
                      thumbRadius: 8.0,
                      onSeek: musicProvider.seekTo,
                      timeLabelTextStyle: TextStyle(
                        color: Theme.of(context).colorScheme.onSurface.withOpacity(0.7),
                      ),
                    ),
                  ),

                  const SizedBox(height: 32),

                  // Controls
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      IconButton(
                        icon: Icon(
                          musicProvider.shuffleMode ? Icons.shuffle : Icons.shuffle,
                          color: musicProvider.shuffleMode
                              ? Theme.of(context).colorScheme.primary
                              : null,
                        ),
                        onPressed: () => musicProvider.toggleShuffle(),
                      ),
                      IconButton(
                        icon: const Icon(Icons.skip_previous),
                        iconSize: 40,
                        onPressed: () => musicProvider.playPrevious(),
                      ),
                      Container(
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: Theme.of(context).colorScheme.primary,
                        ),
                        child: IconButton(
                          icon: Icon(
                            musicProvider.isPlaying ? Icons.pause : Icons.play_arrow,
                            color: Colors.white,
                          ),
                          iconSize: 50,
                          onPressed: () => musicProvider.playPause(),
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.skip_next),
                        iconSize: 40,
                        onPressed: () => musicProvider.playNext(),
                      ),
                      IconButton(
                        icon: Icon(
                          musicProvider.loopMode == LoopMode.off
                              ? Icons.repeat
                              : musicProvider.loopMode == LoopMode.one
                              ? Icons.repeat_one
                              : Icons.repeat,
                          color: musicProvider.loopMode != LoopMode.off
                              ? Theme.of(context).colorScheme.primary
                              : null,
                        ),
                        onPressed: () => musicProvider.toggleLoopMode(),
                      ),
                    ],
                  ),

                  const SizedBox(height: 32),

                  // Queue Info
                  if (musicProvider.queue.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 32),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            Icons.queue_music,
                            size: 20,
                            color: Theme.of(context).colorScheme.onSurface.withOpacity(0.5),
                          ),
                          const SizedBox(width: 8),
                          Text(
                            'Next: ${musicProvider.queue.first.title}',
                            style: TextStyle(
                              color: Theme.of(context).colorScheme.onSurface.withOpacity(0.5),
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ),
                    ),

                  const Spacer(),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

// Profile Page
class ProfilePage extends StatelessWidget {
  const ProfilePage({super.key});

  @override
  Widget build(BuildContext context) {
    final authProvider = context.watch<AuthProvider>();
    final userStats = context.watch<UserStatsProvider>();

    return Scaffold(
      body: CustomScrollView(
        slivers: [
          SliverAppBar(
            expandedHeight: 250,
            pinned: true,
            flexibleSpace: FlexibleSpaceBar(
              background: Container(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      Theme.of(context).colorScheme.primary.withOpacity(0.8),
                      Theme.of(context).colorScheme.secondary.withOpacity(0.6),
                    ],
                  ),
                ),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const SizedBox(height: 40),
                    Stack(
                      children: [
                        CircleAvatar(
                          radius: 60,
                          backgroundImage: NetworkImage(
                            authProvider.user?.photoURL ??
                                'https://ui-avatars.com/api/?name=${authProvider.user?.displayName ?? "User"}',
                          ),
                        ),
                        Positioned(
                          bottom: 0,
                          right: 0,
                          child: Container(
                            decoration: BoxDecoration(
                              color: Theme.of(context).colorScheme.primary,
                              shape: BoxShape.circle,
                            ),
                            child: IconButton(
                              icon: const Icon(Icons.edit, color: Colors.white, size: 20),
                              onPressed: () {
                                // Edit profile photo
                              },
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    Text(
                      authProvider.user?.displayName ?? 'Music Lover',
                      style: const TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    ),
                    Text(
                      authProvider.user?.email ?? '',
                      style: const TextStyle(
                        fontSize: 14,
                        color: Colors.white70,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            actions: [
              IconButton(
                icon: const Icon(Icons.settings),
                onPressed: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => const SettingsPage(),
                    ),
                  );
                },
              ),
            ],
          ),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Stats Overview
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Your Stats',
                            style: GoogleFonts.poppins(
                              fontSize: 20,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 16),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceAround,
                            children: [
                              _buildStatItem('Level', '${userStats.level}', Icons.star),
                              _buildStatItem('XP', '${userStats.xp}', Icons.bolt),
                              _buildStatItem('Streak', '${userStats.stats['streak'] ?? 0}', Icons.local_fire_department),
                            ],
                          ),
                          const SizedBox(height: 16),
                          LinearProgressIndicator(
                            value: (userStats.xp % 1000) / 1000,
                            minHeight: 8,
                            borderRadius: BorderRadius.circular(4),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            '${userStats.xp % 1000} / 1000 XP to Level ${userStats.level + 1}',
                            style: TextStyle(
                              color: Theme.of(context).colorScheme.onSurface.withOpacity(0.6),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),

                  const SizedBox(height: 20),

                  // Recent Achievements
                  if (userStats.achievements.isNotEmpty) ...[
                    Text(
                      'Recent Achievements',
                      style: GoogleFonts.poppins(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 12),
                    SizedBox(
                      height: 100,
                      child: ListView.builder(
                        scrollDirection: Axis.horizontal,
                        itemCount: userStats.achievements.take(5).length,
                        itemBuilder: (context, index) {
                          final achievement = userStats.achievements[index];
                          return Container(
                            width: 100,
                            margin: const EdgeInsets.only(right: 12),
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                begin: Alignment.topLeft,
                                end: Alignment.bottomRight,
                                colors: [
                                  Colors.primaries[index % Colors.primaries.length],
                                  Colors.primaries[index % Colors.primaries.length].withOpacity(0.6),
                                ],
                              ),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(achievement.icon, color: Colors.white, size: 30),
                                const SizedBox(height: 8),
                                Text(
                                  achievement.name,
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 12,
                                    fontWeight: FontWeight.bold,
                                  ),
                                  textAlign: TextAlign.center,
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ],
                            ),
                          );
                        },
                      ),
                    ),
                  ],

                  const SizedBox(height: 20),

                  // Menu Options
                  ListTile(
                    leading: const Icon(Icons.music_note),
                    title: const Text('Recently Played'),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) => const RecentlyPlayedPage(),
                        ),
                      );
                    },
                  ),
                  ListTile(
                    leading: const Icon(Icons.favorite),
                    title: const Text('Liked Songs'),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () {
                      // Navigate to liked songs
                    },
                  ),
                  ListTile(
                    leading: const Icon(Icons.download),
                    title: const Text('Downloads'),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () {
                      // Navigate to downloads
                    },
                  ),
                  ListTile(
                    leading: const Icon(Icons.history),
                    title: const Text('Listening History'),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () {
                      // Navigate to history
                    },
                  ),
                  const Divider(),
                  ListTile(
                    leading: const Icon(Icons.logout, color: Colors.red),
                    title: const Text('Sign Out', style: TextStyle(color: Colors.red)),
                    onTap: () async {
                      await authProvider.signOut();
                      if (context.mounted) {
                        Navigator.pushAndRemoveUntil(
                          context,
                          MaterialPageRoute(builder: (context) => const LandingPage()),
                              (route) => false,
                        );
                      }
                    },
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatItem(String label, String value, IconData icon) {
    return Column(
      children: [
        Icon(icon, size: 30),
        const SizedBox(height: 8),
        Text(
          value,
          style: const TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.bold,
          ),
        ),
        Text(
          label,
          style: TextStyle(
            fontSize: 14,
            color: Colors.grey[600],
          ),
        ),
      ],
    );
  }
}

// Additional Essential Pages

// Playlist Detail Page
class PlaylistDetailPage extends StatelessWidget {
  final Playlist playlist;

  const PlaylistDetailPage({super.key, required this.playlist});

  @override
  Widget build(BuildContext context) {
    final musicProvider = context.read<MusicProvider>();
    final userStats = context.read<UserStatsProvider>();

    return Scaffold(
      body: CustomScrollView(
        slivers: [
          SliverAppBar(
            expandedHeight: 200,
            pinned: true,
            flexibleSpace: FlexibleSpaceBar(
              title: Text(playlist.name),
              background: Container(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      Colors.primaries[playlist.name.length % Colors.primaries.length],
                      Colors.primaries[playlist.name.length % Colors.primaries.length].withOpacity(0.6),
                    ],
                  ),
                ),
                child: Center(
                  child: Icon(
                    Icons.playlist_play,
                    size: 80,
                    color: Colors.white.withOpacity(0.8),
                  ),
                ),
              ),
            ),
            actions: [
              if (playlist.createdBy == context.read<AuthProvider>().user?.uid)
                PopupMenuButton<String>(
                  onSelected: (value) {
                    if (value == 'edit') {
                      // Edit playlist
                    } else if (value == 'delete') {
                      context.read<PlaylistProvider>().deletePlaylist(
                        playlist.id,
                        context.read<AuthProvider>().user!.uid,
                      );
                      Navigator.pop(context);
                    } else if (value == 'share') {
                      Share.share('Check out my playlist: ${playlist.name}');
                    }
                  },
                  itemBuilder: (context) => [
                    const PopupMenuItem(value: 'edit', child: Text('Edit')),
                    const PopupMenuItem(value: 'share', child: Text('Share')),
                    const PopupMenuItem(value: 'delete', child: Text('Delete')),
                  ],
                ),
            ],
          ),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    playlist.description,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.onSurface.withOpacity(0.7),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '${playlist.songs.length} songs',
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.onSurface.withOpacity(0.5),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Expanded(
                        child: ElevatedButton.icon(
                          onPressed: () {
                            if (playlist.songs.isNotEmpty) {
                              // Play all songs
                              musicProvider.clearQueue();
                              for (var song in playlist.songs.skip(1)) {
                                musicProvider.addToQueue(song);
                              }
                              musicProvider.playSong(playlist.songs.first);
                              userStats.addXP(20);
                            }
                          },
                          icon: const Icon(Icons.play_arrow),
                          label: const Text('Play All'),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: () {
                            if (playlist.songs.isNotEmpty) {
                              // Shuffle play
                              final shuffled = List<Song>.from(playlist.songs)..shuffle();
                              musicProvider.clearQueue();
                              for (var song in shuffled.skip(1)) {
                                musicProvider.addToQueue(song);
                              }
                              musicProvider.playSong(shuffled.first);
                              userStats.addXP(20);
                            }
                          },
                          icon: const Icon(Icons.shuffle),
                          label: const Text('Shuffle'),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          SliverList(
            delegate: SliverChildBuilderDelegate(
                  (context, index) {
                final song = playlist.songs[index];
                return ListTile(
                  leading: ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: song.albumArt != null
                        ? CachedNetworkImage(
                      imageUrl: song.albumArt!,
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
                  title: Text(song.title),
                  subtitle: Text(song.artist),
                  trailing: PopupMenuButton<String>(
                    onSelected: (value) {
                      if (value == 'play') {
                        musicProvider.playSong(song);
                        userStats.addXP(10);
                      } else if (value == 'queue') {
                        musicProvider.addToQueue(song);
                      } else if (value == 'remove') {
                        // Remove from playlist
                      }
                    },
                    itemBuilder: (context) => [
                      const PopupMenuItem(value: 'play', child: Text('Play')),
                      const PopupMenuItem(value: 'queue', child: Text('Add to Queue')),
                      if (playlist.createdBy == context.read<AuthProvider>().user?.uid)
                        const PopupMenuItem(value: 'remove', child: Text('Remove')),
                    ],
                  ),
                  onTap: () {
                    musicProvider.playSong(song);
                    userStats.addXP(10);
                  },
                );
              },
              childCount: playlist.songs.length,
            ),
          ),
        ],
      ),
    );
  }
}

// Settings Page
class SettingsPage extends StatelessWidget {
  const SettingsPage({super.key});

  @override
  Widget build(BuildContext context) {
    final themeProvider = context.watch<ThemeProvider>();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Settings'),
      ),
      body: ListView(
        children: [
          // Account Settings
          ListTile(
            leading: const Icon(Icons.person),
            title: const Text('Account'),
            subtitle: const Text('Manage your account'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () {
              // Navigate to account settings
            },
          ),
          // Theme Settings
          SwitchListTile(
            secondary: const Icon(Icons.dark_mode),
            title: const Text('Dark Mode'),
            subtitle: Text(themeProvider.themeMode == ThemeMode.dark ? 'On' : 'Off'),
            value: themeProvider.themeMode == ThemeMode.dark,
            onChanged: (value) {
              themeProvider.toggleTheme();
            },
          ),
          // Notification Settings
          ListTile(
            leading: const Icon(Icons.notifications),
            title: const Text('Notifications'),
            subtitle: const Text('Manage notification preferences'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () {
              // Navigate to notification settings
            },
          ),
          // Privacy Settings
          ListTile(
            leading: const Icon(Icons.privacy_tip),
            title: const Text('Privacy'),
            subtitle: const Text('Control your privacy settings'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () {
              // Navigate to privacy settings
            },
          ),
          // Audio Quality
          ListTile(
            leading: const Icon(Icons.high_quality),
            title: const Text('Audio Quality'),
            subtitle: const Text('Streaming and download quality'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () {
              // Navigate to audio quality settings
            },
          ),
          const Divider(),
          // Help & Support
          ListTile(
            leading: const Icon(Icons.help),
            title: const Text('Help & Support'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () {
              // Navigate to help
            },
          ),
          // About
          ListTile(
            leading: const Icon(Icons.info),
            title: const Text('About'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () {
              showAboutDialog(
                context: context,
                applicationName: 'Music Stream Pro',
                applicationVersion: '1.0.0',
                applicationIcon: const Icon(Icons.music_note, size: 50),
                children: [
                  const Text('A gamified music streaming app with social features.'),
                ],
              );
            },
          ),
        ],
      ),
    );
  }
}

// Achievements Page
class AchievementsPage extends StatelessWidget {
  const AchievementsPage({super.key});

  @override
  Widget build(BuildContext context) {
    final userStats = context.watch<UserStatsProvider>();

    // All possible achievements
    final allAchievements = [
      Achievement(
        id: 'first_10_songs',
        name: 'Music Lover',
        description: 'Play 10 songs',
        icon: Icons.music_note,
        xpReward: 50,
      ),
      Achievement(
        id: '100_songs',
        name: 'Audiophile',
        description: 'Play 100 songs',
        icon: Icons.headphones,
        xpReward: 200,
      ),
      Achievement(
        id: 'level_5',
        name: 'Rising Star',
        description: 'Reach Level 5',
        icon: Icons.star,
        xpReward: 100,
      ),
      Achievement(
        id: 'week_streak',
        name: 'Dedicated Listener',
        description: 'Maintain a 7-day streak',
        icon: Icons.local_fire_department,
        xpReward: 150,
      ),
      Achievement(
        id: 'playlist_master',
        name: 'Playlist Master',
        description: 'Create 5 playlists',
        icon: Icons.playlist_add_check,
        xpReward: 100,
      ),
      Achievement(
        id: 'social_butterfly',
        name: 'Social Butterfly',
        description: 'Add 10 friends',
        icon: Icons.people,
        xpReward: 150,
      ),
    ];

    return Scaffold(
      appBar: AppBar(
        title: const Text('Achievements'),
      ),
      body: GridView.builder(
        padding: const EdgeInsets.all(16),
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 2,
          crossAxisSpacing: 16,
          mainAxisSpacing: 16,
          childAspectRatio: 0.9,
        ),
        itemCount: allAchievements.length,
        itemBuilder: (context, index) {
          final achievement = allAchievements[index];
          final isUnlocked = userStats.hasAchievement(achievement.id);

          return Container(
            decoration: BoxDecoration(
              gradient: isUnlocked
                  ? LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  Colors.primaries[index % Colors.primaries.length],
                  Colors.primaries[index % Colors.primaries.length].withOpacity(0.6),
                ],
              )
                  : null,
              color: isUnlocked ? null : Colors.grey[800],
              borderRadius: BorderRadius.circular(16),
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  achievement.icon,
                  size: 50,
                  color: isUnlocked ? Colors.white : Colors.grey[600],
                ),
                const SizedBox(height: 12),
                Text(
                  achievement.name,
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: isUnlocked ? Colors.white : Colors.grey[400],
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 4),
                Text(
                  achievement.description,
                  style: TextStyle(
                    fontSize: 12,
                    color: isUnlocked ? Colors.white70 : Colors.grey[500],
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                  decoration: BoxDecoration(
                    color: isUnlocked ? Colors.white.withOpacity(0.2) : Colors.grey[700],
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    isUnlocked ? 'Unlocked' : '+${achievement.xpReward} XP',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      color: isUnlocked ? Colors.white : Colors.grey[400],
                    ),
                  ),
                ),
              ],
            ),
          ).animate()
              .fadeIn(delay: Duration(milliseconds: index * 100))
              .scale();
        },
      ),
    );
  }
}

// Friends Page
class FriendsPage extends StatelessWidget {
  const FriendsPage({super.key});

  @override
  Widget build(BuildContext context) {
    final socialProvider = context.watch<SocialProvider>();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Friends'),
        actions: [
          IconButton(
            icon: const Icon(Icons.person_add),
            onPressed: () {
              // Add friend dialog
              _showAddFriendDialog(context);
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
                Tab(text: 'Friends'),
                Tab(text: 'Activity Feed'),
              ],
            ),
            Expanded(
              child: TabBarView(
                children: [
                  // Friends List
                  _buildFriendsList(context, socialProvider),
                  // Activity Feed
                  _buildActivityFeed(context, socialProvider),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFriendsList(BuildContext context, SocialProvider socialProvider) {
    if (socialProvider.friends.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.people_outline, size: 100, color: Colors.grey[400]),
            const SizedBox(height: 20),
            Text(
              'No friends yet',
              style: TextStyle(fontSize: 18, color: Colors.grey[400]),
            ),
            const SizedBox(height: 10),
            ElevatedButton.icon(
              onPressed: () => _showAddFriendDialog(context),
              icon: const Icon(Icons.person_add),
              label: const Text('Add Friends'),
            ),
          ],
        ),
      );
    }

    return ListView.builder(
      itemCount: socialProvider.friends.length,
      itemBuilder: (context, index) {
        // In real app, fetch friend details from Firestore
        return ListTile(
          leading: CircleAvatar(
            backgroundImage: NetworkImage(
              'https://ui-avatars.com/api/?name=Friend${index + 1}',
            ),
          ),
          title: Text('Friend ${index + 1}'),
          subtitle: const Text('Active now'),
          trailing: PopupMenuButton<String>(
            onSelected: (value) {
              if (value == 'remove') {
                socialProvider.removeFriend(
                  socialProvider.friends[index],
                  context.read<AuthProvider>().user!.uid,
                );
              }
            },
            itemBuilder: (context) => [
              const PopupMenuItem(value: 'view', child: Text('View Profile')),
              const PopupMenuItem(value: 'remove', child: Text('Remove Friend')),
            ],
          ),
        );
      },
    );
  }

  Widget _buildActivityFeed(BuildContext context, SocialProvider socialProvider) {
    if (socialProvider.feed.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.feed_outlined, size: 100, color: Colors.grey[400]),
            const SizedBox(height: 20),
            Text(
              'No activity yet',
              style: TextStyle(fontSize: 18, color: Colors.grey[400]),
            ),
          ],
        ),
      );
    }

    return ListView.builder(
      itemCount: socialProvider.feed.length,
      itemBuilder: (context, index) {
        final activity = socialProvider.feed[index];
        return Card(
          margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: ListTile(
            leading: CircleAvatar(
              backgroundImage: NetworkImage(
                'https://ui-avatars.com/api/?name=${activity.username}',
              ),
            ),
            title: Text(activity.username),
            subtitle: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(activity.content),
                const SizedBox(height: 4),
                Text(
                  _formatTime(activity.timestamp),
                  style: TextStyle(
                    fontSize: 12,
                    color: Theme.of(context).colorScheme.onSurface.withOpacity(0.5),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  String _formatTime(DateTime time) {
    final now = DateTime.now();
    final difference = now.difference(time);

    if (difference.inMinutes < 60) {
      return '${difference.inMinutes}m ago';
    } else if (difference.inHours < 24) {
      return '${difference.inHours}h ago';
    } else {
      return '${difference.inDays}d ago';
    }
  }

  void _showAddFriendDialog(BuildContext context) {
    final searchController = TextEditingController();

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Add Friend'),
        content: TextField(
          controller: searchController,
          decoration: const InputDecoration(
            labelText: 'Enter username or email',
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () {
              // Search and add friend
              Navigator.pop(context);
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Friend request sent!')),
              );
            },
            child: const Text('Send Request'),
          ),
        ],
      ),
    );
  }
}

// Other pages (DiscoverPage, TopChartsPage, NotificationsPage, RecentlyPlayedPage)
// would follow similar patterns with their specific functionality...

class DiscoverPage extends StatelessWidget {
  const DiscoverPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Discover')),
      body: const Center(child: Text('Discover new music')),
    );
  }
}

class TopChartsPage extends StatelessWidget {
  const TopChartsPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Top Charts')),
      body: const Center(child: Text('Top Charts')),
    );
  }
}

class NotificationsPage extends StatelessWidget {
  const NotificationsPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Notifications')),
      body: const Center(child: Text('No new notifications')),
    );
  }
}

class RecentlyPlayedPage extends StatelessWidget {
  const RecentlyPlayedPage({super.key});

  @override
  Widget build(BuildContext context) {
    final musicProvider = context.watch<MusicProvider>();

    return Scaffold(
      appBar: AppBar(title: const Text('Recently Played')),
      body: musicProvider.recentlyPlayed.isEmpty
          ? const Center(child: Text('No recently played songs'))
          : ListView.builder(
        itemCount: musicProvider.recentlyPlayed.length,
        itemBuilder: (context, index) {
          final song = musicProvider.recentlyPlayed[index];
          return ListTile(
            leading: song.albumArt != null
                ? CachedNetworkImage(
              imageUrl: song.albumArt!,
              width: 50,
              height: 50,
              fit: BoxFit.cover,
            )
                : const Icon(Icons.music_note),
            title: Text(song.title),
            subtitle: Text(song.artist),
            onTap: () {
              musicProvider.playSong(song);
              context.read<UserStatsProvider>().addXP(10);
            },
          );
        },
      ),
    );
  }
}