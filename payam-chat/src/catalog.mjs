// Server-side mirror of the curated RSSCatalog from the iOS app.
// Used by discover_sources for deterministic first-pass keyword matching.
//
// When the iOS catalog changes, regenerate this file; the two are intentionally
// duplicated so the agent can suggest from the canonical set without a roundtrip.

export const CATALOG = [
  {
    category: 'Tech',
    keywords: ['tech', 'technology', 'gadgets', 'hardware', 'computers', 'internet', 'consumer tech'],
    feeds: [
      { name: 'Hacker News', feedURL: 'https://news.ycombinator.com/rss', description: 'Links for the intellectually curious, ranked by readers.' },
      { name: 'The Verge', feedURL: 'https://www.theverge.com/rss/index.xml', description: 'All the latest in tech, science, art, and culture.' },
      { name: 'Ars Technica', feedURL: 'http://feeds.arstechnica.com/arstechnica/index', description: 'Serving the Technologist for more than a decade.' },
      { name: 'TechCrunch', feedURL: 'http://feeds.feedburner.com/TechCrunch', description: 'Startup and technology news.' },
      { name: 'Gizmodo', feedURL: 'https://gizmodo.com/rss', description: 'We come from the future.' },
      { name: 'Stratechery', feedURL: 'http://stratechery.com/feed/', description: 'On the business, strategy, and impact of technology.' },
      { name: 'Engadget', feedURL: 'https://www.engadget.com/rss.xml', description: 'Technology news, advice and features.' },
      { name: 'Lifehacker', feedURL: 'https://lifehacker.com/rss', description: 'Do everything better.' },
      { name: 'Slashdot', feedURL: 'http://rss.slashdot.org/Slashdot/slashdotMain', description: 'News for nerds, stuff that matters.' },
      { name: 'The Next Web', feedURL: 'https://thenextweb.com/feed/', description: 'Original and proudly opinionated perspectives for Generation T.' },
    ],
  },
  {
    category: 'Apple',
    keywords: ['apple', 'mac', 'macos', 'ios', 'iphone', 'ipad', 'macbook', 'iphone rumors'],
    feeds: [
      { name: '9to5Mac', feedURL: 'https://9to5mac.com/feed', description: 'Breaking Apple news and reviews.' },
      { name: 'Apple Newsroom', feedURL: 'https://www.apple.com/newsroom/rss-feed.rss', description: 'Official news and product announcements from Apple.' },
      { name: 'AppleInsider', feedURL: 'https://appleinsider.com/rss/news/', description: 'Apple news, rumours, and deep analysis.' },
      { name: 'Cult of Mac', feedURL: 'https://www.cultofmac.com/feed', description: 'Apple news, reviews, and how-tos.' },
      { name: 'Daring Fireball', feedURL: 'https://daringfireball.net/feeds/main', description: "John Gruber's commentary on Apple and the tech industry." },
      { name: 'MacStories', feedURL: 'https://www.macstories.net/feed', description: 'App reviews, analysis, and productivity on Apple platforms.' },
      { name: 'MacRumors', feedURL: 'http://feeds.macrumors.com/MacRumors-Mac', description: 'Mac news, rumors, and price guides.' },
    ],
  },
  {
    category: 'Programming',
    keywords: ['programming', 'coding', 'software', 'engineering', 'developer', 'dev', 'languages', 'architecture'],
    feeds: [
      { name: 'Stack Overflow Blog', feedURL: 'https://stackoverflow.blog/feed/', description: 'Essays, opinions, and advice on the act of computer programming.' },
      { name: 'GitHub Blog', feedURL: 'https://github.blog/feed/', description: 'Updates, ideas, and inspiration from GitHub.' },
      { name: 'Joel on Software', feedURL: 'https://www.joelonsoftware.com/feed/', description: 'Software development and engineering management.' },
      { name: 'Martin Fowler', feedURL: 'https://martinfowler.com/feed.atom', description: 'Architecture, design patterns, and agile practices.' },
      { name: 'Netflix TechBlog', feedURL: 'https://netflixtechblog.com/feed', description: "Netflix's world-class engineering and data science." },
      { name: 'Coding Horror', feedURL: 'https://feeds.feedburner.com/codinghorror', description: 'Programming and human factors by Jeff Atwood.' },
      { name: 'InfoQ', feedURL: 'https://feed.infoq.com', description: 'Software development news, trends, and deep dives.' },
      { name: 'Spotify Engineering', feedURL: 'https://labs.spotify.com/feed/', description: "Spotify's official technology and engineering blog." },
      { name: 'Overreacted', feedURL: 'https://overreacted.io/rss.xml', description: 'Personal blog by Dan Abramov — React and JavaScript insights.' },
      { name: 'Facebook Engineering', feedURL: 'https://engineering.fb.com/feed/', description: "Meta's engineering and infrastructure blog." },
    ],
  },
  {
    category: 'Science',
    keywords: ['science', 'research', 'environment', 'biology', 'physics', 'chemistry'],
    feeds: [
      { name: 'BBC Science & Environment', feedURL: 'http://feeds.bbci.co.uk/news/science_and_environment/rss.xml', description: 'Science and environment news from the BBC.' },
      { name: 'Scientific American', feedURL: 'http://rss.sciam.com/sciam/60secsciencepodcast', description: '60-Second Science podcast from Scientific American.' },
      { name: 'Gizmodo Science', feedURL: 'https://gizmodo.com/tag/science/rss', description: 'Science news and discoveries from Gizmodo.' },
      { name: 'Hidden Brain', feedURL: 'https://feeds.npr.org/510308/podcast.xml', description: 'Exploring unconscious patterns that drive human behavior.' },
      { name: 'FlowingData', feedURL: 'https://flowingdata.com/feed', description: 'Data visualization, statistics, and infographics.' },
      { name: 'Invisibilia', feedURL: 'https://feeds.npr.org/510307/podcast.xml', description: 'The invisible forces that shape human behavior.' },
    ],
  },
  {
    category: 'News',
    keywords: ['news', 'world', 'politics', 'current events', 'headlines', 'breaking news'],
    feeds: [
      { name: 'BBC News – World', feedURL: 'http://feeds.bbci.co.uk/news/world/rss.xml', description: 'World news from the BBC.' },
      { name: 'NYT World News', feedURL: 'https://rss.nytimes.com/services/xml/rss/nyt/World.xml', description: 'World news from The New York Times.' },
      { name: 'Google News', feedURL: 'https://news.google.com/rss', description: 'Top stories aggregated by Google News.' },
      { name: 'Washington Post', feedURL: 'http://feeds.washingtonpost.com/rss/world', description: 'World news from The Washington Post.' },
      { name: 'CNBC International', feedURL: 'https://www.cnbc.com/id/100727362/device/rss/rss.html', description: 'International top news and analysis from CNBC.' },
      { name: 'r/worldnews', feedURL: 'https://www.reddit.com/r/worldnews/.rss', description: 'Major news stories from around the world.' },
      { name: 'NDTV World News', feedURL: 'http://feeds.feedburner.com/ndtvnews-world-news', description: 'World news from NDTV.' },
    ],
  },
  {
    category: 'Gaming',
    keywords: ['gaming', 'games', 'video games', 'esports', 'indie games'],
    feeds: [
      { name: 'Kotaku', feedURL: 'https://kotaku.com/rss', description: 'Video game culture, reviews, and news.' },
      { name: 'IGN', feedURL: 'http://feeds.ign.com/ign/all', description: 'Video games, movies, TV and more.' },
      { name: 'Eurogamer', feedURL: 'https://www.eurogamer.net/?format=rss', description: 'Video game reviews, previews, and news.' },
      { name: 'GameSpot', feedURL: 'https://www.gamespot.com/feeds/mashup/', description: 'Video game reviews and industry news.' },
      { name: 'Indie Games Plus', feedURL: 'https://indiegamesplus.com/feed', description: 'Indie game news, reviews, and features.' },
      { name: 'Gamasutra', feedURL: 'http://feeds.feedburner.com/GamasutraNews', description: 'The art & business of making games.' },
      { name: 'Escapist Magazine', feedURL: 'https://www.escapistmagazine.com/v2/feed/', description: 'Video game and pop-culture commentary.' },
    ],
  },
  {
    category: 'Music',
    keywords: ['music', 'songs', 'albums', 'bands', 'edm', 'pop', 'rock', 'concerts'],
    feeds: [
      { name: 'Pitchfork', feedURL: 'http://pitchfork.com/rss/news', description: 'Music reviews, news, and features.' },
      { name: 'Billboard', feedURL: 'https://www.billboard.com/articles/rss.xml', description: 'Charts, artist features, and industry news.' },
      { name: 'Consequence of Sound', feedURL: 'http://consequenceofsound.net/feed', description: 'Music, film, and television news and reviews.' },
      { name: 'Song Exploder', feedURL: 'http://songexploder.net/feed', description: 'Musicians take apart their songs piece by piece.' },
      { name: 'Music Business Worldwide', feedURL: 'https://www.musicbusinessworldwide.com/feed/', description: 'Global music industry news and analysis.' },
      { name: 'Your EDM', feedURL: 'https://www.youredm.com/feed', description: 'Electronic dance music news, reviews, and culture.' },
    ],
  },
  {
    category: 'Business',
    keywords: ['business', 'finance', 'markets', 'economy', 'stocks', 'investing', 'corporate'],
    feeds: [
      { name: 'Forbes Business', feedURL: 'https://www.forbes.com/business/feed/', description: 'Business news and analysis from Forbes.' },
      { name: 'Fortune', feedURL: 'https://fortune.com/feed', description: 'Business leadership and corporate strategy.' },
      { name: 'Inc.com', feedURL: 'https://www.inc.com/rss/', description: 'Small business and entrepreneurship advice.' },
      { name: 'Economic Times', feedURL: 'https://economictimes.indiatimes.com/rssfeedsdefault.cms', description: 'India and global business and economic news.' },
      { name: 'Seeking Alpha', feedURL: 'https://seekingalpha.com/market_currents.xml', description: 'Breaking news from financial markets.' },
      { name: 'Duct Tape Marketing', feedURL: 'https://ducttape.libsyn.com/rss', description: 'Small business marketing strategy and advice.' },
    ],
  },
  {
    category: 'Startups',
    keywords: ['startups', 'startup', 'entrepreneur', 'vc', 'venture capital', 'founders'],
    feeds: [
      { name: 'Hacker News: Front Page', feedURL: 'https://hnrss.org/frontpage', description: 'Top stories from Hacker News.' },
      { name: 'AVC', feedURL: 'https://avc.com/feed/', description: 'Venture capital musings by Fred Wilson of USV.' },
      { name: 'Both Sides of the Table', feedURL: 'https://bothsidesofthetable.com/feed', description: 'Startup advice from a VC-turned-entrepreneur.' },
      { name: 'Entrepreneur', feedURL: 'http://feeds.feedburner.com/entrepreneur/latest', description: 'Startup and entrepreneurship news and advice.' },
      { name: 'Forbes Entrepreneurs', feedURL: 'https://www.forbes.com/entrepreneurs/feed/', description: 'Entrepreneurship insight and profiles from Forbes.' },
      { name: 'Feld Thoughts', feedURL: 'https://feld.com/feed', description: 'Brad Feld on venture capital, startups, and life.' },
    ],
  },
  {
    category: 'Space',
    keywords: ['space', 'astronomy', 'nasa', 'rockets', 'spacex', 'stars', 'cosmos'],
    feeds: [
      { name: 'NASA Breaking News', feedURL: 'https://www.nasa.gov/rss/dyn/breaking_news.rss', description: 'The latest news and announcements from NASA.' },
      { name: 'Space.com', feedURL: 'https://www.space.com/feeds/all', description: 'The latest in space science and exploration.' },
      { name: 'The Guardian: Space', feedURL: 'https://www.theguardian.com/science/space/rss', description: 'Space news from The Guardian.' },
      { name: 'Sky & Telescope', feedURL: 'https://www.skyandtelescope.com/feed/', description: 'Astronomy news, observing guides, and gear.' },
      { name: 'r/space', feedURL: 'https://www.reddit.com/r/space/.rss?format=xml', description: 'News, articles and discussion about space.' },
      { name: 'New Scientist: Space', feedURL: 'https://www.newscientist.com/subject/space/feed/', description: 'Space and astronomy from New Scientist.' },
    ],
  },
  {
    category: 'iOS Dev',
    keywords: ['ios development', 'ios dev', 'swift', 'swiftui', 'xcode', 'apple developer'],
    feeds: [
      { name: 'Swift by Sundell', feedURL: 'https://www.swiftbysundell.com/feed.rss', description: 'Articles, podcasts and tips about Swift development.' },
      { name: 'Apple Developer News', feedURL: 'https://developer.apple.com/news/rss/news.rss', description: 'Latest news and announcements from Apple Developer.' },
      { name: 'Augmented Code', feedURL: 'https://augmentedcode.io/feed/', description: 'iOS and Swift development tips and tutorials.' },
      { name: 'Ole Begemann', feedURL: 'https://oleb.net/blog/atom.xml', description: 'Deep-dive iOS and Swift development articles.' },
      { name: 'More Than Just Code', feedURL: 'https://feeds.fireside.fm/mtjc/rss', description: 'iOS and Swift development news and advice.' },
    ],
  },
  {
    category: 'Books',
    keywords: ['books', 'reading', 'literature', 'fiction', 'novels', 'book reviews'],
    feeds: [
      { name: 'Book Riot', feedURL: 'https://bookriot.com/feed/', description: 'Book reviews, lists, and literary culture.' },
      { name: 'Kirkus Reviews', feedURL: 'https://www.kirkusreviews.com/feeds/rss/', description: 'Authoritative book reviews since 1933.' },
      { name: 'r/books', feedURL: 'https://reddit.com/r/books/.rss', description: 'A place for readers to share and discuss.' },
      { name: 'A Year of Reading the World', feedURL: 'https://ayearofreadingtheworld.com/feed/', description: 'Reading and reviewing books from every country.' },
    ],
  },
];

/**
 * Score every catalog category against a topic phrase. Pure helper shared by the
 * candidate pickers below. Higher score = stronger match; 0 means no signal at all.
 */
function scoreCategories(topic) {
  const topicLower = topic.toLowerCase();
  const tokens = topicLower.split(/\W+/).filter(Boolean);

  return CATALOG.map((cat) => {
    let score = 0;
    for (const kw of cat.keywords) {
      if (topicLower.includes(kw)) score += 3;
      for (const t of tokens) if (kw.includes(t)) score += 1;
    }
    if (cat.category.toLowerCase().includes(topicLower)) score += 5;
    return { cat, score };
  }).sort((a, b) => b.score - a.score);
}

/**
 * Pick candidate feeds for a topic by scoring categories against the topic phrase.
 *
 * Returns up to `limit` candidates from the highest-scoring category, falling through
 * to lower-scoring categories if a category lacks enough feeds. Pure function — no
 * external state, deterministic ordering.
 *
 * NOTE: this legacy picker will pad with the first (score-0) category when nothing
 * matches. Prefer `matchedCandidatesForTopic` for discovery — it never pads with
 * unrelated feeds.
 */
export function candidatesForTopic(topic, { limit = 8 } = {}) {
  const scored = scoreCategories(topic);

  const out = [];
  for (const { cat, score } of scored) {
    if (score === 0 && out.length > 0) break;
    for (const f of cat.feeds) {
      out.push({ ...f, category: cat.category });
      if (out.length >= limit) return out;
    }
  }
  return out;
}

/**
 * Like `candidatesForTopic`, but ONLY returns feeds from categories that actually
 * matched the topic (score > 0). When nothing in the catalog matches the topic
 * (e.g. "soccer"), this returns `[]` rather than padding the list with unrelated
 * feeds from the first category — so the caller can fall back to AI web discovery.
 */
export function matchedCandidatesForTopic(topic, { limit = 8 } = {}) {
  const scored = scoreCategories(topic);

  const out = [];
  for (const { cat, score } of scored) {
    if (score === 0) break; // sorted desc — once we hit 0, the rest are 0 too.
    for (const f of cat.feeds) {
      out.push({ ...f, category: cat.category });
      if (out.length >= limit) return out;
    }
  }
  return out;
}
