// Copyright 2017 David Roundy <daveroundy@gmail.com>

// Copyright 2015 The Chromium Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

const Duration _kFlingDuration = const Duration(milliseconds: 200);
const Curve _kResizeTimeCurve = const Interval(0.4, 1.0, curve: Curves.ease);
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
  /// The [Flingable] can be flinged by dragging either up or down.
  vertical,

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
/// to slide out of view. Following the slide animation, if [resizeDuration] is
/// non-null, the Flingable widget animates its height (or width, whichever is
/// perpendicular to the fling direction) to zero over the [resizeDuration].
///
/// Backgrounds can be used to implement the "leave-behind" idiom. If a background
/// is specified it is stacked behind the Flingable's child and is exposed when
/// the child moves.
///
/// The widget calls the [onFlinged] callback either after its size has
/// collapsed to zero (if [resizeDuration] is non-null) or immediately after
/// the slide animation (if [resizeDuration] is null). If the Flingable is a
/// list item, it must have a key that distinguishes it from the other items.
class Flingable extends StatefulWidget {
  /// Creates a widget that can be flinged.
  ///
  /// The [key] argument must not be null because [Flingable]s are commonly
  /// used in lists and reordered in the list when flinged. Without keys, the
  /// default behavior is to sync widgets based on their index in the list,
  /// which means the item after the flinged item would be synced with the
  /// state of the flinged item. Using keys causes the widgets to sync
  /// according to their keys and avoids this pitfall.
  const Flingable({
    @required Key key,
    @required this.child,
    this.background,
    this.secondaryBackground,
    this.onResize,
    this.onFlinged,
    this.direction: FlingDirection.horizontal,
    this.resizeDuration: const Duration(milliseconds: 300),
    this.flingThresholds: const <FlingDirection, double>{},
  })
      : assert(key != null),
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

  /// Called when the widget changes size (i.e., when contracting before being flinged).
  final VoidCallback onResize;

  /// Called when the widget has been flinged, after finishing resizing.
  final FlingDirectionCallback onFlinged;

  /// The direction in which the widget can be flinged.
  final FlingDirection direction;

  /// The amount of time the widget will spend contracting before [onFlinged] is called.
  ///
  /// If null, the widget will not contract and [onFlinged] will be called
  /// immediately after the the widget is flinged.
  final Duration resizeDuration;

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
  _FlingableClipper({@required this.axis, @required this.moveAnimation})
      : assert(axis != null),
        assert(moveAnimation != null),
        super(reclip: moveAnimation);

  final Axis axis;
  final Animation<Offset> moveAnimation;

  @override
  Rect getClip(Size size) {
    assert(axis != null);
    switch (axis) {
      case Axis.horizontal:
        final double offset = moveAnimation.value.dx * size.width;
        if (offset < 0)
          return new Rect.fromLTRB(
              size.width + offset, 0.0, size.width, size.height);
        return new Rect.fromLTRB(0.0, 0.0, offset, size.height);
      case Axis.vertical:
        final double offset = moveAnimation.value.dy * size.height;
        if (offset < 0)
          return new Rect.fromLTRB(
              0.0, size.height + offset, size.width, size.height);
        return new Rect.fromLTRB(0.0, 0.0, size.width, offset);
    }
    return null;
  }

  @override
  Rect getApproximateClipRect(Size size) => getClip(size);

  @override
  bool shouldReclip(_FlingableClipper oldClipper) {
    return oldClipper.axis != axis ||
        oldClipper.moveAnimation.value != moveAnimation.value;
  }
}

class _FlingableState extends State<Flingable> with TickerProviderStateMixin {
  @override
  void initState() {
    super.initState();
    _moveController =
        new AnimationController(duration: _kFlingDuration, vsync: this)
          ..addStatusListener(_handleFlingStatusChanged);
    _updateMoveAnimation();
    //_growToSize();
  }

  AnimationController _moveController;
  Animation<Offset> _moveAnimation;

  AnimationController _resizeController;
  Animation<double> _resizeAnimation;

  double _dragExtent = 0.0;
  bool _dragUnderway = false;
  Size _sizePriorToCollapse;
  bool _amRestoring = false;

  @override
  void dispose() {
    _moveController.dispose();
    _resizeController?.dispose();
    super.dispose();
  }

  bool get _directionIsXAxis {
    return widget.direction == FlingDirection.horizontal ||
        widget.direction == FlingDirection.endToStart ||
        widget.direction == FlingDirection.startToEnd;
  }

  FlingDirection get _flingDirection {
    if (_directionIsXAxis)
      return _dragExtent > 0
          ? FlingDirection.startToEnd
          : FlingDirection.endToStart;
    return _dragExtent > 0 ? FlingDirection.down : FlingDirection.up;
  }

  double get _flingThreshold {
    return widget.flingThresholds[_flingDirection] ?? _kFlingThreshold;
  }

  bool get _isActive {
    return _dragUnderway || _moveController.isAnimating;
  }

  double get _overallDragAxisExtent {
    final Size size = context.size;
    return _directionIsXAxis ? size.width : size.height;
  }

  void _handleDragStart(DragStartDetails details) {
    _dragUnderway = true;
    if (_moveController.isAnimating) {
      _dragExtent =
          _moveController.value * _overallDragAxisExtent * _dragExtent.sign;
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
    if (!_isActive || _moveController.isAnimating) return;

    final double delta = details.primaryDelta;
    final double oldDragExtent = _dragExtent;
    switch (widget.direction) {
      case FlingDirection.horizontal:
      case FlingDirection.vertical:
        _dragExtent += delta;
        break;

      case FlingDirection.up:
      case FlingDirection.endToStart:
        if (_dragExtent + delta < 0) _dragExtent += delta;
        break;

      case FlingDirection.down:
      case FlingDirection.startToEnd:
        if (_dragExtent + delta > 0) _dragExtent += delta;
        break;
    }
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
    final double end = _dragExtent.sign;
    _moveAnimation = new Tween<Offset>(
      begin: Offset.zero,
      end: new Offset(end, 0.0),
    )
        .animate(_moveController);
  }

  bool _isFlingGesture(Velocity velocity) {
    // Cannot fling an item if it cannot be flinged by drag.
    if (_flingThreshold >= 1.0) return false;
    final double vx = velocity.pixelsPerSecond.dx;
    final double vy = velocity.pixelsPerSecond.dy;
    if (_directionIsXAxis) {
      if (vx.abs() - vy.abs() < _kMinFlingVelocityDelta) return false;
      switch (widget.direction) {
        case FlingDirection.horizontal:
          return vx.abs() > _kMinFlingVelocity;
        case FlingDirection.endToStart:
          return -vx > _kMinFlingVelocity;
        default:
          return vx > _kMinFlingVelocity;
      }
    } else {
      if (vy.abs() - vx.abs() < _kMinFlingVelocityDelta) return false;
      switch (widget.direction) {
        case FlingDirection.vertical:
          return vy.abs() > _kMinFlingVelocity;
        case FlingDirection.up:
          return -vy > _kMinFlingVelocity;
        default:
          return vy > _kMinFlingVelocity;
      }
    }
  }

  void _handleDragEnd(DragEndDetails details) {
    if (!_isActive || _moveController.isAnimating) return;
    _dragUnderway = false;
    if (_moveController.isCompleted) {
      _startResizeAnimation();
    } else if (_isFlingGesture(details.velocity)) {
      final double flingVelocity = _directionIsXAxis
          ? details.velocity.pixelsPerSecond.dx
          : details.velocity.pixelsPerSecond.dy;
      _dragExtent = flingVelocity.sign;
      _moveController.fling(
          velocity: flingVelocity.abs() * _kFlingVelocityScale);
    } else if (_moveController.value > _flingThreshold) {
      _moveController.forward();
    } else {
      _moveController.reverse();
    }
  }

  void _handleFlingStatusChanged(AnimationStatus status) {
    if (status == AnimationStatus.completed && !_dragUnderway)
      _startResizeAnimation();
  }

  void _startResizeAnimation() {
    assert(_moveController != null);
    assert(_moveController.isCompleted);
    assert(_resizeController == null);
    assert(_sizePriorToCollapse == null);
    if (widget.resizeDuration == null) {
      if (widget.onFlinged != null) widget.onFlinged(_flingDirection);
    } else {
      _resizeController =
          new AnimationController(duration: widget.resizeDuration, vsync: this)
            ..addListener(_handleResizeProgressChanged);
      _resizeController.forward();
      setState(() {
        _sizePriorToCollapse = context.size;
        _resizeAnimation = new Tween<double>(begin: 1.0, end: 0.0).animate(
            new CurvedAnimation(
                parent: _resizeController, curve: _kResizeTimeCurve));
      });
    }
  }

  void _growToSize() {
    setState(() {
      _amRestoring = true;
      _resizeController =
          new AnimationController(duration: widget.resizeDuration, vsync: this)
            ..addListener(_handleResizeProgressChanged);
      _resizeController.forward();
      _resizeAnimation = new Tween<double>(begin: 0.0, end: 1.0).animate(
          new CurvedAnimation(
              parent: _resizeController, curve: _kResizeTimeCurve));
    });
  }

  void _handleResizeProgressChanged() {
    if (_resizeController.isCompleted) {
      _amRestoring = !_amRestoring;
      if (_amRestoring) {
        if (widget.onFlinged != null) widget.onFlinged(_flingDirection);

        _growToSize();
        // Here we restore the widget to its original size.
      } else {
        setState(() {
          _amRestoring = false;
          _resizeAnimation = null;
          _resizeController = null;
          _sizePriorToCollapse = null;
          _moveController =
              new AnimationController(duration: _kFlingDuration, vsync: this)
                ..addStatusListener(_handleFlingStatusChanged);
          _updateMoveAnimation();
        });
      }
    } else {
      if (widget.onResize != null) widget.onResize();
    }
  }

  @override
  Widget build(BuildContext context) {
    Widget background = widget.background;
    if (widget.secondaryBackground != null) {
      final FlingDirection direction = _flingDirection;
      if (direction == FlingDirection.endToStart ||
          direction == FlingDirection.up)
        background = widget.secondaryBackground;
    }

    if (_resizeAnimation != null) {
      // we are now resizing.
      if (_amRestoring) {
        return new SizeTransition(
            sizeFactor: _resizeAnimation,
            axis: _directionIsXAxis ? Axis.vertical : Axis.horizontal,
            child: widget.child);
      } else {
        return new SizeTransition(
            sizeFactor: _resizeAnimation,
            axis: _directionIsXAxis ? Axis.vertical : Axis.horizontal,
            child: new SizedBox(
                width: _sizePriorToCollapse.width,
                height: _sizePriorToCollapse.height,
                child: background));
      }
    }

    Widget content =
        new SlideTransition(position: _moveAnimation, child: widget.child);

    if (background != null) {
      final List<Widget> children = <Widget>[];

      if (!_moveAnimation.isDismissed) {
        children.add(new Positioned.fill(
            child: new ClipRect(
                clipper: new _FlingableClipper(
                  axis: _directionIsXAxis ? Axis.horizontal : Axis.vertical,
                  moveAnimation: _moveAnimation,
                ),
                child: background)));
      }

      children.add(content);
      content = new Stack(children: children);
    }

    // We are not resizing but we may be being dragging in widget.direction.
    return new GestureDetector(
        onHorizontalDragStart: _directionIsXAxis ? _handleDragStart : null,
        onHorizontalDragUpdate: _directionIsXAxis ? _handleDragUpdate : null,
        onHorizontalDragEnd: _directionIsXAxis ? _handleDragEnd : null,
        onVerticalDragStart: _directionIsXAxis ? null : _handleDragStart,
        onVerticalDragUpdate: _directionIsXAxis ? null : _handleDragUpdate,
        onVerticalDragEnd: _directionIsXAxis ? null : _handleDragEnd,
        behavior: HitTestBehavior.opaque,
        child: content);
  }
}
