import '../state/session.dart';

enum GameAudioCue {
  explore,
  fight,
  rest,
  loot,
  fire,
  hit,
  miss,
  reload,
  pause,
  victory,
  defeat,
}

class GameAudioService {
  GameAudioService._();

  static final GameAudioService instance = GameAudioService._();

  Future<void> attachSession(Session session) async {}

  Future<void> ensureMusicPlaying() async {}

  Future<void> playCue(GameAudioCue cue) async {}

  Future<void> playActionCue(String actionName) async {}

  Future<void> playHitCue() async {}

  Future<void> playMissCue() async {}

  Future<void> playReloadCue() async {}

  Future<void> playPauseCue({required bool paused}) async {}

  Future<void> playRoundEndCue({required bool victory}) async {}

  Future<void> dispose() async {}
}
