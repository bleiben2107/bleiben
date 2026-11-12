import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:bleiben/core/network/api_client.dart';
import 'package:bleiben/core/storage/session_store.dart';
import 'package:bleiben/features/auth/auth_controller.dart';
import 'package:bleiben/features/host/host_control_center.dart';

/// In-memory stand-in for /api/auth/me and /api/properties/*.
class FakePropertiesApi {
  FakePropertiesApi({this.role = 'owner'});

  final String role;
  final requests = <String>[];
  Map<String, dynamic>? lastRoomBody;

  final properties = <Map<String, dynamic>>[
    {
      'id': 1,
      'propertySerialId': 'HH-P-AAA111',
      'title': 'Pine Cottage',
      'city': 'Manali',
      'location': 'Mall Road, Manali',
      'status': 'draft',
      'propertyType': 'Cottage',
      'basePrice': 4500,
      'capacity': {'guests': 4},
      'room_count': 0,
      'unit_count': 0,
      'booking_url': null,
    },
    {
      'id': 2,
      'propertySerialId': 'HH-P-BBB222',
      'title': 'Goa Beach House',
      'city': 'Goa',
      'status': 'activated',
      'basePrice': 9000,
      'room_count': 1,
      'unit_count': 1,
      'booking_url': 'http://127.0.0.1:5180/p/goa-beach-house',
    },
  ];
  final rooms = <Map<String, dynamic>>[];

  List<String> get permissions => role == 'read_only'
      ? ['org.read', 'properties.read']
      : ['org.read', 'properties.read', 'properties.write', 'properties.publish'];

  Map<String, dynamic> _detail(Map<String, dynamic> p) => {
        ...p,
        'rooms': [for (final r in rooms) r],
        'room_count': rooms.length,
        'unit_count': rooms.fold<int>(0, (n, r) => n + (r['unit_count'] as int)),
      };

  late final client = MockClient((req) async {
    final path = req.url.path;
    requests.add('${req.method} ${req.url}');
    final body = req.body.isEmpty ? <String, dynamic>{} : jsonDecode(req.body) as Map<String, dynamic>;
    http.Response json(Object data, [int status = 200]) =>
        http.Response(jsonEncode(data), status, headers: {'content-type': 'application/json'});

    if (path == '/api/auth/me') {
      return json({
        'id': 1,
        'name': 'Asha Rao',
        'email': 'asha@example.com',
        'memberships': [
          {'org_id': 1, 'org_name': 'Asha Rao', 'role': role, 'permissions': permissions}
        ],
      });
    }
    if (req.method == 'GET' && path == '/api/properties') {
      final q = (req.url.queryParameters['q'] ?? '').toLowerCase();
      final status = req.url.queryParameters['status'];
      return json([
        for (final p in properties)
          if ((q.isEmpty || '${p['title']} ${p['city']}'.toLowerCase().contains(q)) &&
              (status == null || p['status'] == status))
            p
      ]);
    }
    if (req.method == 'GET' && path == '/api/properties/1') return json(_detail(properties[0]));
    if (req.method == 'GET' && path == '/api/properties/1/activity') {
      return json([
        {'action': 'created_draft', 'user_name': 'Asha Rao', 'at': '2026-11-12T10:00:00Z'}
      ]);
    }
    if (req.method == 'POST' && path == '/api/properties/1/rooms') {
      lastRoomBody = body;
      final room = {
        'id': rooms.length + 1,
        ...body,
        'max_guests': (body['max_adults'] as int) + (body['max_children'] as int),
        'effective_price': body['base_price'] ?? 4500,
        'status': 'active',
      };
      rooms.add(room);
      return json(room, 201);
    }
    if (req.method == 'POST' && path == '/api/properties/1/publish') {
      properties[0] = {
        ...properties[0],
        'status': 'activated',
        'booking_url': 'http://127.0.0.1:5180/p/pine-cottage',
      };
      return json({'ok': true, 'property': properties[0]});
    }
    return json({'detail': 'not found'}, 404);
  });
}

Future<FakePropertiesApi> pumpHost(WidgetTester tester, {String role = 'owner'}) async {
  GoogleFonts.config.allowRuntimeFetching = false;
  SharedPreferences.setMockInitialValues({'bleiben_token': 'tok'});
  tester.view.physicalSize = const Size(1280, 900);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final fake = FakePropertiesApi(role: role);
  final session = SessionStore();
  await session.load();
  final api = ApiClient(session: session, httpClient: fake.client);
  final auth = AuthController(api: api, session: session);
  await auth.loadProfile();
  await tester.pumpWidget(MaterialApp(home: HostControlCenterScreen(auth: auth, api: api)));
  await tester.pumpAndSettle();
  return fake;
}

void main() {
  testWidgets('shell shows the MVP nav and unbuilt sections say what is coming', (tester) async {
    await pumpHost(tester);
    for (final label in ['Dashboard', 'Calendar', 'Properties', 'Reservations', 'Channel Manager', 'Notifications']) {
      expect(find.text(label), findsWidgets);
    }
    // Properties is the landing section.
    expect(find.text('Pine Cottage'), findsOneWidget);
    expect(find.text('Goa Beach House'), findsOneWidget);

    await tester.tap(find.text('Calendar'));
    await tester.pumpAndSettle();
    expect(find.text('Coming next in this release'), findsOneWidget);
    expect(find.text('15-minute holds and overlap prevention'), findsOneWidget);
  });

  testWidgets('all properties: search and status filter call the API', (tester) async {
    final fake = await pumpHost(tester);
    expect(find.text('Draft'), findsWidgets);
    expect(find.text('Published'), findsWidgets);

    await tester.enterText(find.byKey(const Key('property-search')), 'manali');
    await tester.testTextInput.receiveAction(TextInputAction.search);
    await tester.pumpAndSettle();
    expect(fake.requests.last, contains('q=manali'));
    expect(find.text('Goa Beach House'), findsNothing);
    expect(find.text('Pine Cottage'), findsOneWidget);
  });

  testWidgets('property details: add a room, then publish to get the booking link', (tester) async {
    final fake = await pumpHost(tester);
    await tester.tap(find.text('Pine Cottage'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Not live yet'), findsOneWidget);

    await tester.tap(find.widgetWithText(Tab, 'Rooms & units'));
    await tester.pumpAndSettle();
    expect(find.textContaining('No rooms yet'), findsOneWidget);

    await tester.tap(find.text('Add room'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(find.text('Room name is required'), findsOneWidget);

    await tester.enterText(find.byKey(const Key('room-name')), 'Deluxe Room');
    await tester.enterText(find.byKey(const Key('room-units')), '3');
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(fake.lastRoomBody?['name'], 'Deluxe Room');
    expect(fake.lastRoomBody?['unit_count'], 3);
    expect(fake.lastRoomBody?['base_price'], isNull, reason: 'empty price inherits the property price');
    expect(find.text('Deluxe Room'), findsOneWidget);
    expect(find.textContaining('3 units'), findsOneWidget);

    await tester.tap(find.text('Publish'));
    await tester.pumpAndSettle();
    expect(fake.requests.where((r) => r.startsWith('POST') && r.endsWith('/api/properties/1/publish')), hasLength(1));

    await tester.tap(find.text('Overview'));
    await tester.pumpAndSettle();
    expect(find.text('http://127.0.0.1:5180/p/pine-cottage'), findsOneWidget);
    expect(find.text('Unpublish'), findsOneWidget);

    await tester.tap(find.text('Activity'));
    await tester.pumpAndSettle();
    expect(find.text('Created the draft'), findsOneWidget);
  });

  testWidgets('read-only members can browse but not create, edit or publish', (tester) async {
    await pumpHost(tester, role: 'read_only');
    expect(find.text('Create new listing'), findsNothing);
    await tester.tap(find.text('Pine Cottage'));
    await tester.pumpAndSettle();
    expect(find.text('Publish'), findsNothing);
    expect(find.text('Continue setup'), findsNothing);
    await tester.tap(find.widgetWithText(Tab, 'Rooms & units'));
    await tester.pumpAndSettle();
    expect(find.text('Add room'), findsNothing);
  });
}
