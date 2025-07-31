import 'package:flutter/material.dart';
import 'package:just_audio/just_audio.dart';
import 'package:file_picker/file_picker.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:audio_video_progress_bar/audio_video_progress_bar.dart';
import 'dart:io';
import 'dart:async';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Music Player',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple),
        useMaterial3: true,
      ),
      home: const MusicPlayerHome(),
    );
  }
}

class Song {
  final String title;
  final String path;
  final String? artist;
  final Duration? duration;

  Song({
    required this.title,
    required this.path,
    this.artist,
    this.duration,
  });
}

class MusicPlayerHome extends StatefulWidget {
  const MusicPlayerHome({super.key});

  @override
  State<MusicPlayerHome> createState() => _MusicPlayerHomeState();
}

class _MusicPlayerHomeState extends State<MusicPlayerHome> with TickerProviderStateMixin {
  final AudioPlayer _audioPlayer = AudioPlayer();
  List<Song> _songs = [];
  int? _currentSongIndex;
  bool _isPlaying = false;
  Duration _duration = Duration.zero;
  Duration _position = Duration.zero;
  StreamSubscription<Duration?>? _durationSubscription;
  StreamSubscription<Duration>? _positionSubscription;
  StreamSubscription<PlayerState>? _playerStateSubscription;
  late AnimationController _animationController;

  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(
      duration: const Duration(seconds: 10),
      vsync: this,
    );
    _setupAudioPlayer();
    _requestPermissions();
  }

  Future<void> _requestPermissions() async {
    if (Platform.isAndroid) {
      await Permission.storage.request();
    }
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

      if (state.processingState == ProcessingState.completed) {
        _playNext();
      }
    });
  }

  @override
  void dispose() {
    _audioPlayer.dispose();
    _durationSubscription?.cancel();
    _positionSubscription?.cancel();
    _playerStateSubscription?.cancel();
    _animationController.dispose();
    super.dispose();
  }

  Future<void> _pickMusic() async {
    FilePickerResult? result = await FilePicker.platform.pickFiles(
      type: FileType.audio,
      allowMultiple: true,
    );

    if (result != null) {
      setState(() {
        for (var file in result.files) {
          if (file.path != null) {
            _songs.add(Song(
              title: file.name.replaceAll('.mp3', '').replaceAll('.m4a', ''),
              path: file.path!,
            ));
          }
        }
      });
    }
  }

  Future<void> _playSong(int index) async {
    if (index < 0 || index >= _songs.length) return;

    setState(() {
      _currentSongIndex = index;
    });

    await _audioPlayer.setFilePath(_songs[index].path);
    await _audioPlayer.play();
  }

  Future<void> _playPause() async {
    if (_isPlaying) {
      await _audioPlayer.pause();
    } else {
      if (_currentSongIndex == null && _songs.isNotEmpty) {
        await _playSong(0);
      } else {
        await _audioPlayer.play();
      }
    }
  }

  Future<void> _playNext() async {
    if (_currentSongIndex != null && _songs.isNotEmpty) {
      int nextIndex = (_currentSongIndex! + 1) % _songs.length;
      await _playSong(nextIndex);
    }
  }

  Future<void> _playPrevious() async {
    if (_currentSongIndex != null && _songs.isNotEmpty) {
      int prevIndex = (_currentSongIndex! - 1 + _songs.length) % _songs.length;
      await _playSong(prevIndex);
    }
  }

  void _seekTo(Duration position) {
    _audioPlayer.seek(position);
  }

  String _formatDuration(Duration duration) {
    String twoDigits(int n) => n.toString().padLeft(2, '0');
    final minutes = twoDigits(duration.inMinutes.remainder(60));
    final seconds = twoDigits(duration.inSeconds.remainder(60));
    return '$minutes:$seconds';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey[900],
      appBar: AppBar(
        title: const Text(
          'Music Player',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
        ),
        backgroundColor: Colors.transparent,
        elevation: 0,
        actions: [
          IconButton(
            icon: const Icon(Icons.add, color: Colors.white),
            onPressed: _pickMusic,
          ),
        ],
      ),
      body: Column(
        children: [
          // Now Playing Section
          if (_currentSongIndex != null)
            Container(
              margin: const EdgeInsets.all(20),
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    Colors.deepPurple.shade400,
                    Colors.deepPurple.shade800,
                  ],
                ),
                borderRadius: BorderRadius.circular(20),
                boxShadow: [
                  BoxShadow(
                    color: Colors.deepPurple.withOpacity(0.3),
                    blurRadius: 20,
                    offset: const Offset(0, 10),
                  ),
                ],
              ),
              child: Column(
                children: [
                  // Album Art Placeholder with Animation
                  AnimatedBuilder(
                    animation: _animationController,
                    builder: (context, child) {
                      return Transform.rotate(
                        angle: _animationController.value * 2 * 3.14159,
                        child: Container(
                          width: 120,
                          height: 120,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            gradient: RadialGradient(
                              colors: [
                                Colors.white.withOpacity(0.3),
                                Colors.white.withOpacity(0.1),
                              ],
                            ),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withOpacity(0.3),
                                blurRadius: 10,
                                offset: const Offset(0, 5),
                              ),
                            ],
                          ),
                          child: const Icon(
                            Icons.music_note,
                            size: 60,
                            color: Colors.white,
                          ),
                        ),
                      );
                    },
                  ),
                  const SizedBox(height: 20),
                  // Song Title
                  Text(
                    _songs[_currentSongIndex!].title,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                    ),
                    textAlign: TextAlign.center,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 20),
                  // Progress Bar
                  ProgressBar(
                    progress: _position,
                    total: _duration,
                    progressBarColor: Colors.white,
                    baseBarColor: Colors.white.withOpacity(0.3),
                    bufferedBarColor: Colors.white.withOpacity(0.3),
                    thumbColor: Colors.white,
                    barHeight: 4.0,
                    thumbRadius: 6.0,
                    onSeek: _seekTo,
                    timeLabelTextStyle: const TextStyle(
                      color: Colors.white,
                      fontSize: 12,
                    ),
                  ),
                  const SizedBox(height: 20),
                  // Control Buttons
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      IconButton(
                        icon: const Icon(Icons.skip_previous, color: Colors.white),
                        iconSize: 40,
                        onPressed: _songs.isNotEmpty ? _playPrevious : null,
                      ),
                      Container(
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: Colors.white.withOpacity(0.2),
                        ),
                        child: IconButton(
                          icon: Icon(
                            _isPlaying ? Icons.pause : Icons.play_arrow,
                            color: Colors.white,
                          ),
                          iconSize: 50,
                          onPressed: _songs.isNotEmpty ? _playPause : null,
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.skip_next, color: Colors.white),
                        iconSize: 40,
                        onPressed: _songs.isNotEmpty ? _playNext : null,
                      ),
                    ],
                  ),
                ],
              ),
            ),

          // Playlist Section
          Expanded(
            child: _songs.isEmpty
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
                    'No songs added',
                    style: TextStyle(
                      color: Colors.grey[400],
                      fontSize: 18,
                    ),
                  ),
                  const SizedBox(height: 10),
                  ElevatedButton.icon(
                    onPressed: _pickMusic,
                    icon: const Icon(Icons.add),
                    label: const Text('Add Music'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.deepPurple,
                      foregroundColor: Colors.white,
                    ),
                  ),
                ],
              ),
            )
                : ListView.builder(
              itemCount: _songs.length,
              padding: const EdgeInsets.all(10),
              itemBuilder: (context, index) {
                final song = _songs[index];
                final isCurrentSong = _currentSongIndex == index;

                return Card(
                  color: isCurrentSong
                      ? Colors.deepPurple.shade700
                      : Colors.grey[800],
                  margin: const EdgeInsets.symmetric(
                    vertical: 5,
                    horizontal: 10,
                  ),
                  child: ListTile(
                    leading: Container(
                      width: 50,
                      height: 50,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: isCurrentSong
                            ? Colors.white.withOpacity(0.2)
                            : Colors.deepPurple.withOpacity(0.2),
                      ),
                      child: Icon(
                        Icons.music_note,
                        color: isCurrentSong
                            ? Colors.white
                            : Colors.deepPurple,
                      ),
                    ),
                    title: Text(
                      song.title,
                      style: TextStyle(
                        color: isCurrentSong
                            ? Colors.white
                            : Colors.grey[200],
                        fontWeight: isCurrentSong
                            ? FontWeight.bold
                            : FontWeight.normal,
                      ),
                    ),
                    subtitle: Text(
                      'Tap to play',
                      style: TextStyle(
                        color: isCurrentSong
                            ? Colors.white70
                            : Colors.grey[500],
                      ),
                    ),
                    trailing: isCurrentSong && _isPlaying
                        ? Icon(
                      Icons.equalizer,
                      color: Colors.white,
                    )
                        : null,
                    onTap: () => _playSong(index),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}