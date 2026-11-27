import 'package:THLRedLook/core/bridge/core_bridge.dart';
import 'package:THLRedLook/core/cast/haw_cast_models.dart';
import 'package:THLRedLook/core/cast/haw_cast_service.dart';
import 'package:THLRedLook/core/player/encrypted_playback.dart';
import 'package:THLRedLook/models/catalog/models.dart';

class HawCastPlayerHelper {
  static bool isRemotePlayablePlan(PlaybackPlan? plan) {
    if (plan == null || plan.local) return false;
    final uri = Uri.tryParse(plan.url);
    if (uri == null) return false;
    final scheme = uri.scheme.toLowerCase();
    if (scheme != 'http' && scheme != 'https') return false;
    final host = uri.host.toLowerCase();
    return host.isNotEmpty &&
        host != '127.0.0.1' &&
        host != 'localhost' &&
        host != '::1';
  }

  static Future<PlaybackPlan?> resolveCastablePlan({
    required Drama drama,
    required Episode episode,
    required PlaybackPlan? currentPlan,
    required EncryptedPlayback encryptedPlayback,
    required AppRepository repository,
    int requestedQuality = 0,
  }) async {
    if (currentPlan != null) {
      final original = encryptedPlayback.originalOnlinePlan(currentPlan);
      if (isRemotePlayablePlan(original)) {
        return original;
      }
      if (isRemotePlayablePlan(currentPlan)) {
        return currentPlan;
      }
    }

    try {
      final onlinePlan = await repository.resolveOnline(
        drama,
        episode,
        quality: requestedQuality,
      );
      if (isRemotePlayablePlan(onlinePlan)) {
        return onlinePlan;
      }
    } catch (_) {}

    return null;
  }

  static HawCastPlayRequest buildPlayRequest({
    required DramaDetail detail,
    required int episodeIndex,
    required PlaybackPlan plan,
    required double startPosition,
    String? sessionId,
  }) {
    final service = HawCastService.instance;
    final ep = detail.episodes[episodeIndex];
    return HawCastPlayRequest(
      sessionId: (sessionId != null && sessionId.isNotEmpty)
          ? sessionId
          : (service.activeSessionId.isNotEmpty
              ? service.activeSessionId
              : service.generateSessionId()),
      mediaId: '${detail.drama.cleanSourceId}_${ep.id}',
      title: '第 ${ep.number} 集',
      dramaTitle: detail.drama.title,
      url: plan.url,
      decryptionKey: plan.decryptionKey,
      headers: plan.headers,
      startPosition: startPosition > 0 ? startPosition : 0.0,
      episodeIndex: episodeIndex,
      totalEpisodes: detail.episodes.length,
    );
  }
}
