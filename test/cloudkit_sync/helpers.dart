import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

const cloudKitChannel = MethodChannel('icloud_storage_plus/cloudkit_sync');

/// Sends a native-to-Dart call on the CloudKit sync channel and returns the
/// decoded reply, or throws the reply's [PlatformException].
Future<Object?> callFromNative(String method, Object? arguments) async {
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  ByteData? reply;
  await messenger.handlePlatformMessage(
    cloudKitChannel.name,
    cloudKitChannel.codec.encodeMethodCall(MethodCall(method, arguments)),
    (data) => reply = data,
  );
  return cloudKitChannel.codec.decodeEnvelope(reply!);
}

/// Records Dart-to-native calls and answers them with [reply].
List<MethodCall> mockNative([
  Future<Object?> Function(MethodCall call)? reply,
]) {
  final calls = <MethodCall>[];
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(cloudKitChannel, (call) async {
    calls.add(call);
    return reply?.call(call);
  });
  return calls;
}

Map<String, Object?> recordMap({
  String recordName = 'book-1',
  Map<String, Object?> fields = const {},
}) =>
    {
      'id': {'zoneName': 'Library', 'recordName': recordName},
      'recordType': 'Book',
      'fields': fields,
      'assets': <String, String>{},
      'systemFields': Uint8List.fromList([1, 2, 3]),
    };
