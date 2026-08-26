// Copyright (c) 2021 Mantano. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE.Iridium file.

import 'package:flureadium_platform_interface/src/extensions/readium_locations_extension.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('TimeFragment.fromFragment', () {
    test('parses a zero begin', () {
      final fragment = TimeFragment.fromFragment('t=0');

      expect(fragment?.begin, Duration.zero);
      expect(fragment?.end, isNull);
    });

    test('parses a begin and end pair', () {
      final fragment = TimeFragment.fromFragment('t=1.5,3.25');

      expect(fragment?.begin, const Duration(milliseconds: 1500));
      expect(fragment?.end, const Duration(milliseconds: 3250));
    });

    test('parses an exponent', () {
      expect(
        TimeFragment.fromFragment('t=1e1')?.begin,
        const Duration(seconds: 10),
      );
    });

    test('parses a negative begin', () {
      expect(
        TimeFragment.fromFragment('t=-1')?.begin,
        const Duration(seconds: -1),
      );
    });

    test('reads a trailing comma as no end', () {
      final fragment = TimeFragment.fromFragment('t=1,');

      expect(fragment?.begin, const Duration(seconds: 1));
      expect(fragment?.end, isNull);
    });

    test('is null for a fragment of another kind', () {
      expect(TimeFragment.fromFragment('page=1'), isNull);
    });

    test('is null for an empty string', () {
      expect(TimeFragment.fromFragment(''), isNull);
    });
  });

  group('TimeFragment.fragment', () {
    test('renders a begin-only fragment', () {
      expect(
        const TimeFragment(begin: Duration(milliseconds: 1500)).fragment,
        't=1.5',
      );
    });

    test('renders a begin and end fragment', () {
      expect(
        const TimeFragment(
          begin: Duration(milliseconds: 1500),
          end: Duration(seconds: 3),
        ).fragment,
        't=1.5,3.0',
      );
    });

    test('renders the default begin of zero', () {
      expect(const TimeFragment().fragment, 't=0.0');
    });

    test('round trips through fromFragment', () {
      const original = TimeFragment(
        begin: Duration(milliseconds: 1500),
        end: Duration(seconds: 3),
      );

      final parsed = TimeFragment.fromFragment(original.fragment);

      expect(parsed?.begin, original.begin);
      expect(parsed?.end, original.end);
    });
  });

  group('TimeFragment.toString', () {
    test('matches fragment', () {
      const fragment = TimeFragment(begin: Duration(seconds: 2));

      expect(fragment.toString(), 't=2.0');
      expect(fragment.toString(), fragment.fragment);
    });
  });
}
