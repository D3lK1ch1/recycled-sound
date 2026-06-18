import 'dart:typed_data';

/// Detects when the camera view has come to rest.
///
/// This is the cheap, always-on TRIGGER for the "motion-stop → segment →
/// identify" capture pipeline (Option D). The heavy work — segmentation, OCR,
/// visual match, colour — fires exactly once, when the hearing aid stops
/// moving, so it never competes with the live frame loop for budget. A
/// stationary frame is also sharp by construction, which sidesteps the
/// motion-blur risk that haunted the sweep-video approach.
///
/// Pure Dart, no camera/platform dependency: feed it the primary image plane of
/// each frame ([CameraImage.planes[0].bytes] — the luma plane on Android NV21,
/// the interleaved BGRA buffer on iOS) and it reports [isStill] once the
/// inter-frame change stays at/below [stillThreshold] for [stillFrames]
/// consecutive frames. Because it only diffs a strided down-sample, the cost is
/// a few thousand byte subtractions per frame regardless of resolution.
///
/// Format-agnostic by design: it never interprets the bytes as pixels, only as
/// a change signal. Motion perturbs the buffer whatever the channel layout, so
/// the same code works for NV21 luma and BGRA alike. If a sharper signal is
/// wanted later (e.g. gyro/IMU fusion), swap the source feeding [push] — the
/// trigger semantics ([isStill]/[reset]) stay put.
class StillnessDetector {
  StillnessDetector({
    this.stride = 64,
    this.stillThreshold = 6.0,
    this.stillFrames = 5,
  })  : assert(stride > 0),
        assert(stillThreshold >= 0),
        assert(stillFrames > 0);

  /// Sample every [stride]th byte of the plane. Larger = cheaper, coarser.
  final int stride;

  /// Mean absolute inter-frame difference at/below which a frame counts as
  /// "not moving" (0–255 byte scale).
  final double stillThreshold;

  /// Consecutive sub-threshold frames required before declaring stillness.
  final int stillFrames;

  Uint8List? _prevSamples;
  int _stillStreak = 0;
  bool _isStill = false;

  /// Whether the view is currently judged to be at rest.
  bool get isStill => _isStill;

  /// The most recent mean-absolute-difference reading. [double.infinity] before
  /// the first comparable frame. Useful for tuning [stillThreshold] from logs.
  double get lastDelta => _lastDelta;
  double _lastDelta = double.infinity;

  /// Feed one frame's primary-plane bytes. Returns the current [isStill] state.
  ///
  /// The first call (and any call where the buffer length changes — a
  /// resolution or format switch) can't be diffed, so it resets the streak and
  /// returns false.
  bool push(Uint8List bytes) {
    final samples = _downsample(bytes);
    final prev = _prevSamples;
    _prevSamples = samples;

    if (prev == null || prev.length != samples.length) {
      _stillStreak = 0;
      _isStill = false;
      _lastDelta = double.infinity;
      return false;
    }

    var sum = 0;
    for (var i = 0; i < samples.length; i++) {
      final d = samples[i] - prev[i];
      sum += d < 0 ? -d : d;
    }
    final delta = sum / samples.length;
    _lastDelta = delta;

    if (delta <= stillThreshold) {
      _stillStreak++;
      if (_stillStreak >= stillFrames) _isStill = true;
    } else {
      _stillStreak = 0;
      _isStill = false;
    }
    return _isStill;
  }

  /// Clear all state. Call after a capture fires so the *next* time the object
  /// comes to rest is treated as a fresh trigger rather than re-firing on the
  /// same stationary device.
  void reset() {
    _prevSamples = null;
    _stillStreak = 0;
    _isStill = false;
    _lastDelta = double.infinity;
  }

  /// Copy out a strided down-sample. We snapshot the samples (rather than hold a
  /// reference to [bytes]) because camera plugins may recycle the underlying
  /// frame buffer between callbacks — aliasing the previous frame would make
  /// every diff read as zero and falsely report stillness.
  Uint8List _downsample(Uint8List bytes) {
    if (bytes.isEmpty) return Uint8List(0);
    final count = ((bytes.length - 1) ~/ stride) + 1;
    final out = Uint8List(count);
    var j = 0;
    for (var i = 0; i < bytes.length; i += stride) {
      out[j++] = bytes[i];
    }
    return out;
  }
}
