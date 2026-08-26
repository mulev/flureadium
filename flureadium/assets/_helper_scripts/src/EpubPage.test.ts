import { EpubPage } from './EpubPage';
import { Locations, Locator, Readium } from './types';

// Mock the global readium object
const mockScrollToPosition = jest.fn();
const mockReadium: Partial<Readium> = {
  scrollToPosition: mockScrollToPosition,
  isScrollModeEnabled: jest.fn().mockReturnValue(true),
};

// Set up globals before importing EpubPage
(global as any).readium = mockReadium;
(global as any).isIos = false;
(global as any).isAndroid = false;
(global as any).webkit = undefined;
(global as any).Android = null;
(global as any).comicBookPage = null;

describe('EpubPage', () => {
  let epubPage: EpubPage;

  beforeEach(() => {
    jest.clearAllMocks();
    epubPage = new EpubPage();
  });

  describe('scrollToLocations', () => {
    describe('scroll mode (isVerticalScroll = true)', () => {
      it('uses progression directly when available', () => {
        const locations: Locations = {
          cssSelector: 'body > :nth-child(38)',
          progression: 0.446870373151943,
          totalProgression: 0.05,
          fragments: null,
          domRange: null,
        };

        const result = epubPage.scrollToLocations(locations, true, false);

        expect(result).toBe(true);
        expect(mockScrollToPosition).toHaveBeenCalledTimes(1);
        expect(mockScrollToPosition).toHaveBeenCalledWith(0.446870373151943);
      });

      it('preserves full precision of progression value', () => {
        const preciseProgression = 0.123456789012345;
        const locations: Locations = {
          cssSelector: '#some-element',
          progression: preciseProgression,
          totalProgression: null,
          fragments: null,
          domRange: null,
        };

        epubPage.scrollToLocations(locations, true, false);

        expect(mockScrollToPosition).toHaveBeenCalledWith(preciseProgression);
      });

      it('handles progression at boundaries (0 and 1)', () => {
        const locationsStart: Locations = {
          cssSelector: null,
          progression: 0,
          totalProgression: null,
          fragments: null,
          domRange: null,
        };

        epubPage.scrollToLocations(locationsStart, true, false);
        expect(mockScrollToPosition).toHaveBeenCalledWith(0);

        mockScrollToPosition.mockClear();

        const locationsEnd: Locations = {
          cssSelector: null,
          progression: 1,
          totalProgression: null,
          fragments: null,
          domRange: null,
        };

        epubPage.scrollToLocations(locationsEnd, true, false);
        expect(mockScrollToPosition).toHaveBeenCalledWith(1);
      });

      it('returns false when no progression or CSS selector available', () => {
        const locations: Locations = {
          cssSelector: null,
          progression: null,
          totalProgression: 0.05,
          fragments: null,
          domRange: null,
        };

        const result = epubPage.scrollToLocations(locations, true, false);

        expect(result).toBe(false);
        expect(mockScrollToPosition).not.toHaveBeenCalled();
      });
    });

    describe('paginated mode (isVerticalScroll = false)', () => {
      it('does not prioritize progression over CSS selector', () => {
        const locations: Locations = {
          cssSelector: 'body > :nth-child(38)',
          progression: 0.446870373151943,
          totalProgression: null,
          fragments: null,
          domRange: null,
        };

        // In paginated mode, it will try _processLocations first
        // Since we can't easily mock DOM elements, it will fail and fall back to progression
        const result = epubPage.scrollToLocations(locations, false, false);

        // It should still work (via fallback to progression)
        expect(result).toBe(true);
      });

      it('uses progression as fallback when CSS selector processing fails', () => {
        const locations: Locations = {
          cssSelector: '#non-existent-element',
          progression: 0.75,
          totalProgression: null,
          fragments: null,
          domRange: null,
        };

        const result = epubPage.scrollToLocations(locations, false, false);

        expect(result).toBe(true);
        expect(mockScrollToPosition).toHaveBeenCalledWith(0.75);
      });
    });

    describe('edge cases', () => {
      it('handles undefined readium gracefully', () => {
        const originalReadium = (global as any).readium;
        (global as any).readium = undefined;

        const locations: Locations = {
          cssSelector: null,
          progression: 0.5,
          totalProgression: null,
          fragments: null,
          domRange: null,
        };

        // Should not throw
        expect(() => {
          epubPage.scrollToLocations(locations, true, false);
        }).not.toThrow();

        (global as any).readium = originalReadium;
      });

      it('handles progression value of 0 correctly (not falsy)', () => {
        const locations: Locations = {
          cssSelector: 'body',
          progression: 0,
          totalProgression: 0,
          fragments: null,
          domRange: null,
        };

        const result = epubPage.scrollToLocations(locations, true, false);

        expect(result).toBe(true);
        // 0 is a valid progression, should be used
        expect(mockScrollToPosition).toHaveBeenCalledWith(0);
      });
    });
  });
  describe('isLocatorVisible', () => {
    // jsdom lays nothing out, so every rect is zero and every range reads as
    // off-screen — each case states the rect it wants. jsdom's Range carries no
    // getBoundingClientRect at all, so this defines one rather than spying on it.
    const withRect = (rect: Partial<DOMRect>) => {
      (Range.prototype as any).getBoundingClientRect = () => ({
        top: 0,
        right: 0,
        bottom: 0,
        left: 0,
        ...rect,
      });
    };

    const locatorFor = (cssSelector: string): Locator => ({
      href: 'front.xhtml',
      locations: {
        cssSelector,
        progression: null,
        totalProgression: null,
        fragments: null,
        domRange: null,
      },
    });

    beforeEach(() => {
      document.body.innerHTML = '<h1 id="a0">Title</h1><h2 id="a1">Byline</h2>';
    });

    afterEach(() => {
      delete (Range.prototype as any).getBoundingClientRect;
      document.body.innerHTML = '';
    });

    it('reports a range on the current page as visible', () => {
      // No `activeLocation` marker anywhere: a table-of-contents entry the
      // reader merely happens to be showing never carries one.
      withRect({ top: 10, right: 100, bottom: 40, left: 0 });

      expect(epubPage.isLocatorVisible(locatorFor('#a1'))).toBe(true);
    });

    it('reports a range past the viewport as not visible', () => {
      const { innerWidth } = window;
      withRect({ top: 10, right: innerWidth + 200, bottom: 40, left: innerWidth + 100 });

      expect(epubPage.isLocatorVisible(locatorFor('#a1'))).toBe(false);
    });

    it('reports a selector that matches nothing as not visible', () => {
      withRect({ top: 10, right: 100, bottom: 40, left: 0 });

      expect(epubPage.isLocatorVisible(locatorFor('#nowhere'))).toBe(false);
    });
  });
});
