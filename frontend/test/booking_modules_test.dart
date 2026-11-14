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
import 'package:bleiben/features/bookings/bookings_api.dart';
import 'package:bleiben/features/host/host_control_center.dart';

const _all = [
  'org.read', 'properties.read', 'properties.write', 'calendar.read', 'calendar.write', 'bookings.read', 'bookings.write',
  'bookings.cancel', 'expenses.read', 'expenses.write', 'dashboard.read', 'messages.read', 'messages.write',
];

String _d(int n) => ymd(DateTime.now().add(Duration(days: n)));

Map<String, dynamic> _booking({String status = 'confirmed'}) => {
      'id': 7,
      'code': 'BLB-ABC123',
      'status': status,
      'trip_status': 'upcoming',
      'source': 'phone',
      'source_label': 'Phone',
      'property': {'id': 1, 'title': 'Pine Cottage'},
      'room': {'id': 11, 'name': 'Deluxe'},
      'check_in': _d(1),
      'check_out': _d(3),
      'nights': 2,
      'guest': {'name': 'Ravi Kumar', 'phone': '+91 98111 11111', 'email': ''},
      'adults': 2,
      'children': 0,
      'total': 8000,
      'paid': 3000,
      'balance': 5000,
      'payment_status': 'partial',
      'payments': [
        {'amount': 3000, 'method': 'upi', 'kind': 'payment', 'at': '2026-11-14T10:00:00Z', 'by': 'Asha Rao'}
      ],
      'events': [
        {'at': '2026-11-14T10:00:00Z', 'by': 'Asha Rao', 'action': 'created', 'detail': 'Phone'}
      ],
      'notes': '',
      'booked_at': '2026-11-14T10:00:00Z',
    };

class FakeHostApi {
  final requests = <String>[];
  final bodies = <String, Map<String, dynamic>>{};

  late final client = MockClient((req) async {
    final path = req.url.path;
    requests.add('${req.method} ${req.url}');
    final body = req.body.isEmpty ? <String, dynamic>{} : jsonDecode(req.body) as Map<String, dynamic>;
    bodies['${req.method} $path'] = body;
    http.Response json(Object data, [int status = 200]) =>
        http.Response(jsonEncode(data), status, headers: {'content-type': 'application/json; charset=utf-8'});

    switch ((req.method, path)) {
      case ('GET', '/api/auth/me'):
        return json({
          'id': 1,
          'name': 'Asha Rao',
          'email': 'asha@example.com',
          'memberships': [
            {'org_id': 1, 'org_name': 'Asha Stays', 'role': 'owner', 'permissions': _all}
          ],
        });
      case ('GET', '/api/properties'):
        return json([
          {'id': 1, 'title': 'Pine Cottage', 'status': 'activated', 'room_count': 1, 'unit_count': 2}
        ]);
      case ('GET', '/api/properties/1'):
        return json({
          'id': 1,
          'title': 'Pine Cottage',
          'rooms': [
            {'id': 11, 'name': 'Deluxe', 'max_guests': 3}
          ]
        });
      case ('GET', '/api/calendar'):
        final days = [for (var i = 0; i < 15; i++) _d(i)];
        return json({
          'from': days.first,
          'to': days.last,
          'days': days,
          'total_properties': 1,
          'properties': [
            {
              'id': 1,
              'serial_id': 'HH-P-AAA111',
              'title': 'Pine Cottage',
              'city': 'Manali',
              'rooms': [
                {
                  'id': 11,
                  'name': 'Deluxe',
                  'units': 2,
                  'max_guests': 3,
                  'base_price': 4000,
                  'occupancy': 13,
                  'cells': [
                    for (final (i, d) in days.indexed)
                      {
                        'date': d,
                        'price': i == 4 ? 5000 : 4000,
                        'custom_price': i == 4,
                        'units': 2,
                        'booked': i == 1 || i == 2 ? 1 : 0,
                        'blocked': i == 6,
                        'block_reason': i == 6 ? 'Maintenance' : null,
                        'available': i == 6 ? 0 : (i == 1 || i == 2 ? 1 : 2),
                      }
                  ],
                  'bookings': [
                    {'id': 7, 'code': 'BLB-ABC123', 'guest_name': 'Ravi Kumar', 'guests': 2, 'source': 'phone', 'status': 'confirmed', 'check_in': _d(1), 'check_out': _d(3), 'balance': 5000}
                  ],
                }
              ],
            }
          ],
        });
      case ('POST', '/api/calendar/blocks'):
        return json({'blocked': 1}, 201);
      case ('GET', '/api/bookings'):
        return json({
          'items': [_booking()],
          'total': 1,
          'page': 1,
          'page_size': 25,
          'counts': {'all': 1, 'upcoming': 1, 'arriving_soon': 1, 'pending_payment': 1, 'offline': 1},
        });
      case ('GET', '/api/bookings/7'):
        return json(_booking());
      case ('POST', '/api/bookings/7/cancel'):
        return json({..._booking(status: 'cancelled'), 'cancel_reason': body['reason']});
      case ('GET', '/api/dashboard'):
        return json({
          'today': _d(0),
          'range': {'period': 'last_30', 'from': _d(-29), 'to': _d(0), 'days': 30, 'count_by': 'check_in', 'compare': {'from': _d(-59), 'to': _d(-30)}},
          'filters': {
            'cities': ['Manali'],
            'properties': [
              {'id': 1, 'title': 'Pine Cottage', 'city': 'Manali'}
            ]
          },
          'totals': {'properties': 1, 'units': 2},
          'kpis': {
            'revenue': {'value': 12000, 'stay': 11000, 'extras': 1000, 'change': 34.4},
            'expenses': {'value': 4000, 'pct_of_revenue': 33.3, 'change': -5},
            'noi': {'value': 8000, 'margin': 66.7, 'change': 4.5},
            'occupancy': {'value': 25, 'booked_nights': 15, 'available_nights': 60, 'change_pts': 2.4},
            'adr': {'value': 4000, 'change': -14.8},
            'revpar': {'value': 200, 'change': 40.9},
            'bookings': {'value': 3, 'change': null},
          },
          'today_panel': {
            'check_ins': {
              'count': 1,
              'items': [
                {'id': 7, 'code': 'BLB-ABC123', 'guest_name': 'Ravi Kumar', 'source_label': 'Phone', 'status': 'confirmed', 'check_in': _d(0), 'check_out': _d(2), 'source': 'phone'}
              ]
            },
            'check_outs': {'count': 0, 'items': []},
            'ongoing': {'count': 0, 'items': []},
            'arriving_soon': {'count': 0, 'items': []},
          },
          'sources': [
            {'source': 'direct', 'label': 'Bleiben Direct', 'bookings': 2, 'nights': 4, 'revenue': 9000, 'share_nights': 66.7, 'share_revenue': 75, 'adr': 2250, 'offline': false, 'saved_commission': 1350},
            {'source': 'airbnb', 'label': 'Airbnb', 'bookings': 1, 'nights': 2, 'revenue': 3000, 'share_nights': 33.3, 'share_revenue': 25, 'adr': 1500, 'offline': false, 'saved_commission': 0},
          ],
          'money': [
            {'category': 'Rent', 'amount': 3000, 'share': 75},
            {'category': 'Laundry', 'amount': 1000, 'share': 25},
          ],
          'properties': [
            {'id': 1, 'title': 'Pine Cottage', 'city': 'Manali', 'revenue': 12000, 'occupancy': 25, 'adr': 4000, 'expenses': 4000, 'expense_pct': 33.3, 'bookings': 3}
          ],
          'monthly': {
            'year': 2026,
            'years': [2026],
            'months': [for (var m = 1; m <= 12; m++) {'month': '2026-${m.toString().padLeft(2, '0')}', 'revenue': m * 1000, 'expenses': m * 300, 'noi': m * 700, 'margin': 70}],
          },
          'outlook': [
            for (var w = 0; w < 13; w++)
              {'from': _d(w * 7), 'to': _d(w * 7 + 6), 'booked_nights': 3, 'offered_nights': 14, 'pct': 21.4, 'band': w == 0 ? 'high' : 'low'}
          ],
          'alerts': [
            {'kind': 'balance_due', 'count': 1, 'text': '1 arriving guest has a balance to collect'}
          ],
        });
      case ('GET', '/api/expenses/meta'):
        return json({
          'categories': ['Rent', 'Laundry', 'Other'],
          'payment_modes': {'cash': 'Cash', 'upi': 'UPI'},
          'export_max': 5000
        });
      case ('GET', '/api/expenses'):
        return json({
          'items': [
            {
              'id': 3,
              'date': _d(0),
              'property': {'id': 1, 'title': 'Pine Cottage', 'city': 'Manali'},
              'payment_mode': 'upi',
              'payment_mode_label': 'UPI',
              'notes': '',
              'attachments': [],
              'lines': [
                {'index': 0, 'category': 'Rent', 'amount': 30000, 'note': '', 'rule_id': 1, 'skipped': false}
              ],
              'total': 30000,
              'repeats_monthly': true,
              'skipped': false,
              'auto_filed': true,
              'added_by': 'Auto-filed',
              'added_on': '2026-11-01T00:00:00Z',
            }
          ],
          'total': 1,
          'sum': 30000,
          'page': 1,
          'page_size': 25,
          'has_any': true,
        });
      case ('POST', '/api/expenses'):
        return json({'id': 4}, 201);
      case ('GET', '/api/messages'):
        return json({
          'items': [
            {
              'id': 5,
              'guest_name': 'Ravi Kumar',
              'channel': 'airbnb',
              'channel_label': 'Airbnb',
              'property': {'id': 1, 'title': 'Pine Cottage'},
              'booking': {'id': 7, 'code': 'BLB-ABC123', 'status': 'confirmed', 'check_in': _d(1), 'check_out': _d(3)},
              'stage': 'upcoming',
              'last_message': {'body': 'Can we check in early?', 'direction': 'in', 'at': '2026-11-14T10:00:00Z'},
              'last_message_at': '2026-11-14T10:00:00Z',
              'waiting_since': '2026-11-14T10:00:00Z',
              'unread': true,
              'starred': false,
              'priority': false,
              'archived': false,
            }
          ],
          'total': 1,
          'stages': ['upcoming'],
          'channels': {'airbnb': 'Airbnb'},
        });
      case ('GET', '/api/messages/unread-count'):
        return json({'count': 1});
      case ('GET', '/api/messages/quick-replies'):
        return json({'starter': [], 'own': [], 'variables': []});
      case ('POST', '/api/messages/5/state'):
        return json({'read_at': '2026-11-14T10:01:00Z'});
      case ('GET', '/api/messages/5'):
        return json({
          'id': 5,
          'guest_name': 'Ravi Kumar',
          'channel': 'airbnb',
          'channel_label': 'Airbnb',
          'property': {'id': 1, 'title': 'Pine Cottage'},
          'booking': {'id': 7, 'code': 'BLB-ABC123', 'status': 'confirmed', 'check_in': _d(1), 'check_out': _d(3)},
          'stage': 'upcoming',
          'starred': false,
          'priority': false,
          'archived': false,
          'unread': false,
          'messages': [
            {'id': 'a', 'direction': 'in', 'body': 'Can we check in early?', 'at': '2026-11-14T10:00:00Z', 'by': 'Ravi Kumar'}
          ],
          'note': null,
          'scheduled': [],
          'details': {'guest': {'name': 'Ravi Kumar', 'phone': '', 'email': ''}, 'adults': 2, 'children': 0, 'nights': 2, 'total': 8000, 'paid': 3000, 'balance': 5000, 'payout_note': null},
          'property_info': [
            {'label': 'Check-in time', 'value': '1 PM'}
          ],
        });
      case ('POST', '/api/messages/5/messages'):
        return json({'message': {}, 'total': 2}, 201);
    }
    return json({'detail': 'not found'}, 404);
  });
}

Future<FakeHostApi> pumpSection(WidgetTester tester, String section) async {
  GoogleFonts.config.allowRuntimeFetching = false;
  SharedPreferences.setMockInitialValues({'bleiben_token': 'tok', 'bleiben_active_org': 1});
  tester.view.physicalSize = const Size(1500, 1000);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final fake = FakeHostApi();
  final session = SessionStore();
  await session.load();
  final api = ApiClient(session: session, httpClient: fake.client);
  final auth = AuthController(api: api, session: session);
  await auth.loadProfile();
  await tester.pumpWidget(MaterialApp(home: HostControlCenterScreen(auth: auth, api: api, initialSection: section)));
  await tester.pumpAndSettle();
  return fake;
}

void main() {
  testWidgets('calendar: grid shows prices, blocks and booking bars; a selection can be blocked', (tester) async {
    final fake = await pumpSection(tester, 'calendar');
    expect(find.text('Deluxe'), findsWidgets);
    expect(find.text('Blocked'), findsWidgets);
    expect(find.textContaining('Ravi Kumar'), findsOneWidget);
    expect(find.text('₹5,000'), findsOneWidget);

    await tester.tap(find.byKey(Key('cell-11-${_d(8)}')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(Key('cell-11-${_d(9)}')));
    await tester.pumpAndSettle();
    expect(find.textContaining('2 days'), findsOneWidget);
    await tester.tap(find.byKey(const Key('block-dates')));
    await tester.pumpAndSettle();
    final sent = fake.bodies['POST /api/calendar/blocks']!;
    expect(sent['room_ids'], [11]);
    expect(sent['from'], _d(8));
    expect(sent['to'], _d(9));
    expect(sent['reason'], 'Maintenance');
  });

  testWidgets('reservations: tabs with counts, row opens detail, cancel needs a reason', (tester) async {
    final fake = await pumpSection(tester, 'reservations');
    expect(find.text('Upcoming (1)'), findsOneWidget);
    expect(find.text('BLB-ABC123'), findsOneWidget);
    expect(find.text('Part paid'), findsOneWidget);

    await tester.tap(find.text('BLB-ABC123'));
    await tester.pumpAndSettle();
    expect(find.text('Ravi Kumar · BLB-ABC123'), findsOneWidget);
    expect(find.text('Record payment'), findsOneWidget);

    await tester.tap(find.byKey(const Key('cancel-booking')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('reason-field')), 'Guest changed plans');
    await tester.tap(find.byKey(const Key('reason-confirm')));
    await tester.pumpAndSettle();
    expect(fake.bodies['POST /api/bookings/7/cancel']!['reason'], 'Guest changed plans');
    expect(find.text('Cancelled'), findsWidgets);
  });

  testWidgets('dashboard: KPIs with comparison, today column, sources, money, alerts', (tester) async {
    await pumpSection(tester, 'dashboard');
    expect(find.textContaining('Asha'), findsWidgets);
    expect(find.text('₹12,000'), findsWidgets);
    expect(find.text('↑34.4%'), findsOneWidget);
    expect(find.text('15 of 60 nights'), findsOneWidget);
    expect(find.text('66.7% margin'), findsOneWidget);
    expect(find.text('1 arriving guest has a balance to collect'), findsOneWidget);
    expect(find.text("Today's check-ins"), findsOneWidget);
    expect(find.text('₹1,350 saved in commission'), findsOneWidget);
    expect(find.text('Where money goes'), findsOneWidget);
    expect(find.text('Occupancy outlook'), findsOneWidget);
  });

  testWidgets('expenses: list shows repeat badges; adding an entry posts its lines', (tester) async {
    final fake = await pumpSection(tester, 'expenses');
    expect(find.text('Repeats monthly'), findsOneWidget);
    expect(find.text('Auto-filed'), findsOneWidget);
    expect(find.text('1 entry · ₹30,000'), findsOneWidget);

    await tester.tap(find.byKey(const Key('add-expense')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('line-category-0')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Laundry').last);
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('line-amount-0')), '1200');
    await tester.tap(find.byKey(const Key('save-expense')));
    await tester.pumpAndSettle();
    final sent = fake.bodies['POST /api/expenses']!;
    expect(sent['property_id'], 1);
    expect((sent['lines'] as List).single, {'category': 'Laundry', 'amount': 1200.0, 'note': ''});
  });

  testWidgets('messages: unread badge, open a conversation, reply', (tester) async {
    final fake = await pumpSection(tester, 'inbox');
    expect(find.text('Ravi Kumar'), findsWidgets);
    expect(find.text('1'), findsWidgets); // unread badge on the nav

    await tester.tap(find.byKey(const Key('thread-5')));
    await tester.pumpAndSettle();
    expect(find.text('Can we check in early?'), findsWidgets);
    expect(find.text('Team note'), findsOneWidget);
    expect(find.text('Your payout ₹8,000 before taxes'), findsOneWidget);

    await tester.enterText(find.byKey(const Key('composer')), 'Hi {guest_first_name}, yes!');
    await tester.tap(find.byKey(const Key('send-message')));
    await tester.pumpAndSettle();
    expect(fake.bodies['POST /api/messages/5/messages'], {'body': 'Hi {guest_first_name}, yes!', 'direction': 'out'});
    expect(fake.requests.where((r) => r == 'POST http://127.0.0.1:8000/api/messages/5/state' || r.endsWith('/api/messages/5/state')), isNotEmpty);
  });
}
