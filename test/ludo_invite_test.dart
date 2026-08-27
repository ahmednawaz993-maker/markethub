import 'package:flutter_test/flutter_test.dart';
import 'package:markethub/main.dart';

// An invite link is handled by a stranger's phone, pasted out of a WhatsApp
// group, possibly mangled on the way. The parser has to be strict about what it
// accepts and must never confuse a Ludo link with an ad link — landing someone
// on the wrong screen from a shared link is the failure that makes people stop
// sharing them.

void main() {
  group('invite links parse', () {
    test('the https forms used in shares', () {
      expect(ludoRoomIdFromRoute('https://pakbazar24.com/ludo/abc123'), 'abc123');
      expect(
        ludoRoomIdFromRoute('https://www.pakbazar24.com/ludo/abc123'),
        'abc123',
      );
      expect(ludoRoomIdFromRoute('/ludo/abc123'), 'abc123');
    });

    // pakbazar://ludo/x parses with 'ludo' as the HOST, not a path segment —
    // the same trap the ad links hit, which is why they share a parser.
    test('the custom scheme, where the first segment is the host', () {
      expect(ludoRoomIdFromRoute('pakbazar://ludo/abc123'), 'abc123');
    });

    test('trailing slashes and query strings survive', () {
      expect(ludoRoomIdFromRoute('https://pakbazar24.com/ludo/abc123/'), 'abc123');
      expect(
        ludoRoomIdFromRoute('https://pakbazar24.com/ludo/abc123?from=whatsapp'),
        'abc123',
      );
    });

    test('junk is refused rather than guessed at', () {
      for (final bad in [
        '',
        '/',
        '/ludo',
        '/ludo/',
        'https://pakbazar24.com/',
        'not a url at all',
      ]) {
        expect(ludoRoomIdFromRoute(bad), isNull, reason: bad);
      }
    });

    // The two link types must not bleed into each other.
    test('an ad link is not a ludo link, and the reverse', () {
      expect(ludoRoomIdFromRoute('https://pakbazar24.com/ad/xyz'), isNull);
      expect(listingIdFromRoute('https://pakbazar24.com/ludo/abc'), isNull);
      expect(listingIdFromRoute('https://pakbazar24.com/ad/xyz'), 'xyz');
    });
  });

  group('the shareable url', () {
    test('round-trips through the parser', () {
      const id = 'Ab3XyZ90qLmN';
      expect(ludoRoomIdFromRoute(ludoInviteUrl(id)), id);
    });

    test('is an https link so it opens from any chat app', () {
      expect(ludoInviteUrl('r1'), startsWith('https://'));
      expect(ludoInviteUrl('r1'), contains('/ludo/'));
    });
  });
}
