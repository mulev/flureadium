import { isSameResource } from './documentIdentity';

describe('isSameResource', () => {
  describe('matches', () => {
    it('accepts the exact URL Android serves a spine item at', () => {
      expect(isSameResource('OEBPS/wrap0000.xhtml', 'https://readium/publication/OEBPS/wrap0000.xhtml')).toBe(true);
    });

    it('ignores a leading slash on the locator side', () => {
      expect(isSameResource('/EPUB/ch1.xhtml', 'https://readium/publication/EPUB/ch1.xhtml')).toBe(true);
    });

    it('accepts a document URL that is a bare path with no scheme or host', () => {
      expect(isSameResource('EPUB/ch1.xhtml', '/EPUB/ch1.xhtml')).toBe(true);
    });

    it('accepts an href shorter than the document path', () => {
      expect(isSameResource('ch1.xhtml', 'https://readium/publication/EPUB/ch1.xhtml')).toBe(true);
    });

    it('decodes a percent-encoded document path before comparing', () => {
      expect(isSameResource('EPUB/Happiness v01 [HD].xhtml', 'https://readium/publication/EPUB/Happiness%20v01%20%5BHD%5D.xhtml')).toBe(true);
    });

    it('decodes a percent-encoded href before comparing', () => {
      expect(isSameResource('EPUB/Happiness%20v01%20%5BHD%5D.xhtml', 'https://readium/publication/EPUB/Happiness v01 [HD].xhtml')).toBe(true);
    });

    it('compares a malformed escape raw rather than throwing', () => {
      expect(isSameResource('EPUB/%zz.xhtml', 'https://readium/publication/EPUB/%zz.xhtml')).toBe(true);
    });

    it('ignores a fragment on the href', () => {
      expect(isSameResource('EPUB/ch1.xhtml#c1', 'https://readium/publication/EPUB/ch1.xhtml')).toBe(true);
    });

    it('ignores a query on the href', () => {
      expect(isSameResource('EPUB/ch1.xhtml?v=2', 'https://readium/publication/EPUB/ch1.xhtml')).toBe(true);
    });

    it('normalises dot segments on either side', () => {
      expect(isSameResource('EPUB/../EPUB/ch1.xhtml', 'https://readium/publication/EPUB/./ch1.xhtml')).toBe(true);
    });

    it('collapses doubled slashes', () => {
      expect(isSameResource('EPUB//ch1.xhtml', 'https://readium/publication/EPUB/ch1.xhtml')).toBe(true);
    });
  });

  describe('proven mismatches', () => {
    it('rejects a sibling resource', () => {
      expect(isSameResource('EPUB/ch1.xhtml', 'https://readium/publication/EPUB/ch2.xhtml')).toBe(false);
    });

    it('rejects the same file name in a different directory', () => {
      expect(isSameResource('EPUB/ch1.xhtml', 'https://readium/publication/OTHER/ch1.xhtml')).toBe(false);
    });

    it('rejects a file name the href is only a suffix of', () => {
      // The case that proves segment comparison rather than `String.endsWith`.
      expect(isSameResource('ch1.xhtml', 'https://readium/publication/EPUB/xch1.xhtml')).toBe(false);
    });

    it('rejects a case difference', () => {
      // Paths inside an EPUB container are case-sensitive, so these are two
      // resources — a real mismatch, not a normalisation gap.
      expect(isSameResource('EPUB/CH1.xhtml', 'https://readium/publication/EPUB/ch1.xhtml')).toBe(false);
    });

    it('rejects the contamination this guard exists to stop', () => {
      expect(isSameResource('EPUB/cover.xhtml', 'https://readium/publication/EPUB/front.xhtml')).toBe(false);
    });
  });

  describe('indeterminate', () => {
    it('answers null for a null document URL', () => {
      expect(isSameResource('EPUB/ch1.xhtml', null)).toBeNull();
    });

    it('answers null for an undefined document URL', () => {
      expect(isSameResource('EPUB/ch1.xhtml', undefined)).toBeNull();
    });

    it('answers null for an empty document URL', () => {
      expect(isSameResource('EPUB/ch1.xhtml', '')).toBeNull();
    });

    it('answers null for about:blank', () => {
      expect(isSameResource('EPUB/ch1.xhtml', 'about:blank')).toBeNull();
    });

    it('answers null for a data URL', () => {
      expect(isSameResource('EPUB/ch1.xhtml', 'data:text/html,<p>x</p>')).toBeNull();
    });

    it("answers null for jsdom's default document URL", () => {
      // `http://localhost/` has no path segments at all. This is why the
      // existing EpubPage suite keeps merging fragments untouched.
      expect(isSameResource('EPUB/ch1.xhtml', 'http://localhost/')).toBeNull();
    });

    it('answers null for a scheme and authority with no path', () => {
      expect(isSameResource('EPUB/ch1.xhtml', 'https://readium')).toBeNull();
    });

    it('answers null for an empty href', () => {
      expect(isSameResource('', 'https://readium/publication/EPUB/ch1.xhtml')).toBeNull();
    });

    it('answers null when the document path is shorter than the href but agrees', () => {
      // A shorter answer is not a different one, so no mismatch is proven.
      expect(isSameResource('EPUB/ch1.xhtml', 'https://readium/ch1.xhtml')).toBeNull();
    });
  });
});
