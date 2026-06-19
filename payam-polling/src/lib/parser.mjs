// Feed parsing — wraps `rss-parser` to produce a ParsedArticle shape that
// mirrors the on-device ParsedArticle (RSSService.swift). rss-parser handles
// RSS 2.0, Atom, and most extension namespaces (media:*, itunes:*, dc:*).

import Parser from 'rss-parser';

const parser = new Parser({
  timeout: 10_000,
  headers: {
    'User-Agent': 'Payam/2.0 (Server; polling)',
    'Accept': 'application/rss+xml, application/atom+xml, application/json, text/xml, */*',
  },
  customFields: {
    item: [
      ['media:content', 'mediaContent', { keepArray: true }],
      ['media:thumbnail', 'mediaThumbnail', { keepArray: true }],
      ['itunes:image', 'itunesImage'],
      ['content:encoded', 'contentEncoded'],
      ['dc:creator', 'dcCreator'],
    ],
    feed: [
      ['itunes:image', 'itunesImage'],
    ],
  },
});

export async function parseFeed(xmlString, { feedUrl } = {}) {
  const feed = await parser.parseString(xmlString);
  return {
    feed: {
      title: feed.title ?? null,
      description: feed.description ?? null,
      imageURL: extractFeedImage(feed),
      lastBuildDate: feed.lastBuildDate ? toEpoch(feed.lastBuildDate) : null,
    },
    items: (feed.items ?? []).map((it) => toParsedArticle(it, feedUrl)),
  };
}

function toParsedArticle(item, feedUrl) {
  const link = (item.link ?? item.guid ?? '').trim();
  const publishedAt = item.isoDate ? toEpoch(item.isoDate)
    : item.pubDate ? toEpoch(item.pubDate)
    : null;

  const enclosureType = item.enclosure?.type ?? '';
  const isAudioEnc = isAudio(enclosureType);
  const isVideoEnc = isVideo(enclosureType);

  let imageURL = item.itunesImage?.$?.href
    ?? widestMediaThumbnail(item.mediaThumbnail)
    ?? widestNonAudioMediaContent(item.mediaContent);

  if (!imageURL && !isAudioEnc && !isVideoEnc) {
    imageURL = item.enclosure?.url ?? null;
  }
  if (!imageURL) {
    imageURL = firstImageInHtml(item.contentEncoded) ?? firstImageInHtml(item.content);
  }
  if (imageURL?.startsWith('http://')) {
    imageURL = 'https://' + imageURL.slice('http://'.length);
  }
  if (!imageURL) {
    const videoID = youtubeVideoID(link);
    if (videoID) imageURL = `https://img.youtube.com/vi/${videoID}/maxresdefault.jpg`;
  }

  let audioURL = null;
  if (isAudioEnc) audioURL = item.enclosure?.url ?? null;
  if (!audioURL) {
    const mc = (item.mediaContent ?? []).find((m) => isAudio(m?.$?.type) || m?.$?.medium === 'audio');
    audioURL = mc?.$?.url ?? null;
  }

  let videoURL = null;
  if (isVideoEnc) videoURL = item.enclosure?.url ?? null;
  if (!videoURL) {
    const mc = (item.mediaContent ?? []).find((m) => isVideo(m?.$?.type) || m?.$?.medium === 'video');
    videoURL = mc?.$?.url ?? null;
  }

  const author = item.creator ?? item.dcCreator ?? item.author ?? null;
  const excerpt = plainText(item.contentSnippet ?? item.content ?? item.description ?? '');

  return {
    title: (item.title ?? '').trim() || null,
    link: link || null,
    publishedAt,
    excerpt,
    imageURL: imageURL ?? null,
    audioURL,
    videoURL,
    author,
  };
}

function extractFeedImage(feed) {
  return feed.itunesImage?.$?.href
    ?? feed.image?.url
    ?? null;
}

function widestMediaThumbnail(thumbs) {
  if (!Array.isArray(thumbs) || thumbs.length === 0) return null;
  let best = null;
  for (const t of thumbs) {
    const url = t?.$?.url;
    if (!url) continue;
    const w = Number(t?.$?.width ?? 0);
    if (!best || w > best.w) best = { w, url };
  }
  return best?.url ?? null;
}

function widestNonAudioMediaContent(contents) {
  if (!Array.isArray(contents) || contents.length === 0) return null;
  let best = null;
  for (const c of contents) {
    const type = c?.$?.type ?? '';
    const medium = c?.$?.medium ?? '';
    if (isAudio(type) || medium === 'audio') continue;
    const url = c?.$?.url;
    if (!url) continue;
    const w = Number(c?.$?.width ?? 0);
    if (!best || w > best.w) best = { w, url };
  }
  return best?.url ?? null;
}

function firstImageInHtml(html) {
  if (!html) return null;
  const m = html.match(/<img\b[^>]*?\bsrc=(?:"([^"]+)"|'([^']+)')/i);
  const raw = m?.[1] ?? m?.[2];
  if (!raw) return null;
  const decoded = raw
    .replaceAll('&#038;', '&').replaceAll('&#38;', '&')
    .replaceAll('&amp;', '&').replaceAll('&#039;', "'")
    .replaceAll('&quot;', '"').replaceAll('&lt;', '<').replaceAll('&gt;', '>');
  if (!decoded.startsWith('http')) return null;
  return decoded.startsWith('http://') ? 'https://' + decoded.slice(7) : decoded;
}

function youtubeVideoID(urlString) {
  try {
    const url = new URL(urlString);
    const host = url.hostname.replace(/^(www\.|m\.)/, '');
    if (host === 'youtu.be') return url.pathname.slice(1) || null;
    if (host === 'youtube.com') {
      if (url.pathname === '/watch') return url.searchParams.get('v') || null;
      const shorts = url.pathname.match(/^\/shorts\/([^/]+)/);
      if (shorts) return shorts[1];
    }
  } catch { /* invalid URL */ }
  return null;
}

function isAudio(type) { return typeof type === 'string' && type.startsWith('audio/'); }
function isVideo(type) { return typeof type === 'string' && type.startsWith('video/'); }

function plainText(html) {
  return (html ?? '')
    .replace(/<[^>]+>/g, '')
    .replace(/&nbsp;/g, ' ')
    .replace(/&amp;/g, '&')
    .replace(/&quot;/g, '"')
    .replace(/&#39;/g, "'")
    .trim();
}

function toEpoch(s) {
  const ms = Date.parse(s);
  return Number.isFinite(ms) ? Math.floor(ms / 1000) : null;
}
