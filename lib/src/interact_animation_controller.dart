import 'package:flutter/material.dart';

final _defaultCurve = CurveTween(curve: Curves.easeOutCubic);

abstract class InteractnimationController {
  Animation<double>? currentAnimation;
  late double dragDistance;

  /// Animate to make the notification stay in screen.
  Future<void> stay();

  /// Animate to dismiss the notification.
  Future<void> dismiss({bool toLeft = false});
}

class VerticalInteractAnimationController extends AnimationController
    implements InteractnimationController {
  @override
  Animation<double>? currentAnimation;

  @override
  double dragDistance = 0.0;

  double _notificationHeight = 0.0;

  set notificationHeight(double value) => _notificationHeight = value;

  VerticalInteractAnimationController({
    required TickerProvider vsync,
    required Duration duration,
  }) : super(vsync: vsync, duration: duration);

  @override
  Future<void> dismiss(
      {double currentPosition = 0.0, bool toLeft = false}) async {
    currentAnimation = Tween(
      begin: currentPosition - _notificationHeight,
      end: -_notificationHeight,
    ).chain(_defaultCurve).animate(this);
    dragDistance = 0.0;

    await forward(from: 0.0);
    currentAnimation = null;
  }

  @override
  Future<void> stay() async {
    currentAnimation =
        Tween(begin: dragDistance, end: 0.0).chain(_defaultCurve).animate(this);

    dragDistance = 0.0;
    await forward(from: 0.0);
    currentAnimation = null;
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
    // If toRight is true, animate out to the right, else dismiss to the left
    final endValue = toLeft
        ? _screenWidth // Move to the right side of the screen
        : dragDistance.sign *
            _screenWidth; // Dismiss to the left side if not toRight

    currentAnimation = Tween(
      begin: 0.0, // Start from the visible position
      end: endValue, // End at the off-screen position (either left or right)
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

  // Show method: Animate from the bottom-right to the visible position
  Future<void> show() async {
    // Starts below the screen, from the bottom-right corner
    currentAnimation = Tween(
      begin:
          _screenWidth, // Start below the screen (off the screen on the right)
      end: 0.0, // Slide up into the visible screen from the bottom-right corner
    ).chain(CurveTween(curve: Curves.easeOut)).animate(this);

    await forward(from: 0.0);
  }
}
