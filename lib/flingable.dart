// Copyright 2017 David Roundy <daveroundy@gmail.com>

// Copyright 2015 The Chromium Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';


const Duration _kFlingDuration = const Duration(milliseconds: 200);
const double _kMinFlingVelocity = 700.0;
const double _kMinFlingVelocityDelta = 400.0;
const double _kFlingVelocityScale = 1.0 / 300.0;
const double _kFlingThreshold = 0.4;

/// Signature used by [Flingable] to indicate that it has been flinged in
/// the given `direction`.
///
/// Used by [Flingable.onFlinged].
typedef void FlingDirectionCallback(FlingDirection direction);

/// The direction in which a [Flingable] can be flinged.
enum FlingDirection {
  /// The [Flingable] can be flinged by dragging either left or right.
  horizontal,

  /// The [Flingable] can be flinged by dragging in the reverse of the
  /// reading direction (e.g., from right to left in left-to-right languages).
  endToStart,

  /// The [Flingable] can be flinged by dragging in the reading direction
  /// (e.g., from left to right in left-to-right languages).
  startToEnd,

  /// The [Flingable] can be flinged by dragging up only.
  up,

  /// The [Flingable] can be flinged by dragging down only.
  down
}

/// A widget that can be flinged by dragging in the indicated [direction].
///
/// Dragging or flinging this widget in the [FlingDirection] causes the child
/// to slide out of view.
///
/// Backgrounds can be used to implement the "leave-behind" idiom. If a background
/// is specified it is stacked behind the Flingable's child and is exposed when
/// the child moves.
///
/// The widget calls the [onFlinged] callback immediately after the slide
/// animation. If the Flingable is a list item, it must have a key that
/// distinguishes it from the other items.
class Flingable extends StatefulWidget {
  /// Creates a widget that can be flinged.
  ///
  /// The [key] argument must not be null because [Flingable]s are commonly
  /// used in lists and removed from the list when flinged. Without keys, the
  /// default behavior is to sync widgets based on their index in the list,
  /// which means the item after the flinged item would be synced with the
  /// state of the flinged item. Using keys causes the widgets to sync
  /// according to their keys and avoids this pitfall.
  const Flingable({
    @required Key key,
    @required this.child,
    this.background,
    this.secondaryBackground,
    this.onFlinged,
    this.flingThresholds: const <FlingDirection, double>{},
  }) : assert(key != null),
       assert(secondaryBackground != null ? background != null : true),
       super(key: key);

  /// The widget below this widget in the tree.
  final Widget child;

  /// A widget that is stacked behind the child. If secondaryBackground is also
  /// specified then this widget only appears when the child has been dragged
  /// down or to the right.
  final Widget background;

  /// A widget that is stacked behind the child and is exposed when the child
  /// has been dragged up or to the left. It may only be specified when background
  /// has also been specified.
  final Widget secondaryBackground;

  /// Called when the widget has been flinged, after finishing resizing.
  final FlingDirectionCallback onFlinged;

  /// The offset threshold the item has to be dragged in order to be considered flinged.
  ///
  /// Represented as a fraction, e.g. if it is 0.4, then the item has to be dragged at least
  /// 40% towards one direction to be considered flinged. Clients can define different
  /// thresholds for each fling direction. This allows for use cases where item can be
  /// flinged to end but not to start.
  final Map<FlingDirection, double> flingThresholds;

  @override
  _FlingableState createState() => new _FlingableState();
}

class _FlingableClipper extends CustomClipper<Rect> {
  _FlingableClipper({
    @required this.moveAnimation
  }) : assert(moveAnimation != null),
       super(reclip: moveAnimation);

  final Animation<FractionalOffset> moveAnimation;

  @override
  Rect getClip(Size size) {
    final double offset = moveAnimation.value.dx * size.width;
    if (offset < 0)
      return new Rect.fromLTRB(size.width + offset, 0.0, size.width, size.height);
    return new Rect.fromLTRB(0.0, 0.0, offset, size.height);
  }

  @override
  Rect getApproximateClipRect(Size size) => getClip(size);

  @override
  bool shouldReclip(_FlingableClipper oldClipper) {
    return oldClipper.moveAnimation.value != moveAnimation.value;
  }
}

class _FlingableState extends State<Flingable> with TickerProviderStateMixin, AutomaticKeepAliveClientMixin {
  @override
  void initState() {
    super.initState();
    _moveController = new AnimationController(duration: _kFlingDuration, vsync: this)
      ..addStatusListener(_handleFlingStatusChanged);
    _updateMoveAnimation();
  }

  AnimationController _moveController;
  Animation<FractionalOffset> _moveAnimation;

  double _dragExtent = 0.0;
  bool _dragUnderway = false;
  Size _sizePriorToCollapse;

  @override
  bool get wantKeepAlive => _moveController?.isAnimating == true;

  @override
  void dispose() {
    _moveController.dispose();
    super.dispose();
  }

  FlingDirection get _flingDirection {
    return  _dragExtent > 0 ? FlingDirection.startToEnd : FlingDirection.endToStart;
  }

  double get _flingThreshold {
    return widget.flingThresholds[_flingDirection] ?? _kFlingThreshold;
  }

  bool get _isActive {
    return _dragUnderway || _moveController.isAnimating;
  }

  double get _overallDragAxisExtent {
    final Size size = context.size;
    return size.width;
  }

  void _handleDragStart(DragStartDetails details) {
    _dragUnderway = true;
    if (_moveController.isAnimating) {
      _dragExtent = _moveController.value * _overallDragAxisExtent * _dragExtent.sign;
      _moveController.stop();
    } else {
      _dragExtent = 0.0;
      _moveController.value = 0.0;
    }
    setState(() {
      _updateMoveAnimation();
    });
  }

  void _handleDragUpdate(DragUpdateDetails details) {
    if (!_isActive || _moveController.isAnimating)
      return;

    final double delta = details.primaryDelta;
    final double oldDragExtent = _dragExtent;
    _dragExtent += delta;
    if (oldDragExtent.sign != _dragExtent.sign) {
      setState(() {
        _updateMoveAnimation();
      });
    }
    if (!_moveController.isAnimating) {
      _moveController.value = _dragExtent.abs() / _overallDragAxisExtent;
    }
  }

  void _updateMoveAnimation() {
    _moveAnimation = new FractionalOffsetTween(
      begin: FractionalOffset.topLeft,
      end: new FractionalOffset(_dragExtent.sign, 0.0)
    ).animate(_moveController);
  }

  bool _isFlingGesture(Velocity velocity) {
    // Cannot fling an item if it cannot be flinged by drag.
    if (_flingThreshold >= 1.0)
      return false;
    final double vx = velocity.pixelsPerSecond.dx;
    final double vy = velocity.pixelsPerSecond.dy;
    if (vx.abs() - vy.abs() < _kMinFlingVelocityDelta)
      return false;
    return vx.abs() > _kMinFlingVelocity;
  }

  void _handleDragEnd(DragEndDetails details) {
    if (!_isActive || _moveController.isAnimating)
      return;
    _dragUnderway = false;
    if (_moveController.isCompleted) {
      _startResizeAnimation();
    } else if (_isFlingGesture(details.velocity)) {
      final double flingVelocity = details.velocity.pixelsPerSecond.dx;
      _dragExtent = flingVelocity.sign;
      _moveController.fling(velocity: flingVelocity.abs() * _kFlingVelocityScale);
    } else if (_moveController.value > _flingThreshold) {
      _moveController.forward();
    } else {
      _moveController.reverse();
    }
  }

  void _handleFlingStatusChanged(AnimationStatus status) {
    if (status == AnimationStatus.completed && !_dragUnderway)
      _startResizeAnimation();
    updateKeepAlive();
  }

  void _startResizeAnimation() {
    assert(_moveController != null);
    assert(_moveController.isCompleted);
    assert(_sizePriorToCollapse == null);
    if (widget.onFlinged != null)
      widget.onFlinged(_flingDirection);
  }

  @override
  Widget build(BuildContext context) {
    super.build(context); // See AutomaticKeepAliveClientMixin.
    Widget background = widget.background;
    if (widget.secondaryBackground != null) {
      final FlingDirection direction = _flingDirection;
      if (direction == FlingDirection.endToStart || direction == FlingDirection.up)
        background = widget.secondaryBackground;
    }

    Widget content = new SlideTransition(
      position: _moveAnimation,
      child: widget.child
    );

    if (background != null) {
      final List<Widget> children = <Widget>[];

      if (!_moveAnimation.isDismissed) {
        children.add(new Positioned.fill(
          child: new ClipRect(
            clipper: new _FlingableClipper(
              moveAnimation: _moveAnimation,
            ),
            child: background
          )
        ));
      }

      children.add(content);
      content = new Stack(children: children);
    }

    // We are not resizing but we may be being dragging in widget.direction.
    return new GestureDetector(
      onHorizontalDragStart: _handleDragStart,
      onHorizontalDragUpdate: _handleDragUpdate,
      onHorizontalDragEnd: _handleDragEnd,
      behavior: HitTestBehavior.opaque,
      child: content
    );
  }
}
