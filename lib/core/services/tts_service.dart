import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:audio_session/audio_session.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:http/http.dart' as http;
import 'package:just_audio/just_audio.dart';
import 'package:path_provider/path_provider.dart';

/// Text-to-speech service with Kokoro TTS Gateway as primary engine
/// and platform TTS ([FlutterTts]) as offline fallback.
///
/// Works in both foreground and background — relies on the app's
/// foreground service to keep the process alive.
class TtsService {
  // ── Env-var resolution (--dart-define → .env) ─────────────────────────────

  static String get _kokoroUrl {
    const compiled = String.fromEnvironment('KOKORO_TTS_URL');
    if (compiled.isNotEmpty) return compiled;
    return dotenv.env['KOKORO_TTS_URL'] ?? '';
  }

  static String get _kokoroApiKey {
    const compiled = String.fromEnvironment('KOKORO_TTS_API_KEY');
    if (compiled.isNotEmpty) return compiled;
    return dotenv.env['KOKORO_TTS_API_KEY'] ?? '';
  }

  // ── Constants ─────────────────────────────────────────────────────────────

  static const _kokoroTimeout = Duration(seconds: 8);
  static const _maxKokoroFailures = 3;
  static const _kokoroBackoffDuration = Duration(minutes: 5);

  // ── State ─────────────────────────────────────────────────────────────────

  final http.Client _client;
  FlutterTts? _systemTts;
  AudioPlayer? _player;
  AudioSession? _audioSession;
  File? _lastWavFile;
  Timer? _duckingReleaseTimer;

  bool _initialized = false;

  /// Consecutive Kokoro failures — triggers circuit-breaker after
  /// [_maxKokoroFailures] in a row.
  int _kokoroFailures = 0;
  DateTime? _kokoroBackoffUntil;

  /// Called when the current utterance finishes (any engine).
  VoidCallback? onComplete;

  /// Whether Kokoro env vars are configured.
  bool get kokoroConfigured =>
      _kokoroUrl.isNotEmpty && _kokoroApiKey.isNotEmpty;

  /// Whether Kokoro should be attempted right now.
  bool get _shouldTryKokoro {
    if (!kokoroConfigured) return false;
    if (_kokoroBackoffUntil != null &&
        DateTime.now().isBefore(_kokoroBackoffUntil!)) {
      return false;
    }
    return true;
  }

  TtsService({http.Client? client}) : _client = client ?? http.Client();

  // ── Lifecycle ─────────────────────────────────────────────────────────────

  Future<void> initialize() async {
    if (_initialized) return;

    // System TTS (fallback — always available offline).
    _systemTts = FlutterTts();
    await _systemTts!.setLanguage('en-US');
    await _systemTts!.setSpeechRate(0.5);
    await _systemTts!.setVolume(0.9);
    await _systemTts!.setPitch(1.0);
    await _systemTts!
        .setIosAudioCategory(IosTextToSpeechAudioCategory.playback, [
          IosTextToSpeechAudioCategoryOptions.mixWithOthers,
          IosTextToSpeechAudioCategoryOptions.duckOthers,
        ]);
    _systemTts!.setCompletionHandler(_handleComplete);

    // Audio player for Kokoro WAV output.
    _player = AudioPlayer();
    _player!.playerStateStream.listen((state) {
      if (state.processingState == ProcessingState.completed) {
        _cleanupWavFile();
        _handleComplete();
      }
    });

    // Configure audio session for speech-over-music ducking.
    // On Android: requests AUDIOFOCUS_GAIN_TRANSIENT_MAY_DUCK so Spotify /
    // YouTube Music / podcasts lower volume instead of pausing.
    // On iOS: sets playback category with duckOthers so other audio dims.
    try {
      _audioSession = await AudioSession.instance;
      await _audioSession!.configure(
        AudioSessionConfiguration(
          avAudioSessionCategory: AVAudioSessionCategory.playback,
          avAudioSessionCategoryOptions:
              AVAudioSessionCategoryOptions.mixWithOthers |
              AVAudioSessionCategoryOptions.duckOthers,
          avAudioSessionMode: AVAudioSessionMode.spokenAudio,
          androidAudioAttributes: const AndroidAudioAttributes(
            contentType: AndroidAudioContentType.speech,
            usage: AndroidAudioUsage.assistant,
          ),
          androidAudioFocusGainType:
              AndroidAudioFocusGainType.gainTransientMayDuck,
        ),
      );
    } catch (e) {
      debugPrint('[TtsService] Audio session config failed: $e');
    }

    _initialized = true;
    debugPrint(
      '[TtsService] initialized (kokoro=${kokoroConfigured ? "on" : "off"})',
    );
  }

  /// Speak [text] using the best available engine.
  ///
  /// Ducks external audio (Spotify, podcasts …) first so the listener
  /// hears the music fade, then the coach's voice cleanly. Audio
  /// restores gracefully after the utterance ends.
  Future<void> speak(String text) async {
    if (!_initialized) return;

    // Duck external audio and let the listener perceive the fade.
    await _activateDucking();

    if (_shouldTryKokoro) {
      try {
        await _speakWithKokoro(text);
        return;
      } catch (e) {
        debugPrint('[TtsService] Kokoro failed, using system TTS: $e');
        _recordKokoroFailure();
      }
    }

    await _speakWithSystem(text);
  }

  Future<void> stop() async {
    _duckingReleaseTimer?.cancel();
    await _player?.stop();
    await _systemTts?.stop();
    _audioSession?.setActive(false);
    _cleanupWavFile();
  }

  void dispose() {
    _duckingReleaseTimer?.cancel();
    stop();
    _player?.dispose();
  }

  // ── Private ───────────────────────────────────────────────────────────────

  Future<void> _speakWithKokoro(String text) async {
    // Kokoro accepts max 2 000 chars.
    final safeText = text.length > 2000 ? text.substring(0, 2000) : text;

    final response = await _client
        .post(
          Uri.parse('$_kokoroUrl/tts'),
          headers: {
            'Content-Type': 'application/json',
            'X-API-Key': _kokoroApiKey,
          },
          body: jsonEncode({
            'text': safeText,
            'voice': 'af_heart',
            'speed': 1.0,
          }),
        )
        .timeout(_kokoroTimeout);

    if (response.statusCode != 200) {
      throw HttpException(
        'Kokoro returned ${response.statusCode}',
        uri: Uri.parse('$_kokoroUrl/tts'),
      );
    }

    final dir = await getTemporaryDirectory();
    final file = File('${dir.path}/kokoro_tts.wav');
    await file.writeAsBytes(response.bodyBytes);
    _lastWavFile = file;

    await _player!.setFilePath(file.path);
    await _player!.play();

    // Reset circuit breaker on success.
    _kokoroFailures = 0;
    _kokoroBackoffUntil = null;
  }

  Future<void> _speakWithSystem(String text) async {
    try {
      await _systemTts!.speak(text);
    } catch (e) {
      debugPrint('[TtsService] System TTS error: $e');
      _handleComplete();
    }
  }

  void _handleComplete() {
    _scheduleDuckingRelease();
    onComplete?.call();
  }

  void _recordKokoroFailure() {
    _kokoroFailures++;
    if (_kokoroFailures >= _maxKokoroFailures) {
      _kokoroBackoffUntil = DateTime.now().add(_kokoroBackoffDuration);
      debugPrint(
        '[TtsService] Kokoro circuit breaker open — '
        'backing off for ${_kokoroBackoffDuration.inMinutes} min',
      );
    }
  }

  // ── Audio ducking ─────────────────────────────────────────────────────────

  /// Duck external audio and pause briefly so the listener perceives
  /// the music fading before the coach starts speaking.
  Future<void> _activateDucking() async {
    _duckingReleaseTimer?.cancel();
    try {
      await _audioSession?.setActive(true);
      // Settling breath — the music dims, a beat of silence, then voice.
      await Future.delayed(const Duration(milliseconds: 350));
    } catch (e) {
      debugPrint('[TtsService] Ducking activation failed: $e');
    }
  }

  /// Release ducking after a grace period so music fades back naturally
  /// instead of snapping back the instant speech ends.
  void _scheduleDuckingRelease() {
    _duckingReleaseTimer?.cancel();
    _duckingReleaseTimer = Timer(const Duration(milliseconds: 500), () {
      _audioSession?.setActive(false);
    });
  }

  void _cleanupWavFile() {
    _lastWavFile?.delete().ignore();
    _lastWavFile = null;
  }
}
