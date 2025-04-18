import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:in_app_notification_desktop/src/interact_animation_controller.dart';
import 'package:in_app_notification_desktop/src/size_listenable_container.dart';

part 'vsync_provider.dart';

@visibleForTesting
const notificationShowingDuration = Duration(milliseconds: 350);

@visibleForTesting
const notificationHorizontalAnimationDuration = Duration(milliseconds: 350);

/// A widget for display foreground notification.
///
/// It is mainly intended to wrap whole your app Widgets.
/// e.g. Just wrapping [MaterialApp].
///
/// {@tool snippet}
/// Usage example:
///
/// ```dart
/// return InAppNotification(
///   child: MaterialApp(
///     title: 'In-App Notification Demo',
///     home: const HomePage(),
///   ),
/// );
/// ```
/// {@end-tool}
class InAppNotification extends StatelessWidget {
  /// Creates an in-app notification system.
  const InAppNotification({
    Key? key,
    required this.child,
  }) : super(key: key);

  final Widget child;

  /// Shows specified Widget as notification.
  ///
  /// [child] is required, this will be displayed as notification body.
  /// [context] is required, this is used to get internally used notification controller class which is subclass of `InheritedWidget`.
  ///
  /// Showing and hiding notifications is managed by animation,
  /// and the process is as follows.
  ///
  /// 1. Execute this method, start animation via call state's `show` method
  ///    internally.
  /// 2. Then the notification appear, it will stay at specified [duration].
  /// 3. After the [duration] has elapsed,
  ///    play the animation in reverse and dispose the notification.
  ///
  /// This method will awaits an animation that showing the notification.
  static FutureOr<void> show({
    required Widget child,
    required BuildContext context,
    VoidCallback? onTap,
    Duration duration = const Duration(seconds: 10),
    Curve curve = Curves.easeOutCubic,
    double width = 250,
    Curve dismissCurve = Curves.easeOutCubic,
    @visibleForTesting FutureOr Function()? notificationCreatedCallback,
  }) async {
    final controller = _NotificationController.of(context);

    assert(controller != null, 'Not found InAppNotification controller.');

    await controller!
        .create(child: child, context: context, width: width, onTap: onTap);
    if (kDebugMode) {
      await notificationCreatedCallback?.call();
    }
    controller.show(
        duration: duration, curve: curve, dismissCurve: dismissCurve);
  }

  /// Hides a shown notification.
  ///
  /// [context] is required, this is used to get internally used notification controller class which is subclass of `InheritedWidget`.
  ///
  /// This method will awaits an animation that showing the notification.
  static FutureOr<void> dismiss({required BuildContext context}) async {
    final controller = _NotificationController.of(context);

    if (controller == null) return;

    await controller.dismissProgramatically();
  }

  @override
  Widget build(BuildContext context) {
    return _VsyncProvider(child: child);
  }
}

class _NotificationController extends InheritedWidget {
  const _NotificationController({
    Key? key,
    required Widget child,
    required this.state,
  }) : super(key: key, child: child);

  final _NotificationState state;

  static _NotificationController? of(BuildContext context) => context
      .getElementForInheritedWidgetOfExactType<_NotificationController>()
      ?.widget as _NotificationController;

  @override
  bool updateShouldNotify(covariant _NotificationController oldWidget) => false;

  Future<void> create({
    required Widget child,
    required BuildContext context,
    required double width,
    VoidCallback? onTap,
  }) async {
    await dismiss(shouldAnimation: !state.showController.isDismissed);

    state.verticalAnimationController.dragDistance = 0.0;
    state.horizontalAnimationController.dragDistance = 0.0;
    state.onTap = onTap;

    state.overlay = OverlayEntry(
      builder: (context) {
        if (state.screenSize == Size.zero) {
          state.screenSize = MediaQuery.of(context).size;
          state.horizontalAnimationController.screenWidth =
              state.screenSize.width;
        }

        return Positioned(
          bottom: 20,
          right: state.currentHorizontalPosition,
          width: width,
          child: SizeListenableContainer(
            onSizeChanged: (size) {
              if (state.notificationSizeCompleter.isCompleted) return;
              final topPadding = MediaQuery.of(context).viewPadding.top;
              state.notificationSizeCompleter
                  .complete(size + Offset(0, topPadding));
            },
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: _onTapNotification,
              onTapDown: (_) => _onTapDown(),
              onVerticalDragUpdate: _onVerticalDragUpdate,
              onVerticalDragEnd: _onVerticalDragEnd,
              onHorizontalDragUpdate: _onHorizontalDragUpdate,
              onHorizontalDragEnd: _onHorizontalDragEnd,
              child: Material(color: Colors.transparent, child: child),
            ),
          ),
        );
      },
    );

    Navigator.of(context).overlay?.insert(state.overlay!);

    // Animate the notification from the right outside of the screen to the visible part of the screen on the right
    await state.horizontalAnimationController.show();
  }

  Future<void> show({
    required Duration duration,
    required Curve curve,
    required Curve dismissCurve,
  }) async {
    final size = await state.notificationSizeCompleter.future;
    final isSizeChanged = state.notificationSize != size;
    state.notificationSize = size;
    state.verticalAnimationController.notificationHeight =
        state.notificationSize.height;

    if (isSizeChanged) {
      state.showAnimation = Tween(
        begin: 1.0,
        end: state.notificationSize.width,
      ).animate(
        CurvedAnimation(
          parent: state.showController,
          curve: curve,
          reverseCurve: dismissCurve,
        ),
      );
    }

    await state.showController.forward(from: 0.0);

    if (duration.inMicroseconds == 0) return;
    state.timer = Timer(duration, () => dismiss());
  }

  Future<void> dismiss({bool shouldAnimation = true, double from = 1.0}) async {
    state.timer?.cancel();

    await state.showController.reverse(from: shouldAnimation ? from : 0.0);

    state.overlay?.remove();
    state.overlay = null;
    state.notificationSizeCompleter = Completer();
  }

  void _onTapNotification() {
    if (state.onTap == null) return;

    dismiss();
    state.onTap!();
  }

  void _onTapDown() {
    state.timer?.cancel();
  }

  void _onVerticalDragUpdate(DragUpdateDetails details) {
    state.verticalAnimationController.dragDistance =
        (state.verticalAnimationController.dragDistance + details.delta.dy)
            .clamp(-state.notificationSize.height, 0.0);
    state.updateNotification();
  }

  void _onVerticalDragEnd(DragEndDetails details) async {
    final percentage =
        state.currentVerticalPosition.abs() / state.notificationSize.height;
    final velocity =
        details.velocity.pixelsPerSecond.dy * state.screenSize.height;
    if (velocity <= -1.0) {
      await state.verticalAnimationController.dismiss(
          currentPosition: state.currentVerticalPosition, toLeft: false);
      await dismiss(
        shouldAnimation: false,
      );
      return;
    }

    if (percentage >= 0.5) {
      if (state.verticalAnimationController.dragDistance == 0.0) return;
      await state.verticalAnimationController.stay();
    } else {
      await state.verticalAnimationController.dismiss(
          currentPosition: state.currentVerticalPosition, toLeft: false);
      await dismiss(shouldAnimation: false);
    }
  }

  void _onHorizontalDragUpdate(DragUpdateDetails details) {
    if (details.primaryDelta! > 0) {
      state.horizontalAnimationController.dragDistance -= details.delta.dx;
      state.updateNotification();
    }
  }

  void _onHorizontalDragEnd(DragEndDetails details) async {
    final velocity =
        details.velocity.pixelsPerSecond.dx / state.screenSize.width;
    final position = state.horizontalAnimationController.dragDistance /
        state.screenSize.width;

    if (velocity.abs() >= 1.0 || position.abs() >= 0.2) {
      await state.horizontalAnimationController.dismiss(toLeft: false);

      dismiss(shouldAnimation: false);
    } else {
      await state.horizontalAnimationController.stay();
    }
  }

  Future<void> dismissProgramatically() async {
    await dismiss(
      shouldAnimation: !state.showController.isDismissed,
      from: state.showController.value,
    );
  }
}

class _NotificationState {
  VoidCallback? onTap;
  Timer? timer;

  OverlayEntry? overlay;
  Animation<double>? showAnimation;

  double get currentVerticalPosition =>
      (showAnimation?.value ?? 0.0) +
      (_verticalAnimation?.value ?? 0.0) +
      verticalAnimationController.dragDistance;
  double get currentHorizontalPosition =>
      (_horizontalAnimation?.value ?? 0.0) +
      horizontalAnimationController.dragDistance;

  final AnimationController showController;
  final VerticalInteractAnimationController verticalAnimationController;
  final HorizontalInteractAnimationController horizontalAnimationController;

  Animation<double>? get _verticalAnimation =>
      verticalAnimationController.currentAnimation;
  Animation<double>? get _horizontalAnimation =>
      horizontalAnimationController.currentAnimation;

  Size notificationSize = Size.zero;
  Completer<Size> notificationSizeCompleter = Completer();
  Size screenSize = Size.zero;

  _NotificationState({
    required this.showController,
    required this.verticalAnimationController,
    required this.horizontalAnimationController,
  }) {
    showController.addListener(updateNotification);
    verticalAnimationController.addListener(updateNotification);
    horizontalAnimationController.addListener(updateNotification);
  }

  void updateNotification() {
    overlay?.markNeedsBuild();
  }
}

class HorizontalInteractAnimationController extends AnimationController
    implements InteractnimationController {
  @override
  Animation<double>? currentAnimation;

  @override
  double dragDistance = 0.0;

  double _screenWidth = 0.0;

  set screenWidth(double value) => _screenWidth = value;

  HorizontalInteractAnimationController({
    required TickerProvider vsync,
    required Duration duration,
  }) : super(vsync: vsync, duration: duration);

  @override
  Future<void> dismiss({bool toLeft = false}) async {
    final endValue = toLeft
        ? _screenWidth // Move to the right side of the screen
        : dragDistance.sign *
            _screenWidth; // Dismiss to the left side if not toLeft

    currentAnimation = Tween(
      begin: dragDistance,
      end: endValue,
    ).chain(CurveTween(curve: Curves.easeOut)).animate(this);

    dragDistance = 0.0;
    await forward(from: 0.0);
    currentAnimation = null;
  }

  @override
  Future<void> stay() async {
    currentAnimation = Tween(begin: dragDistance, end: 0.0)
        .chain(CurveTween(curve: Curves.easeOut))
        .animate(this);
    dragDistance = 0.0;

    await forward(from: 0.0);
    currentAnimation = null;
  }

  // Show method: Animate from right (off-screen) to the final position on the screen
  Future<void> show() async {
    currentAnimation = Tween(
      begin: -_screenWidth * 2, // Start off-screen to the right
      end: 0.0, // Move to the visible right side of the screen
    ).chain(CurveTween(curve: Curves.easeOut)).animate(this);

    await forward(from: 0.0);
  }
}
