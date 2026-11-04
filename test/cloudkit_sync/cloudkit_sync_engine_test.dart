import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:icloud_storage_plus/cloudkit_sync.dart';

import 'helpers.dart';

class _Delegate implements CloudKitSyncDelegate {
  final events = <CloudKitSyncEvent>[];
  Completer<void>? eventGate;
  Error? eventError;
  List<CloudKitPendingRecordZoneChange>? pendingChanges;
  CloudKitRecordZoneChangeBatch? batch;

  @override
  Future<void> handleEvent(CloudKitSyncEvent event) async {
    events.add(event);
    await eventGate?.future;
    if (eventError case final error?) throw error;
  }

  @override
  Future<CloudKitRecordZoneChangeBatch?> nextRecordZoneChangeBatch(
    List<CloudKitPendingRecordZoneChange> pendingChanges,
  ) async {
    this.pendingChanges = pendingChanges;
    return batch;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const engine = CloudKitSyncEngine('iCloud.com.example.app');
  const id = CloudKitRecordId(zoneName: 'Library', recordName: 'book-1');
  late _Delegate delegate;
  late List<MethodCall> nativeCalls;

  setUp(() async {
    nativeCalls = mockNative();
    delegate = _Delegate();
    await engine.start(
      delegate: delegate,
      stateSerialization: '{"saved":true}',
      excludedZoneNames: ['Blobs'],
    );
  });

  test('start passes the container, saved state, and excluded zones', () {
    expect(nativeCalls.single.method, 'start');
    expect(nativeCalls.single.arguments, {
      'containerId': 'iCloud.com.example.app',
      'stateSerialization': '{"saved":true}',
      'excludedZoneNames': ['Blobs'],
    });
  });

  test('pending changes are sent as typed saves and deletes', () async {
    await engine.addPendingRecordZoneChanges([
      const CloudKitPendingRecordSave(id),
      const CloudKitPendingRecordDelete(id),
    ]);
    await engine.addPendingDatabaseChanges([
      const CloudKitPendingZoneSave('Library'),
      const CloudKitPendingZoneDelete('Old'),
    ]);

    final idMap = {'zoneName': 'Library', 'recordName': 'book-1'};
    expect(nativeCalls[1].arguments, {
      'changes': [
        {'type': 'save', 'id': idMap},
        {'type': 'delete', 'id': idMap},
      ],
    });
    expect(nativeCalls[2].arguments, {
      'changes': [
        {'type': 'saveZone', 'zoneName': 'Library'},
        {'type': 'deleteZone', 'zoneName': 'Old'},
      ],
    });
  });

  test('native failures become CloudKitSyncException', () async {
    mockNative((call) async {
      throw PlatformException(
        code: 'nativeError',
        message: 'Quota exceeded',
        details: {'domain': 'CKErrorDomain', 'code': 25},
      );
    });

    await expectLater(
      engine.sendChanges(),
      throwsA(
        isA<CloudKitSyncException>()
            .having((e) => e.code, 'code', CloudKitSyncException.nativeError)
            .having((e) => e.nativeDomain, 'nativeDomain', 'CKErrorDomain')
            .having((e) => e.nativeCode, 'nativeCode', 25),
      ),
    );
  });

  test('the reply to an event waits until the delegate has handled it',
      () async {
    delegate.eventGate = Completer<void>();
    var replied = false;
    final reply = callFromNative('handleEvent', {
      'type': 'stateUpdate',
      'stateSerialization': '{}',
    }).then((_) => replied = true);
    await pumpEventQueue();

    expect(delegate.events.single, isA<CloudKitStateUpdate>());
    expect(replied, isFalse);

    delegate.eventGate!.complete();
    await reply;
    expect(replied, isTrue);
  });

  test('a delegate error is reported and replied as an error', () async {
    delegate.eventError = StateError('database closed');
    final reported = <FlutterErrorDetails>[];
    final previousOnError = FlutterError.onError;
    FlutterError.onError = reported.add;
    addTearDown(() => FlutterError.onError = previousOnError);

    await expectLater(
      callFromNative('handleEvent', {
        'type': 'stateUpdate',
        'stateSerialization': '{}',
      }),
      throwsA(isA<PlatformException>()),
    );
    expect(reported.single.exception, isA<StateError>());
  });

  test('a null batch replies null', () async {
    final reply = await callFromNative('nextRecordZoneChangeBatch', {
      'pendingChanges': [
        {
          'type': 'save',
          'id': {'zoneName': 'Library', 'recordName': 'book-1'},
        },
      ],
    });

    expect(reply, isNull);
    expect(delegate.pendingChanges, [const CloudKitPendingRecordSave(id)]);
  });

  test('a batch replies with its encoded records and deletes', () async {
    delegate.batch = CloudKitRecordZoneChangeBatch(
      recordsToSave: [
        CloudKitRecord(
          id: id,
          recordType: 'Book',
          fields: {
            'title': 'Tome',
            'pages': 320,
            'scale': 1.5,
            'tags': ['a'],
            'removed': null,
          },
          systemFields: Uint8List.fromList([7]),
        ),
      ],
      recordIdsToDelete: [
        const CloudKitRecordId(zoneName: 'Library', recordName: 'book-2'),
      ],
    );

    final reply = await callFromNative('nextRecordZoneChangeBatch', {
      'pendingChanges': <Object?>[],
    });

    expect(reply, {
      'recordsToSave': [
        {
          'id': {'zoneName': 'Library', 'recordName': 'book-1'},
          'recordType': 'Book',
          'fields': {
            'title': 'Tome',
            'pages': 320,
            'scale': 1.5,
            'tags': ['a'],
            'removed': null,
          },
          'assets': <String, Object?>{},
          'systemFields': Uint8List.fromList([7]),
        },
      ],
      'recordIDsToDelete': [
        {'zoneName': 'Library', 'recordName': 'book-2'},
      ],
    });
  });

  test('a batch with an unsupported field value replies an error', () async {
    FlutterError.onError = (_) {};
    addTearDown(() => FlutterError.onError = FlutterError.presentError);
    delegate.batch = const CloudKitRecordZoneChangeBatch(
      recordsToSave: [
        CloudKitRecord(id: id, recordType: 'Book', fields: {'read': true}),
      ],
    );

    await expectLater(
      callFromNative('nextRecordZoneChangeBatch', {
        'pendingChanges': <Object?>[],
      }),
      throwsA(
        isA<PlatformException>().having(
          (e) => e.message,
          'message',
          contains('fields[read]'),
        ),
      ),
    );
  });

  test('starting again sends events to the new delegate only', () async {
    final next = _Delegate();
    await engine.start(delegate: next, stateSerialization: null);

    await callFromNative('handleEvent', {
      'type': 'stateUpdate',
      'stateSerialization': '{}',
    });

    expect(delegate.events, isEmpty);
    expect(next.events, hasLength(1));
  });
}
