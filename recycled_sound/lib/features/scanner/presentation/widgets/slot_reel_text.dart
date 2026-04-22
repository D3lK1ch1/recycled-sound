import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../../core/theme/app_colors.dart';

/// A text widget that cycles through candidate values like a slot machine
/// reel, then decelerates and locks onto the detected value with an
/// overshoot-bounce.
///
/// While [targetValue] is null, the reel spins through [candidates].
/// When [targetValue] is set, it decelerates, overshoots past the target,
/// then bounces back to land on it.
class SlotReelText extends StatefulWidget {
  const SlotReelText({
    super.key,
    required this.candidates,
    this.targetValue,
    this.style,
    this.lockedStyle,
    this.spinSpeed = const Duration(milliseconds: 80),
  });

  /// Values to cycle through while spinning.
  final List<String> candidates;

  /// The detected value to land on. Null = keep spinning.
  final String? targetValue;

  /// Style while spinning.
  final TextStyle? style;

  /// Style after locking (defaults to green).
  final TextStyle? lockedStyle;

  /// How fast to cycle while spinning.
  final Duration spinSpeed;

  @override
  State<SlotReelText> createState() => _SlotReelTextState();
}

class _SlotReelTextState extends State<SlotReelText>
    with SingleTickerProviderStateMixin {
  Timer? _spinTimer;
  int _currentIndex = 0;
  String _displayValue = '';
  bool _locked = false;
  bool _locking = false; // in deceleration phase

  // For the slide animation
  late final AnimationController _slideController;
  String _outgoingValue = '';
  bool _isSliding = false;

  final _rng = math.Random();

  @override
  void initState() {
    super.initState();
    _slideController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 60),
    );

    if (widget.candidates.isNotEmpty) {
      _currentIndex = _rng.nextInt(widget.candidates.length);
      _displayValue = widget.candidates[_currentIndex];
    }

    if (widget.targetValue != null) {
      _locked = true;
      _displayValue = widget.targetValue!;
    } else {
      _startSpinning();
    }
  }

  @override
  void didUpdateWidget(SlotReelText old) {
    super.didUpdateWidget(old);

    // Target just arrived — start deceleration
    if (widget.targetValue != null && !_locked && !_locking) {
      _locking = true;
      _decelerate();
    }
  }

  @override
  void dispose() {
    _spinTimer?.cancel();
    _slideController.dispose();
    super.dispose();
  }

  void _startSpinning() {
    _spinTimer = Timer.periodic(widget.spinSpeed, (_) {
      if (_locking) return;
      _advance();
    });
  }

  void _advance() {
    if (widget.candidates.isEmpty) return;
    _currentIndex = (_currentIndex + 1) % widget.candidates.length;
    final next = widget.candidates[_currentIndex];

    setState(() {
      _outgoingValue = _displayValue;
      _displayValue = next;
      _isSliding = true;
    });

    _slideController.forward(from: 0).then((_) {
      if (mounted) setState(() => _isSliding = false);
    });
  }

  /// Decelerate: increase interval between ticks, overshoot past target,
  /// then bounce back.
  Future<void> _decelerate() async {
    _spinTimer?.cancel();

    final target = widget.targetValue!;

    // Ensure target is in candidates for the overshoot to work
    final targetIdx = widget.candidates.indexOf(target);

    // Phase 1: slow down over ~6 ticks
    for (var delay = 100; delay <= 250; delay += 30) {
      await Future<void>.delayed(Duration(milliseconds: delay));
      if (!mounted) return;
      _advance();
    }

    // Phase 2: land on the value AFTER target (overshoot)
    if (targetIdx >= 0) {
      // Advance to one past target
      final overshootIdx = (targetIdx + 1) % widget.candidates.length;
      setState(() {
        _outgoingValue = _displayValue;
        _displayValue = widget.candidates[overshootIdx];
        _isSliding = true;
      });
      _slideController.forward(from: 0);
      await Future<void>.delayed(const Duration(milliseconds: 200));
    }

    // Phase 3: bounce back to target
    if (!mounted) return;
    setState(() {
      _outgoingValue = _displayValue;
      _displayValue = target;
      _isSliding = true;
      _locked = true;
    });
    _slideController.forward(from: 0);
    HapticFeedback.mediumImpact();
  }

  @override
  Widget build(BuildContext context) {
    final spinStyle = widget.style ??
        const TextStyle(
          fontFamily: 'monospace',
          fontSize: 12,
          fontWeight: FontWeight.w400,
          color: Color(0x55FFFFFF),
          letterSpacing: 0.3,
        );

    final lockStyle = widget.lockedStyle ??
        TextStyle(
          fontFamily: 'monospace',
          fontSize: 12,
          fontWeight: FontWeight.w600,
          color: AppColors.success,
          letterSpacing: 0.3,
        );

    final style = _locked ? lockStyle : spinStyle;

    return ClipRect(
      child: SizedBox(
        height: 16,
        child: AnimatedBuilder(
          animation: _slideController,
          builder: (context, _) {
            final t = _slideController.value;
            if (!_isSliding || t >= 1.0) {
              return Text(_displayValue, style: style);
            }

            // Slide: outgoing moves up, incoming slides in from below
            return Stack(
              children: [
                Transform.translate(
                  offset: Offset(0, -16 * t),
                  child: Text(_outgoingValue, style: style),
                ),
                Transform.translate(
                  offset: Offset(0, 16 * (1 - t)),
                  child: Text(_displayValue, style: style),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}
