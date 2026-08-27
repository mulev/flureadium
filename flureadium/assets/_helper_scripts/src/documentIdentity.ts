// Decides whether a locator's href names the document this script is running in.
//
// Both platforms serve a spine item at a URL whose path *ends with* the
// publication-relative href the locator carries: Android at
// `https://readium/publication/OEBPS/wrap0000.xhtml`, iOS at whatever
// `link.url(relativeTo: publicationBaseURL)` produces. So this is a suffix match
// over path segments — never string equality, and never a URL parse that assumes
// a scheme or an authority.
//
// `readium.link` is deliberately not consulted. It is set only on iOS, so a check
// keyed on it would answer "unknown" on every Android page and disable fragment
// resolution there.

/**
 * `true` when the href names the running document, `false` on a proven mismatch,
 * `null` when identity cannot be determined. A caller must treat `null` as "carry
 * on": the guard exists to catch a proven mismatch, not to demand proof of a match.
 */
export function isSameResource(locatorHref: string | null | undefined, documentUrl: string | null | undefined): boolean | null {
  if (!locatorHref || !documentUrl) {
    return null;
  }

  const hrefSegments = pathSegments(locatorHref);
  const documentSegments = pathSegments(documentUrl);
  const overlap = Math.min(hrefSegments.length, documentSegments.length);
  if (overlap === 0) {
    return null;
  }

  for (let fromEnd = 1; fromEnd <= overlap; fromEnd++) {
    const hrefSegment = hrefSegments[hrefSegments.length - fromEnd];
    const documentSegment = documentSegments[documentSegments.length - fromEnd];

    if (hrefSegment !== documentSegment) {
      return false;
    }
  }

  // The overlap agrees. That proves identity only when the document's path is at
  // least as specific as the href; a document reporting fewer segments than the
  // locator names has given a shorter answer, not a different one.
  return documentSegments.length >= hrefSegments.length ? true : null;
}

function pathSegments(value: string): string[] {
  const withoutQueryOrFragment = value.split('#')[0].split('?')[0];
  const path = urlPath(withoutQueryOrFragment);
  const segments: string[] = [];

  for (const raw of path.split('/')) {
    if (raw === '' || raw === '.') {
      continue;
    }

    if (raw === '..') {
      segments.pop();
      continue;
    }

    segments.push(decodeSegment(raw));
  }

  return segments;
}

function urlPath(value: string): string {
  const schemeEnd = value.indexOf('://');
  if (schemeEnd >= 0) {
    const authorityEnd = value.indexOf('/', schemeEnd + 3);

    return authorityEnd < 0 ? '' : value.slice(authorityEnd);
  }

  // `about:blank`, `data:…`, `blob:…` — a scheme with no hierarchical path. Nothing
  // in them names a resource this comparison can reason about, so they reduce to no
  // segments and the answer comes back indeterminate.
  const colon = value.indexOf(':');
  const slash = value.indexOf('/');
  if (colon >= 0 && (slash < 0 || colon < slash)) {
    return '';
  }

  return value;
}

function decodeSegment(segment: string): string {
  try {
    return decodeURIComponent(segment);
  } catch (_) {
    // A malformed escape such as `%zz` is not a reason to abandon the whole
    // comparison — compare that segment raw and let the other side match or not.
    return segment;
  }
}
