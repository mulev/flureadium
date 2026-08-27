// Copyright (c) 2021 Mantano. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE.Iridium file.

import 'package:flureadium_platform_interface/src/extensions/readium_locations_extension.dart';
import 'package:flureadium_platform_interface/src/shared/publication/locations.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('timeFragment', () {
    test('is null when there are no fragments', () {
      expect(const Locations().timeFragment, isNull);
    });

    test('is null when no fragment is a time fragment', () {
      expect(const Locations(fragments: ['page=1']).timeFragment, isNull);
    });

    test('reads a begin-only fragment', () {
      final fragment = const Locations(fragments: ['t=1.5']).timeFragment;

      expect(fragment?.begin, const Duration(milliseconds: 1500));
      expect(fragment?.end, isNull);
    });

    test('reads a begin and end fragment', () {
      final fragment = const Locations(fragments: ['t=1.5,3']).timeFragment;

      expect(fragment?.begin, const Duration(milliseconds: 1500));
      expect(fragment?.end, const Duration(seconds: 3));
    });

    test('skips fragments that are not time fragments', () {
      expect(
        const Locations(fragments: ['page=1', 't=2']).timeFragment?.begin,
        const Duration(seconds: 2),
      );
    });

    test('throws on a bare t= fragment', () {
      // Observed behaviour, filed as flureadium-p2s7 and deliberately not
      // fixed here: the begin group of the pattern is optional, but
      // fromFragment force-unwraps it with match[1]!.
      expect(
        () => const Locations(fragments: ['t=']).timeFragment,
        throwsA(isA<TypeError>()),
      );
    });
  });

  group('copyWithTimeFragment', () {
    const twoSeconds = TimeFragment(begin: Duration(seconds: 2));

    test('sets a fragment on an empty locations', () {
      expect(const Locations().copyWithTimeFragment(twoSeconds).fragments, [
        't=2.0',
      ]);
    });

    test('replaces the existing fragment and keeps the others', () {
      expect(
        const Locations(
          fragments: ['page=1', 't=1.0'],
        ).copyWithTimeFragment(twoSeconds).fragments,
        ['page=1', 't=2.0'],
      );
    });

    test('clears the fragment when another one survives', () {
      expect(
        const Locations(
          fragments: ['page=1', 't=1.0'],
        ).copyWithTimeFragment(null).fragments,
        ['page=1'],
      );
    });

    test('cannot clear the only fragment', () {
      // Observed behaviour, filed as flureadium-vea4 and deliberately not
      // fixed here: an empty result list is passed to copyWith as null, and
      // Locations.copyWith reads null as "keep", not "clear".
      expect(
        const Locations(
          fragments: ['t=1.0'],
        ).copyWithTimeFragment(null).fragments,
        ['t=1.0'],
      );
    });
  });

  group('copyWithPhysicalPageNumber', () {
    test('sets a fragment on an empty locations', () {
      expect(const Locations().copyWithPhysicalPageNumber('iv').fragments, [
        'physicalPage=iv',
      ]);
    });

    test('replaces the existing fragment and keeps the others', () {
      expect(
        const Locations(
          fragments: ['page=1', 'physicalPage=iii'],
        ).copyWithPhysicalPageNumber('iv').fragments,
        ['page=1', 'physicalPage=iv'],
      );
    });

    test('clears the fragment when another one survives', () {
      expect(
        const Locations(
          fragments: ['page=1', 'physicalPage=iv'],
        ).copyWithPhysicalPageNumber(null).fragments,
        ['page=1'],
      );
    });

    test('cannot clear the only fragment', () {
      // See flureadium-vea4 — null means keep, not clear.
      expect(
        const Locations(
          fragments: ['physicalPage=iv'],
        ).copyWithPhysicalPageNumber(null).fragments,
        ['physicalPage=iv'],
      );
    });
  });

  group('copyWithPage', () {
    test('sets a fragment on an empty locations', () {
      expect(const Locations().copyWithPage(7).fragments, ['page=7']);
    });

    test('replaces the existing fragment and keeps the others', () {
      expect(
        const Locations(
          fragments: ['toc=c1', 'page=1'],
        ).copyWithPage(7).fragments,
        ['toc=c1', 'page=7'],
      );
    });

    test('clears the fragment when another one survives', () {
      expect(
        const Locations(
          fragments: ['toc=c1', 'page=1'],
        ).copyWithPage(null).fragments,
        ['toc=c1'],
      );
    });

    test('cannot clear the only fragment', () {
      // See flureadium-vea4 — null means keep, not clear.
      expect(
        const Locations(fragments: ['page=1']).copyWithPage(null).fragments,
        ['page=1'],
      );
    });
  });

  group('copyWithFragmentDuration', () {
    test('sets a fragment on an empty locations', () {
      expect(const Locations().copyWithFragmentDuration(30).fragments, [
        'duration=30',
      ]);
    });

    test('writes a non-integer duration verbatim', () {
      expect(const Locations().copyWithFragmentDuration(12.5).fragments, [
        'duration=12.5',
      ]);
    });

    test('clears the fragment when another one survives', () {
      expect(
        const Locations(
          fragments: ['page=1', 'duration=30'],
        ).copyWithFragmentDuration(null).fragments,
        ['page=1'],
      );
    });

    test('cannot clear the only fragment', () {
      // See flureadium-vea4 — null means keep, not clear.
      expect(
        const Locations(
          fragments: ['duration=30'],
        ).copyWithFragmentDuration(null).fragments,
        ['duration=30'],
      );
    });
  });

  group('physicalPage', () {
    test('reads the value', () {
      const locations = Locations(fragments: ['physicalPage=iv']);

      expect(locations.physicalPage, 'iv');
    });

    test('is null when the fragment is absent', () {
      expect(const Locations(fragments: ['page=1']).physicalPage, isNull);
    });

    test('reads an empty value as an empty string', () {
      // Unchanged by the tocFragment guard; this case records that.
      expect(const Locations(fragments: ['physicalPage=']).physicalPage, '');
    });
  });

  group('page', () {
    test('reads the value', () {
      expect(const Locations(fragments: ['page=7']).page, 7);
    });

    test('is null when the fragment is absent', () {
      expect(const Locations(fragments: ['toc=c1']).page, isNull);
    });

    test('is null when the value is not a number', () {
      expect(const Locations(fragments: ['page=abc']).page, isNull);
    });

    test('is null when the value is empty', () {
      expect(const Locations(fragments: ['page=']).page, isNull);
    });

    test('does not read a physical page as a page', () {
      expect(const Locations(fragments: ['physicalPage=3']).page, isNull);
    });
  });

  group('totalPages', () {
    test('reads the value', () {
      expect(const Locations(fragments: ['totalPages=42']).totalPages, 42);
    });

    test('is null when the fragment is absent', () {
      expect(const Locations(fragments: ['page=1']).totalPages, isNull);
    });

    test('is null when the value is not a number', () {
      const locations = Locations(fragments: ['totalPages=many']);

      expect(locations.totalPages, isNull);
    });
  });

  group('tocFragment', () {
    const id = 'pgepubid00003';

    test('reads the value', () {
      expect(const Locations(fragments: ['toc=$id']).tocFragment, id);
    });

    test('reads the value past another fragment', () {
      expect(const Locations(fragments: ['page=1', 'toc=$id']).tocFragment, id);
    });

    test('is null when the fragment is absent', () {
      expect(const Locations(fragments: ['page=1']).tocFragment, isNull);
    });

    test('is null when the value is empty', () {
      expect(const Locations(fragments: ['toc=']).tocFragment, isNull);
    });

    test('leaves the sibling getters alone', () {
      const locations = Locations(fragments: ['toc=']);

      expect(locations.page, isNull);
      expect(locations.physicalPage, isNull);
    });
  });

  group('durationFragment', () {
    test('reads the value', () {
      expect(const Locations(fragments: ['duration=30']).durationFragment, 30);
    });

    test('is null when the fragment is absent', () {
      expect(const Locations(fragments: ['page=1']).durationFragment, isNull);
    });

    test('is null for a non-integer value', () {
      // copyWithFragmentDuration accepts a num, so it can write a value this
      // getter cannot read back. Recorded, not fixed here.
      const locations = Locations(fragments: ['duration=30.5']);

      expect(locations.durationFragment, isNull);
    });

    test('is null when the value is empty', () {
      const locations = Locations(fragments: ['duration=']);

      expect(locations.durationFragment, isNull);
    });
  });
}
