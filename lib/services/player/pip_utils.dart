import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:kazumi/services/logging/logger.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:window_manager/window_manager.dart';
import 'package:kazumi/utils/device.dart';

class PipUtils {
  static bool androidPIPInited = false;

  // 比例约分
  static Size getPIPAspectSize({required int width, required int height}) {
    if (width <= 0 || height <= 0) {
      return const Size(16, 9);
    }
    final int divisor = width.gcd(height);
    return Size(width / divisor, height / divisor);
  }

  static Future<bool> isAndroidPIPSupported() async {
    if (!Platform.isAndroid) {
      return false;
    }
    const pipChannel = MethodChannel('com.predidit.kazumi/pip');
    try {
      final bool? supported =
          await pipChannel.invokeMethod('isPictureInPictureSupported');
      return supported ?? false;
    } on PlatformException catch (e) {
      KazumiLogger().e("Failed to check Android PIP support: '${e.message}'.");
      return false;
    }
  }

  static Future<bool> enterAndroidPIPWindow(
      {int width = 16, int height = 9}) async {
    if (!Platform.isAndroid) {
      return false;
    }
    final Size aspectSize = getPIPAspectSize(width: width, height: height);
    const pipChannel = MethodChannel('com.predidit.kazumi/pip');
    try {
      final bool? entered =
          await pipChannel.invokeMethod('enterPictureInPictureMode', {
        'width': aspectSize.width.toInt(),
        'height': aspectSize.height.toInt(),
      });
      return entered ?? false;
    } on PlatformException catch (e) {
      KazumiLogger().e("Failed to enter Android PIP mode: '${e.message}'.");
      return false;
    }
  }

  static Future<void> updateAndroidPIPActions({
    required bool playing,
    required bool danmakuEnabled,
    int width = 16,
    int height = 9,
    Rect? sourceRect,
  }) async {
    if (!Platform.isAndroid) {
      return;
    }
    final Size aspectSize = getPIPAspectSize(width: width, height: height);
    const pipChannel = MethodChannel('com.predidit.kazumi/pip');
    try {
      await pipChannel.invokeMethod('updatePictureInPictureActions', {
        'playing': playing,
        'danmakuEnabled': danmakuEnabled,
        'width': aspectSize.width.toInt(),
        'height': aspectSize.height.toInt(),
        if (sourceRect != null) ...{
          'sourceLeft': sourceRect.left.round(),
          'sourceTop': sourceRect.top.round(),
          'sourceRight': sourceRect.right.round(),
          'sourceBottom': sourceRect.bottom.round(),
        },
      });
    } on PlatformException catch (e) {
      KazumiLogger().e("Failed to update Android PIP actions: '${e.message}'.");
    }
  }

  static Future<void> setAndroidAutoEnterPIPEnabled(bool enabled) async {
    if (!Platform.isAndroid) {
      return;
    }
    const pipChannel = MethodChannel('com.predidit.kazumi/pip');
    try {
      await pipChannel.invokeMethod('setAndroidAutoEnterPIPEnabled', {
        'enabled': enabled,
      });
    } on PlatformException catch (e) {
      KazumiLogger().e(
          "Failed to set Android auto-enter PIP enabled state: '${e.message}'.");
    }
  }

  static Future<void> setAndroidPIPInPlayerPage(bool inPlayerPage) async {
    if (!Platform.isAndroid) {
      return;
    }
    const pipChannel = MethodChannel('com.predidit.kazumi/pip');
    try {
      await pipChannel.invokeMethod('setAndroidPIPInPlayerPage', {
        'inPlayerPage': inPlayerPage,
      });
    } on PlatformException catch (e) {
      KazumiLogger().e("Failed to set Android PIP page state: '${e.message}'.");
    }
  }

  // MARK: - iOS 系统级画中画
  //
  // iOS 上走的是系统画中画：`PictureInPicture` 通过 media_kit_video 的方法通道
  // 驱动原生侧 `AVPictureInPictureController`，小窗由系统绘制、可悬浮在其它 App
  // 之上，与应用内画面互不干扰。

  /// 当前设备 / 系统是否支持系统级画中画（iOS 15+）。
  static Future<bool> isIOSPIPSupported() async {
    if (!Platform.isIOS) {
      return false;
    }
    return PictureInPicture.isSupported();
  }

  /// 画中画事件流：`start` / `stop` / `restore`。
  static Stream<String> get iosPipEvents => PictureInPicture.events;

  /// 画中画错误流，内容为可直接展示给用户的失败原因。
  static Stream<String> get iosPipErrors => PictureInPicture.errors;

  static Future<void> enterIOSPIPWindow(VideoController controller) async {
    if (!Platform.isIOS) {
      return;
    }
    await controller.setPictureInPicture(true);
  }

  static Future<void> exitIOSPIPWindow(VideoController controller) async {
    if (!Platform.isIOS) {
      return;
    }
    await controller.setPictureInPicture(false);
  }

  /// 「武装」自动画中画：不立即弹出窗口，而是在用户划回主屏幕时由系统自动进入。
  static Future<void> setIOSAutoEnterPIPEnabled(
    VideoController controller,
    bool enabled,
  ) async {
    if (!Platform.isIOS) {
      return;
    }
    await controller.setAutoEnterPictureInPicture(enabled);
  }

  /// 为「换了视频源」做准备（连播下一集、换源、切清晰度等）。
  ///
  /// 保持小窗存活，只清掉上一集的残留（图层内容、时间轴与弹幕），
  /// 否则时间轴倒退会让系统小窗停在黑屏。
  static Future<void> prepareIOSPIPForNewMedia(
    VideoController controller,
  ) async {
    if (!Platform.isIOS) {
      return;
    }
    await controller.preparePictureInPictureForNewMedia();
  }

  // 进入桌面设备小窗模式，并用播放源比例固定窗口宽高比
  static Future<void> enterDesktopPIPWindow(
      {int width = 16, int height = 9}) async {
    final Size aspectSize = getPIPAspectSize(width: width, height: height);
    final double aspectRatio = aspectSize.width / aspectSize.height;
    const double pipWidth = 480;
    await windowManager.setAlwaysOnTop(true);
    await windowManager.setAspectRatio(aspectRatio);
    await windowManager.setSize(Size(pipWidth, pipWidth / aspectRatio));
  }

  // 退出桌面设备小窗模式
  static Future<void> exitDesktopPIPWindow() async {
    final lowResolution = await isLowResolution();
    await windowManager.setAlwaysOnTop(false);
    await windowManager.setAspectRatio(0);
    await windowManager
        .setSize(lowResolution ? const Size(800, 600) : const Size(1280, 860));
    await windowManager.center();
  }

  static void initPipHandler({
    required Future<void> Function(String action) onAction,
    required void Function(bool inPipMode) onModeChanged,
  }) {
    const MethodChannel pipChannel = MethodChannel('com.predidit.kazumi/pip');
    if (androidPIPInited) return;
    androidPIPInited = true;

    pipChannel.setMethodCallHandler((call) async {
      if (!Platform.isAndroid) {
        return;
      }

      final Object? args = call.arguments;
      final Map? arguments = (args is Map) ? args : null;

      switch (call.method) {
        case 'onModeChanged':
          final bool? inPipMode = arguments?['isInPipMode'] as bool?;
          if (inPipMode != null) {
            onModeChanged(inPipMode);
          }
        case 'onAction':
          final String? action = arguments?['action'] as String?;
          if (action != null) {
            await onAction(action);
          }
      }
    });
  }

  static void disposePipHandler() {
    const MethodChannel pipChannel = MethodChannel('com.predidit.kazumi/pip');
    pipChannel.setMethodCallHandler(null);
    androidPIPInited = false;
  }
}
