import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:markethub/main.dart';

// Deep-link routing decides what a shared pakbazar24.com link opens. The
// failure modes are quiet ones — a link that silently drops the user on Home,
// or a malformed URL that throws during route generation — so the parsing is
// pinned here.

String? _listingIdFor(String route) => listingIdFromRoute(route);

void main() {
  group('generateAppRoute', () {
    test('opens a listing from a bare path', () {
      expect(_listingIdFor('/ad/abc123'), 'abc123');
    });

    test('opens a listing from a full https URL', () {
      expect(_listingIdFor('https://pakbazar24.com/ad/abc123'), 'abc123');
    });

    test('opens a listing from the www host', () {
      expect(_listingIdFor('https://www.pakbazar24.com/ad/abc123'), 'abc123');
    });

    // The custom scheme puts the first segment in the URI's host, not its
    // path — pakbazar://ad/xyz parses as host 'ad', path '/xyz'.
    test('opens a listing from the custom scheme', () {
      expect(_listingIdFor('pakbazar://ad/xyz789'), 'xyz789');
    });

    test('ignores a trailing slash', () {
      expect(_listingIdFor('/ad/abc123/'), 'abc123');
    });

    test('ignores query and fragment', () {
      expect(_listingIdFor('/ad/abc123?utm_source=whatsapp#top'), 'abc123');
    });

    // Anything unrecognised must return null so MaterialApp falls back to
    // `home`. Returning a route here would strand the user on a blank screen.
    test('falls back to home for unknown, empty and malformed routes', () {
      for (final route in <String>[
        '/',
        '',
        '/ad',
        '/ad/',
        '/unknown/path',
        '/adx/abc123',
        'https://pakbazar24.com/',
      ]) {
        expect(
          listingIdFromRoute(route),
          isNull,
          reason: 'route "$route" should not resolve to a listing',
        );
        expect(generateAppRoute(RouteSettings(name: route)), isNull);
      }
    });

    test('never throws on hostile input', () {
      for (final route in <String>[
        '://',
        '/ad/%%%',
        'not a url at all',
        '/ad/' * 40,
      ]) {
        expect(() => listingIdFromRoute(route), returnsNormally);
      }
    });
  });

  group('listingShareUrl', () {
    test('points at the ad, not the site root', () {
      expect(listingShareUrl('abc123'), 'https://pakbazar24.com/ad/abc123');
    });

    // A blank id must not produce ".../ad/", which would deep-link to a
    // guaranteed dead end.
    test('falls back to the site root for a blank id', () {
      expect(listingShareUrl(''), 'https://pakbazar24.com');
      expect(listingShareUrl('   '), 'https://pakbazar24.com');
    });

    test('round-trips through the route parser', () {
      expect(_listingIdFor(listingShareUrl('round-trip-id')), 'round-trip-id');
    });
  });
}
