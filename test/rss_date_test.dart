import 'package:flutter_test/flutter_test.dart';
import 'package:tn/src/rss.dart';

void main() {
  group('RssService.parseDate', () {
    test('RFC 822 with numeric zone offset', () {
      expect(
        RssService.parseDate('Tue, 03 Jun 2008 15:00:00 +0000'),
        DateTime.utc(2008, 6, 3, 15).millisecondsSinceEpoch,
      );
      expect(
        RssService.parseDate('Tue, 03 Jun 2008 15:00:00 +0300'),
        DateTime.utc(2008, 6, 3, 12).millisecondsSinceEpoch,
      );
      expect(
        RssService.parseDate('Tue, 03 Jun 2008 15:00:00 -0500'),
        DateTime.utc(2008, 6, 3, 20).millisecondsSinceEpoch,
      );
      expect(
        RssService.parseDate('Tue, 03 Jun 2008 15:00:00 +03:00'),
        DateTime.utc(2008, 6, 3, 12).millisecondsSinceEpoch,
      );
    });

    test('HTTP-date (GMT), ISO and no-seconds forms', () {
      expect(
        RssService.parseDate('Mon, 06 Jan 2025 12:00:00 GMT'),
        DateTime.utc(2025, 1, 6, 12).millisecondsSinceEpoch,
      );
      expect(
        RssService.parseDate('2025-01-06T12:00:00Z'),
        DateTime.utc(2025, 1, 6, 12).millisecondsSinceEpoch,
      );
      expect(
        RssService.parseDate('Mon, 06 Jan 2025 12:34 +0200'),
        DateTime.utc(2025, 1, 6, 10, 34).millisecondsSinceEpoch,
      );
    });

    test('garbage and empty input return null', () {
      expect(RssService.parseDate('not a date'), isNull);
      expect(RssService.parseDate(''), isNull);
      expect(RssService.parseDate(null), isNull);
    });
  });
}
