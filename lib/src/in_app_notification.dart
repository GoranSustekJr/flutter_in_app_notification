import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:in_app_notification/src/size_listenable_container.dart';

@visibleForTesting
const notificationShowingDuration = Duration(milliseconds: 350);

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
class InAppNotification extends StatefulWidget {
  /// Creates an in-app notification system.
  const InAppNotification({
    Key? key,
    required this.child,
  }) : super(key: key);

  final Widget child;

  /// Shows specified Widget as notification.
  ///
  /// [child] is required, this will be displayed as notification body.
  /// [context] is required, this is used to get Navigator instance.
  ///
  /// Showing and hiding notifications is managed by animation,
  /// and the process is as follows.
  ///
  /// 1. Execute this method, start animation via call state's `show` method
  ///    internally.
  /// 2. Then the notification appear, it will stay at specified [duration].
  /// 3. After the [duration] has elapsed,
  ///    play the animation in reverse and dispose the notification.
  static FutureOr<void> show({
    required Widget child,
    required BuildContext context,
    VoidCallback? onTap,
    Duration duration = const Duration(seconds: 10),
    Curve curve = Curves.ease,
    @visibleForTesting FutureOr Function()? notificationCreatedCallback,
  }) async {
    final state = context.findAncestorStateOfType<_InAppNotificationState>();

    assert(state != null);

    await state!.create(
      child: child,
      context: context,
      onTap: onTap,
      curve: curve,
    );
    if (kDebugMode) {
      await notificationCreatedCallback?.call();
    }
    state.show(duration: duration);
  }

  @override
  _InAppNotificationState createState() => _InAppNotificationState();
}

class _InAppNotificationState extends State<InAppNotification>
    with SingleTickerProviderStateMixin {
  VoidCallback? _onTap;
  Timer? _timer;
  double _verticalDragDistance = 0.0;

  OverlayEntry? _overlay;
  late CurvedAnimation _animation;

  double get _currentVerticalPosition =>
      _animation.value * _notificationSize.height + _verticalDragDistance;

  late final AnimationController _controller =
      AnimationController(vsync: this, duration: notificationShowingDuration)
        ..addListener(_updateNotification);

  Size _notificationSize = Size.zero;
  Completer<Size> _notificationSizeCompleter = Completer();
  Size _screenSize = Size.zero;

  @override
  void initState() {
    _animation = CurvedAnimation(parent: _controller, curve: Curves.ease);
    super.initState();
  }

  void _updateNotification() {
    _overlay?.markNeedsBuild();
  }

  Future<void> create({
    required Widget child,
    required BuildContext context,
    VoidCallback? onTap,
    Curve curve = Curves.ease,
  }) async {
    await dismiss();

    _verticalDragDistance = 0.0;
    _onTap = onTap;
    _animation = CurvedAnimation(parent: _controller, curve: curve);

    _overlay = OverlayEntry(
      builder: (context) {
        if (_screenSize == Size.zero) {
          _screenSize = MediaQuery.of(context).size *
              MediaQuery.of(context).devicePixelRatio;
        }

        return Positioned(
          bottom: MediaQuery.of(context).size.height -
              MediaQuery.of(context).viewPadding.top -
              _currentVerticalPosition,
          left: 0,
          right: 0,
          child: SizeListenableContainer(
            onSizeChanged: (size) => _notificationSizeCompleter.complete(size),
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: _onTapNotification,
              onTapDown: (_) => _onTapDown(),
              onVerticalDragUpdate: _onVerticalDragUpdate,
              onVerticalDragEnd: _onVerticalDragEnd,
              child: Material(color: Colors.transparent, child: child),
            ),
          ),
        );
      },
    );

    Navigator.of(context).overlay?.insert(_overlay!);
  }

  Future<void> show({
    Duration duration = const Duration(seconds: 10),
  }) async {
    _notificationSize = await _notificationSizeCompleter.future;

    _controller.forward(from: 0.0);

    if (duration.inMicroseconds == 0) return;
    _timer = Timer(duration, () => dismiss());
  }

  Future dismiss({double animationFrom = 1.0}) async {
    _timer?.cancel();

    if (_controller.status == AnimationStatus.completed) {
      await _controller.reverse(from: animationFrom);
    }

    _overlay?.remove();
    _overlay = null;
    _notificationSizeCompleter = Completer();
  }

  void _onTapNotification() {
    if (_onTap == null) return;

    dismiss();
    _onTap!();
  }

  void _onTapDown() {
    _timer?.cancel();
  }

  void _onVerticalDragUpdate(DragUpdateDetails details) {
    _verticalDragDistance = (_verticalDragDistance + details.delta.dy)
        .clamp(-_notificationSize.height, 0.0);
    _updateNotification();
  }

  void _onVerticalDragEnd(DragEndDetails details) async {
    final percentage =
        _currentVerticalPosition.abs() / _notificationSize.height;
    final velocity = details.velocity.pixelsPerSecond.dy * _screenSize.height;
    if (velocity <= -1.0) {
      await dismiss(animationFrom: percentage);
      return;
    }

    if (percentage >= 0.5) {
      if (_verticalDragDistance == 0.0) return;
      _verticalDragDistance = 0.0;
      _controller.forward(from: percentage);
    } else {
      dismiss(animationFrom: percentage);
    }
  }

  @override
  Widget build(BuildContext context) {
    return widget.child;
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }
}
