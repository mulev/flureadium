import { EpubPage } from './EpubPage';
import { Locator, Readium } from './types';

// Mock the global readium object
const mockReadium: Partial<Readium> = {
  scrollToPosition: jest.fn(),
  isScrollModeEnabled: jest.fn().mockReturnValue(true),
};

// Set up globals before importing EpubPage
(global as any).readium = mockReadium;
(global as any).isIos = false;
(global as any).isAndroid = false;
(global as any).webkit = undefined;
(global as any).Android = null;
(global as any).comicBookPage = null;

describe('EpubPage toc= fragments', () => {
  // A fresh instance per case: `_allHeadings` is cached on the instance, so a
  // reused one would carry the previous case's DOM.
  function fragmentsFor(html: string, cssSelector: string): string[] {
    document.body.innerHTML = html;

    const locator: Locator = {
      href: 'chapter.xhtml',
      locations: {
        cssSelector,
        progression: null,
        totalProgression: null,
        fragments: null,
        domRange: null,
      },
    };

    return new EpubPage().getLocatorFragments(locator, false).locations?.fragments ?? [];
  }

  function tocFragments(fragments: string[]): string[] {
    return fragments.filter((fragment) => fragment.startsWith('toc='));
  }

  it('uses the id of the heading that precedes the selector', () => {
    const fragments = fragmentsFor('<h2 id="c1">One</h2><p id="p1">text</p><h2 id="c2">Two</h2>', '#p1');

    expect(fragments).toContain('toc=c1');
  });

  it('emits no toc fragment when the preceding heading carries no id', () => {
    const fragments = fragmentsFor('<h2>One</h2><p id="p1">text</p><h2 id="c2">Two</h2>', '#p1');

    expect(tocFragments(fragments)).toEqual([]);
    expect(fragments).not.toContain('toc=c2');
  });

  it('falls back to the enclosing section id when no heading precedes', () => {
    const fragments = fragmentsFor('<section id="sec"><p id="p1">text</p></section>', '#p1');

    expect(fragments).toContain('toc=sec');
  });

  it('emits no toc fragment when nothing around the selector carries an id', () => {
    const fragments = fragmentsFor('<p id="p1">text</p>', '#p1');

    expect(tocFragments(fragments)).toEqual([]);
  });

  it('falls forward to the chapter heading when the selector sits above it', () => {
    const fragments = fragmentsFor('<span><a id="back" href="x#t">Inhoud</a></span><h2 id="c1">One</h2>', '#back');

    expect(fragments).toContain('toc=c1');
  });

  it('resolves the heading of an ebookmaker chapter opening with a back link', () => {
    const fragments = fragmentsFor(
      '<div class="div1 chapter" id="ch2">' +
        '<span class="pageNum">[<a class="pginternal" href="76346-h-27.htm.xhtml#ch2.toc">Inhoud</a>]</span>' +
        '<div class="divHead" id="pgepubid00003"><h2 class="main">II.</h2></div>' +
        '<p>body</p>' +
        '</div>',
      "[href='76346-h-27.htm.xhtml#ch2.toc']",
    );

    expect(fragments).toContain('toc=pgepubid00003');
  });
});

describe('EpubPage fragment guard', () => {
  // The jsdom document URL is per file, not per case, so an unreset case would
  // leak into the next one.
  afterEach(() => window.history.replaceState({}, '', '/'));

  // Returns the argument alongside the result, because two of the assertions
  // below are about what the result does *not* carry.
  function resolveLocator(cssSelector: string | null, href: string, documentPath?: string): { locator: Locator; result: Locator } {
    document.body.innerHTML = '<h2 id="c1">One</h2><p id="p1">text</p>';

    if (documentPath != null) {
      // jsdom's document URL is settable only through history; the default is
      // `http://localhost/`, whose path carries no segments at all.
      window.history.replaceState({}, '', documentPath);
    }

    const locator: Locator = {
      href,
      locations: {
        cssSelector,
        progression: null,
        totalProgression: null,
        fragments: null,
        domRange: null,
      },
    };

    return { locator, result: new EpubPage().getLocatorFragments(locator, false) };
  }

  it('merges fragments when the document is the one the locator names', () => {
    const { result } = resolveLocator('#p1', 'EPUB/ch1.xhtml', '/EPUB/ch1.xhtml');

    expect(result.locations?.fragments).toContain('toc=c1');
  });

  it('returns the locator unmerged when the document is another resource', () => {
    const { locator, result } = resolveLocator('#p1', 'EPUB/ch1.xhtml', '/EPUB/ch2.xhtml');

    expect(result).toBe(locator);
    expect(result.locations?.fragments).toBeNull();
    expect(result.locations?.cssSelector).toBe('#p1');
  });

  it('resolves no selector against another resource when the locator carries none', () => {
    const { locator, result } = resolveLocator(null, 'EPUB/ch1.xhtml', '/EPUB/ch2.xhtml');

    expect(result).toBe(locator);
    expect(result.locations?.fragments).toBeNull();
    expect(result.locations?.cssSelector).toBeNull();
  });

  it('merges fragments when the document identity is indeterminate', () => {
    const { result } = resolveLocator('#p1', 'chapter.xhtml');

    expect(result.locations?.fragments).toContain('toc=c1');
  });
});
