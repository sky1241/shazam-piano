import 'dart:typed_data';
import 'package:flutter/services.dart';
import 'package:record_platform_interface/record_platform_interface.dart';

/// Stub implementation for record_linux
/// This is a workaround for compilation issues on Windows/Android builds
class RecordLinux extends RecordPlatform {
  static const MethodChannel _channel = MethodChannel('record_linux');

  @override
  Future<bool> hasPermission() async {
    throw UnimplementedError('record_linux is not supported on this platform');
  }

  @override
  Future<void> start(RecordConfig config, {String? path}) async {
    throw UnimplementedError('record_linux is not supported on this platform');
  }

  @override
  Future<String?> stop() async {
    throw UnimplementedError('record_linux is not supported on this platform');
  }

  @override
  Future<void> pause() async {
    throw UnimplementedError('record_linux is not supported on this platform');
  }

  @override
  Future<void> resume() async {
    throw UnimplementedError('record_linux is not supported on this platform');
  }

  @override
  Future<bool> isPaused() async {
    throw UnimplementedError('record_linux is not supported on this platform');
  }

  @override
  Future<bool> isRecording() async {
    throw UnimplementedError('record_linux is not supported on this platform');
  }

  @override
  Future<void> dispose() async {
    // No-op
  }

  @override
  Future<Amplitude> getAmplitude() async {
    throw UnimplementedError('record_linux is not supported on this platform');
  }

  @override
  Future<bool> isEncoderSupported(AudioEncoder encoder) async {
    return false;
  }

  @override
  Future<Stream<Uint8List>> startStream(String recorderId, RecordConfig config) async {
    throw UnimplementedError('record_linux is not supported on this platform');
  }
}
