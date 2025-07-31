import 'package:flutter/material.dart';
import 'package:just_audio/just_audio.dart';
import 'package:audio_video_progress_bar/audio_video_progress_bar.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:share_plus/share_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'dart:async';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Music Streaming',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: Colors.deepPurple,
          brightness: Brightness.dark,
        ),
        useMaterial3: true,
      ),
      home: const MusicStreamingHome(),
    );
  }
}

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

  Map<String, dynamic> toJson() => {
    'id': id,
    'title': title,
    'artist': artist,
    'albumArt': albumArt,
    'previewUrl': previewUrl,
    'albumName': albumName,
    'duration': duration?.inSeconds,
  };

  factory Song.fromJson(Map<String, dynamic> json) => Song(
    id: json['id'],
    title: json['title'],
    artist: json['artist'],
    albumArt: json['albumArt'],
    previewUrl: json['previewUrl'],
    albumName: json['albumName'],
    duration: json['duration'] != null
        ? Duration(seconds: json['duration'])
        : null,
  );
}

class Playlist {
  final String id;
  final String name;
  final List<Song> songs;
  final DateTime createdAt;

  Playlist({
    required this.id,
    required this.name,
    required this.songs,
    required this.createdAt,
  });

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'songs': songs.map((s) => s.toJson()).toList(),
    'createdAt': createdAt.toIso8601String(),
  };

  factory Playlist.fromJson(Map<String, dynamic> json) => Playlist(
    id: json['id'],
    name: json['name'],
    songs: (json['songs'] as List).map((s) => Song.fromJson(s)).toList(),
    createdAt: DateTime.parse(json['createdAt']),
  );
}

class MusicStreamingHome extends StatefulWidget {
  const MusicStreamingHome({super.key});

  @override
  State<MusicStreamingHome> createState() => _MusicStreamingHomeState();
}

class _MusicStreamingHomeState extends State<MusicStreamingHome>
    with TickerProviderStateMixin {
  final AudioPlayer _audioPlayer = AudioPlayer();
  final TextEditingController _searchController = TextEditingController();

  List<Song> _searchResults = [];
  List<Song> _recentlyPlayed = [];
  List<Playlist> _playlists = [];
  Song? _currentSong;
  bool _isPlaying = false;
  bool _isLoading = false;
  Duration _duration = Duration.zero;
  Duration _position = Duration.zero;

  late AnimationController _animationController;
  late TabController _tabController;
  StreamSubscription<Duration?>? _durationSubscription;
  StreamSubscription<Duration>? _positionSubscription;
  StreamSubscription<PlayerState>? _playerStateSubscription;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _animationController = AnimationController(
      duration: const Duration(seconds: 10),
      vsync: this,
    );
    _setupAudioPlayer();
    _loadData();
  }

  Future<void> _loadData() async {
    final prefs = await SharedPreferences.getInstance();

    // Load recently played
    final recentlyPlayedJson = prefs.getStringList('recentlyPlayed') ?? [];
    setState(() {
      _recentlyPlayed = recentlyPlayedJson
          .map((json) => Song.fromJson(jsonDecode(json)))
          .toList();
    });

    // Load playlists
    final playlistsJson = prefs.getStringList('playlists') ?? [];
    setState(() {
      _playlists = playlistsJson
          .map((json) => Playlist.fromJson(jsonDecode(json)))
          .toList();
    });
  }

  Future<void> _saveData() async {
    final prefs = await SharedPreferences.getInstance();

    // Save recently played
    await prefs.setStringList(
      'recentlyPlayed',
      _recentlyPlayed.map((s) => jsonEncode(s.toJson())).toList(),
    );

    // Save playlists
    await prefs.setStringList(
      'playlists',
      _playlists.map((p) => jsonEncode(p.toJson())).toList(),
    );
  }

  void _setupAudioPlayer() {
    _durationSubscription = _audioPlayer.durationStream.listen((duration) {
      setState(() {
        _duration = duration ?? Duration.zero;
      });
    });

    _positionSubscription = _audioPlayer.positionStream.listen((position) {
      setState(() {
        _position = position;
      });
    });

    _playerStateSubscription = _audioPlayer.playerStateStream.listen((state) {
      setState(() {
        _isPlaying = state.playing;
      });
      if (state.playing) {
        _animationController.repeat();
      } else {
        _animationController.stop();
      }
    });
  }

  Future<void> _searchSongs(String query) async {
    if (query.isEmpty) return;

    setState(() {
      _isLoading = true;
    });

    try {
      // Using iTunes Search API for free music previews
      final response = await http.get(
        Uri.parse(
            'https://itunes.apple.com/search?term=${Uri.encodeComponent(query)}&media=music&limit=50'
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

  Future<void> _playSong(Song song) async {
    setState(() {
      _currentSong = song;
    });

    // Add to recently played
    _recentlyPlayed.removeWhere((s) => s.id == song.id);
    _recentlyPlayed.insert(0, song);
    if (_recentlyPlayed.length > 20) {
      _recentlyPlayed = _recentlyPlayed.sublist(0, 20);
    }
    _saveData();

    try {
      await _audioPlayer.setUrl(song.previewUrl);
      await _audioPlayer.play();
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error playing song: $e')),
      );
    }
  }

  Future<void> _playPause() async {
    if (_isPlaying) {
      await _audioPlayer.pause();
    } else {
      await _audioPlayer.play();
    }
  }

  void _seekTo(Duration position) {
    _audioPlayer.seek(position);
  }

  void _shareSong(Song song) {
    Share.share(
      'Check out "${song.title}" by ${song.artist} 🎵',
      subject: 'Listen to this song!',
    );
  }

  void _showCreatePlaylistDialog() {
    final nameController = TextEditingController();

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Create Playlist'),
        content: TextField(
          controller: nameController,
          decoration: const InputDecoration(
            labelText: 'Playlist Name',
            border: OutlineInputBorder(),
          ),
          autofocus: true,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () {
              if (nameController.text.isNotEmpty) {
                setState(() {
                  _playlists.add(Playlist(
                    id: DateTime.now().millisecondsSinceEpoch.toString(),
                    name: nameController.text,
                    songs: [],
                    createdAt: DateTime.now(),
                  ));
                });
                _saveData();
                Navigator.pop(context);
              }
            },
            child: const Text('Create'),
          ),
        ],
      ),
    );
  }

  void _showAddToPlaylistDialog(Song song) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Add to Playlist'),
        content: SizedBox(
          width: double.maxFinite,
          child: ListView.builder(
            shrinkWrap: true,
            itemCount: _playlists.length,
            itemBuilder: (context, index) {
              final playlist = _playlists[index];
              return ListTile(
                title: Text(playlist.name),
                subtitle: Text('${playlist.songs.length} songs'),
                onTap: () {
                  if (!playlist.songs.any((s) => s.id == song.id)) {
                    setState(() {
                      playlist.songs.add(song);
                    });
                    _saveData();
                    Navigator.pop(context);
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text('Added to ${playlist.name}'),
                      ),
                    );
                  } else {
                    Navigator.pop(context);
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('Song already in playlist'),
                      ),
                    );
                  }
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

  Widget _buildSongTile(Song song, {VoidCallback? onRemove}) {
    final isCurrentSong = _currentSong?.id == song.id;

    return Card(
      color: isCurrentSong
          ? Theme.of(context).colorScheme.primaryContainer
          : Theme.of(context).colorScheme.surface,
      margin: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      child: ListTile(
        leading: ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: song.albumArt != null
              ? CachedNetworkImage(
            imageUrl: song.albumArt!,
            width: 50,
            height: 50,
            fit: BoxFit.cover,
            placeholder: (context, url) => Container(
              width: 50,
              height: 50,
              color: Colors.grey[800],
              child: const Icon(Icons.music_note),
            ),
            errorWidget: (context, url, error) => Container(
              width: 50,
              height: 50,
              color: Colors.grey[800],
              child: const Icon(Icons.music_note),
            ),
          )
              : Container(
            width: 50,
            height: 50,
            color: Colors.grey[800],
            child: const Icon(Icons.music_note),
          ),
        ),
        title: Text(
          song.title,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            fontWeight: isCurrentSong ? FontWeight.bold : FontWeight.normal,
          ),
        ),
        subtitle: Text(
          '${song.artist}${song.albumName != null ? ' • ${song.albumName}' : ''}',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (isCurrentSong && _isPlaying)
              Icon(
                Icons.equalizer,
                color: Theme.of(context).colorScheme.primary,
              ),
            PopupMenuButton<String>(
              icon: const Icon(Icons.more_vert),
              onSelected: (value) {
                switch (value) {
                  case 'play':
                    _playSong(song);
                    break;
                  case 'addToPlaylist':
                    _showAddToPlaylistDialog(song);
                    break;
                  case 'share':
                    _shareSong(song);
                    break;
                  case 'remove':
                    onRemove?.call();
                    break;
                }
              },
              itemBuilder: (context) => [
                const PopupMenuItem(
                  value: 'play',
                  child: ListTile(
                    leading: Icon(Icons.play_arrow),
                    title: Text('Play'),
                    contentPadding: EdgeInsets.zero,
                  ),
                ),
                const PopupMenuItem(
                  value: 'addToPlaylist',
                  child: ListTile(
                    leading: Icon(Icons.playlist_add),
                    title: Text('Add to Playlist'),
                    contentPadding: EdgeInsets.zero,
                  ),
                ),
                const PopupMenuItem(
                  value: 'share',
                  child: ListTile(
                    leading: Icon(Icons.share),
                    title: Text('Share'),
                    contentPadding: EdgeInsets.zero,
                  ),
                ),
                if (onRemove != null)
                  const PopupMenuItem(
                    value: 'remove',
                    child: ListTile(
                      leading: Icon(Icons.remove_circle_outline),
                      title: Text('Remove'),
                      contentPadding: EdgeInsets.zero,
                    ),
                  ),
              ],
            ),
          ],
        ),
        onTap: () => _playSong(song),
      ),
    );
  }

  Widget _buildSearchTab() {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(16.0),
          child: TextField(
            controller: _searchController,
            decoration: InputDecoration(
              hintText: 'Search for songs, artists...',
              prefixIcon: const Icon(Icons.search),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(30),
              ),
              filled: true,
              suffixIcon: IconButton(
                icon: const Icon(Icons.clear),
                onPressed: () {
                  _searchController.clear();
                  setState(() {
                    _searchResults.clear();
                  });
                },
              ),
            ),
            onSubmitted: _searchSongs,
          ),
        ),
        if (_isLoading)
          const Expanded(
            child: Center(
              child: CircularProgressIndicator(),
            ),
          )
        else if (_searchResults.isEmpty)
          Expanded(
            child: Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.search_off,
                    size: 100,
                    color: Colors.grey[600],
                  ),
                  const SizedBox(height: 20),
                  Text(
                    'Search for your favorite songs',
                    style: TextStyle(
                      color: Colors.grey[400],
                      fontSize: 18,
                    ),
                  ),
                ],
              ),
            ),
          )
        else
          Expanded(
            child: ListView.builder(
              itemCount: _searchResults.length,
              itemBuilder: (context, index) => _buildSongTile(_searchResults[index]),
            ),
          ),
      ],
    );
  }

  Widget _buildHomeTab() {
    return _recentlyPlayed.isEmpty
        ? Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.history,
            size: 100,
            color: Colors.grey[600],
          ),
          const SizedBox(height: 20),
          Text(
            'No recently played songs',
            style: TextStyle(
              color: Colors.grey[400],
              fontSize: 18,
            ),
          ),
          const SizedBox(height: 10),
          ElevatedButton.icon(
            onPressed: () => _tabController.animateTo(1),
            icon: const Icon(Icons.search),
            label: const Text('Search Music'),
          ),
        ],
      ),
    )
        : Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Padding(
          padding: EdgeInsets.all(16.0),
          child: Text(
            'Recently Played',
            style: TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
        Expanded(
          child: ListView.builder(
            itemCount: _recentlyPlayed.length,
            itemBuilder: (context, index) => _buildSongTile(
              _recentlyPlayed[index],
              onRemove: () {
                setState(() {
                  _recentlyPlayed.removeAt(index);
                });
                _saveData();
              },
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildPlaylistsTab() {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(16.0),
          child: ElevatedButton.icon(
            onPressed: _showCreatePlaylistDialog,
            icon: const Icon(Icons.add),
            label: const Text('Create Playlist'),
            style: ElevatedButton.styleFrom(
              minimumSize: const Size(double.infinity, 50),
            ),
          ),
        ),
        if (_playlists.isEmpty)
          Expanded(
            child: Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.playlist_play,
                    size: 100,
                    color: Colors.grey[600],
                  ),
                  const SizedBox(height: 20),
                  Text(
                    'No playlists yet',
                    style: TextStyle(
                      color: Colors.grey[400],
                      fontSize: 18,
                    ),
                  ),
                ],
              ),
            ),
          )
        else
          Expanded(
            child: ListView.builder(
              itemCount: _playlists.length,
              itemBuilder: (context, index) {
                final playlist = _playlists[index];
                return Card(
                  margin: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 8,
                  ),
                  child: ListTile(
                    leading: Container(
                      width: 50,
                      height: 50,
                      decoration: BoxDecoration(
                        color: Theme.of(context).colorScheme.primaryContainer,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Icon(Icons.playlist_play),
                    ),
                    title: Text(
                      playlist.name,
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                    subtitle: Text('${playlist.songs.length} songs'),
                    trailing: IconButton(
                      icon: const Icon(Icons.delete_outline),
                      onPressed: () {
                        showDialog(
                          context: context,
                          builder: (context) => AlertDialog(
                            title: const Text('Delete Playlist'),
                            content: Text(
                              'Are you sure you want to delete "${playlist.name}"?',
                            ),
                            actions: [
                              TextButton(
                                onPressed: () => Navigator.pop(context),
                                child: const Text('Cancel'),
                              ),
                              ElevatedButton(
                                onPressed: () {
                                  setState(() {
                                    _playlists.removeAt(index);
                                  });
                                  _saveData();
                                  Navigator.pop(context);
                                },
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: Colors.red,
                                ),
                                child: const Text('Delete'),
                              ),
                            ],
                          ),
                        );
                      },
                    ),
                    onTap: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) => PlaylistDetailPage(
                            playlist: playlist,
                            onPlaySong: _playSong,
                            onUpdate: () => _saveData(),
                          ),
                        ),
                      );
                    },
                  ),
                );
              },
            ),
          ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            // Mini Player
            if (_currentSong != null)
              Container(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      Theme.of(context).colorScheme.primaryContainer,
                      Theme.of(context).colorScheme.secondaryContainer,
                    ],
                  ),
                ),
                child: Column(
                  children: [
                    ListTile(
                      leading: AnimatedBuilder(
                        animation: _animationController,
                        builder: (context, child) {
                          return Transform.rotate(
                            angle: _animationController.value * 2 * 3.14159,
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(8),
                              child: _currentSong!.albumArt != null
                                  ? CachedNetworkImage(
                                imageUrl: _currentSong!.albumArt!,
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
                          );
                        },
                      ),
                      title: Text(
                        _currentSong!.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      subtitle: Text(
                        _currentSong!.artist,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          IconButton(
                            icon: Icon(
                              _isPlaying ? Icons.pause : Icons.play_arrow,
                            ),
                            onPressed: _playPause,
                          ),
                          IconButton(
                            icon: const Icon(Icons.share),
                            onPressed: () => _shareSong(_currentSong!),
                          ),
                        ],
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16.0),
                      child: ProgressBar(
                        progress: _position,
                        total: _duration,
                        progressBarColor: Theme.of(context).colorScheme.primary,
                        baseBarColor: Theme.of(context).colorScheme.primary.withOpacity(0.3),
                        bufferedBarColor: Theme.of(context).colorScheme.primary.withOpacity(0.3),
                        thumbColor: Theme.of(context).colorScheme.primary,
                        barHeight: 4.0,
                        thumbRadius: 6.0,
                        onSeek: _seekTo,
                        timeLabelTextStyle: const TextStyle(fontSize: 12),
                      ),
                    ),
                    const SizedBox(height: 8),
                  ],
                ),
              ),

            // Tab Bar
            TabBar(
              controller: _tabController,
              tabs: const [
                Tab(icon: Icon(Icons.home), text: 'Home'),
                Tab(icon: Icon(Icons.search), text: 'Search'),
                Tab(icon: Icon(Icons.playlist_play), text: 'Playlists'),
              ],
            ),

            // Tab Views
            Expanded(
              child: TabBarView(
                controller: _tabController,
                children: [
                  _buildHomeTab(),
                  _buildSearchTab(),
                  _buildPlaylistsTab(),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  void dispose() {
    _audioPlayer.dispose();
    _searchController.dispose();
    _tabController.dispose();
    _animationController.dispose();
    _durationSubscription?.cancel();
    _positionSubscription?.cancel();
    _playerStateSubscription?.cancel();
    super.dispose();
  }
}

class PlaylistDetailPage extends StatefulWidget {
  final Playlist playlist;
  final Function(Song) onPlaySong;
  final VoidCallback onUpdate;

  const PlaylistDetailPage({
    super.key,
    required this.playlist,
    required this.onPlaySong,
    required this.onUpdate,
  });

  @override
  State<PlaylistDetailPage> createState() => _PlaylistDetailPageState();
}

class _PlaylistDetailPageState extends State<PlaylistDetailPage> {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.playlist.name),
        actions: [
          IconButton(
            icon: const Icon(Icons.share),
            onPressed: () {
              final songs = widget.playlist.songs
                  .map((s) => '• ${s.title} by ${s.artist}')
                  .join('\n');
              Share.share(
                'Check out my playlist "${widget.playlist.name}":\n\n$songs',
                subject: 'My Playlist: ${widget.playlist.name}',
              );
            },
          ),
        ],
      ),
      body: widget.playlist.songs.isEmpty
          ? Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.music_off,
              size: 100,
              color: Colors.grey[600],
            ),
            const SizedBox(height: 20),
            Text(
              'No songs in this playlist',
              style: TextStyle(
                color: Colors.grey[400],
                fontSize: 18,
              ),
            ),
          ],
        ),
      )
          : ListView.builder(
        itemCount: widget.playlist.songs.length,
        itemBuilder: (context, index) {
          final song = widget.playlist.songs[index];
          return Dismissible(
            key: Key(song.id),
            direction: DismissDirection.endToStart,
            background: Container(
              alignment: Alignment.centerRight,
              padding: const EdgeInsets.only(right: 20),
              color: Colors.red,
              child: const Icon(Icons.delete, color: Colors.white),
            ),
            onDismissed: (direction) {
              setState(() {
                widget.playlist.songs.removeAt(index);
              });
              widget.onUpdate();
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text('${song.title} removed'),
                  action: SnackBarAction(
                    label: 'Undo',
                    onPressed: () {
                      setState(() {
                        widget.playlist.songs.insert(index, song);
                      });
                      widget.onUpdate();
                    },
                  ),
                ),
              );
            },
            child: ListTile(
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
              onTap: () => widget.onPlaySong(song),
            ),
          );
        },
      ),
    );
  }
}