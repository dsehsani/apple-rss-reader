workspace "OpenRSS — Data Flow (Free vs Premium)" "Dynamic views showing the step-by-step sequence of what happens when a free user vs premium user refreshes their feed and opens an article." {

    model {

        freeUser    = person "Free User"    "Device does all the work. Zero cloud calls."
        premiumUser = person "Premium User" "Cloud already fetched feeds. Device just syncs a delta."

        feedServers = softwareSystem "RSS Feed Servers" "The Verge, Hacker News, NYT, etc." "External"

        iosApp = softwareSystem "OpenRSS iOS App" "" {

            bgTask          = container "BGTaskScheduler"        "iOS background task. Fires every 15-30min (iOS-controlled, not guaranteed)." "iOS BGTask" {
                tags "iOS"
            }
            feedIngest      = container "FeedIngestService"      "Free path: fetches RSS directly. Premium path: calls CloudFeedSyncService." "Swift" {
                tags "iOS"
            }
            cloudSync       = container "CloudFeedSyncService"   "Premium only. GET /v1/river since timestamp. Returns pre-fetched delta in under 200ms." "Swift" {
                tags "iOS"
            }
            sqliteStore     = container "SQLiteStore"            "feed_items table. All pipeline stages read and write here." "SQLite3" {
                tags "iOS" "Database"
            }
            riverPipeline   = container "RiverPipeline"          "Cluster, RateGate, Decay, Snapshot. On-device. Unchanged by cloud." "Swift / Combine" {
                tags "iOS"
            }
            articlePipeline = container "ArticlePipelineService" "L0 cloud, L1 NSCache, L2 SwiftData, L3 WKWebView. Tries cheapest first." "Swift" {
                tags "iOS"
            }
            wkWebView       = container "WKWebView + Readability" "Last resort. Loads live URL, waits 2.5s for JS, runs Readability. Takes 2-20 seconds." "WKWebView" {
                tags "iOS" "Slow"
            }
            swiftUI         = container "SwiftUI Views"          "TodayView, ArticleReaderView. Observes pipeline output." "Swift / SwiftUI" {
                tags "iOS"
            }
        }

        cloudBackend = softwareSystem "OpenRSS Cloud (AWS)" "" {

            apiGateway      = container "API Gateway"            "Entry point for all Premium app-to-cloud traffic." "AWS API Gateway" {
                tags "Gateway"
            }
            syncLambda      = container "river-sync Lambda"      "Joins user-feeds, feed-items, user-item-state. Returns delta since timestamp." "AWS Lambda" {
                tags "Lambda"
            }
            extractLambda   = container "extraction-cache Lambda" "Checks DynamoDB. On hit returns S3 content. On miss runs Puppeteer." "AWS Lambda" {
                tags "Lambda"
            }
            feedItemsTable  = container "feed-items (DynamoDB)"  "Articles already fetched by server-side poller. Shared across all users." "DynamoDB" {
                tags "Database"
            }
            extractionStore = container "openrss-extractions (S3)" "Cached ContentNode JSON. 72hr TTL." "AWS S3" {
                tags "Storage"
            }
        }

        # Required static relationships for dynamic views to reference
        bgTask          -> feedIngest       "Triggers"
        feedIngest      -> feedServers      "Free: HTTP GET feed.xml"
        feedIngest      -> cloudSync        "Premium: delegates to cloud sync"
        cloudSync       -> apiGateway       "GET /v1/river since timestamp"
        apiGateway      -> syncLambda       "Routes"
        syncLambda      -> feedItemsTable   "Reads new items"
        cloudSync       -> sqliteStore      "upsertFeedItems"
        feedIngest      -> sqliteStore      "upsertFeedItems"
        sqliteStore     -> riverPipeline    "Items read by pipeline"
        riverPipeline   -> swiftUI          "Snapshot published"
        swiftUI         -> articlePipeline  "process(item) on tap"
        articlePipeline -> apiGateway       "GET /v1/extractions/sha256"
        apiGateway      -> extractLambda    "Routes"
        extractLambda   -> extractionStore  "Fetches cached ContentNode JSON"
        articlePipeline -> wkWebView        "Fallback on cloud miss"
        wkWebView       -> feedServers      "Loads live article URL"
        articlePipeline -> swiftUI          "Returns ExtractedArticle"
    }

    views {

        # ── Dynamic View 1: Free User — Feed Refresh ─────────────────────────
        dynamic iosApp "FreeUserRefresh" "Free User: what happens step by step when BGTask fires" {
            bgTask        -> feedIngest      "1. BGTask fires (iOS decides when)"
            feedIngest    -> feedServers     "2. HTTP GET feed.xml per feed (N requests per device)"
            feedIngest    -> sqliteStore     "3. Parse, dedup, upsertFeedItems"
            sqliteStore   -> riverPipeline   "4. Pipeline reads items"
            riverPipeline -> swiftUI         "5. Snapshot published — TodayView updates"
            autoLayout tb
            title "Free User — Feed Refresh Sequence"
            description "Every subscribed feed is fetched directly from the device. BGTask timing is iOS-controlled."
        }

        # ── Dynamic View 2: Premium User — Feed Refresh ───────────────────────
        dynamic iosApp "PremiumUserRefresh" "Premium User: feed refresh delegates to cloud" {
            bgTask     -> feedIngest      "1. BGTask fires (or user opens app)"
            feedIngest -> cloudSync       "2. Source type is Premium — delegates to CloudFeedSyncService"
            cloudSync  -> apiGateway      "3. GET /v1/river?since=timestamp (JWT in header)"
            apiGateway -> syncLambda      "4. Routes to river-sync Lambda"
            syncLambda -> feedItemsTable  "5. Reads items already fetched by server-side poller"
            cloudSync  -> sqliteStore     "6. upsertFeedItems with returned delta (under 200ms)"
            sqliteStore -> riverPipeline  "7. Pipeline reads items — same as free user"
            riverPipeline -> swiftUI      "8. Snapshot published — TodayView updates"
            autoLayout tb
            title "Premium User — Feed Refresh Sequence"
            description "Cloud already fetched all feeds on schedule. Device just receives a tiny delta. BGTask unreliability stops mattering."
        }

        # ── Dynamic View 3: Free User — Article Open ─────────────────────────
        dynamic iosApp "FreeUserArticle" "Free User: opening an article — on-device extraction only" {
            swiftUI         -> articlePipeline "1. User taps article"
            articlePipeline -> wkWebView       "2. No cloud cache — loads live URL in WKWebView"
            wkWebView       -> feedServers     "3. Fetches article page (JS renders — 2.5s wait)"
            articlePipeline -> swiftUI         "4. ExtractedArticle returned (2-20 seconds total)"
            autoLayout tb
            title "Free User — Article Open Sequence"
            description "No cloud cache available. Every article open runs the full WKWebView + Readability pipeline. Takes 2-20 seconds."
        }

        # ── Dynamic View 4: Premium User — Article Open (cache hit) ──────────
        dynamic iosApp "PremiumUserArticle" "Premium User: opening an article — cloud cache hit" {
            swiftUI         -> articlePipeline  "1. User taps article"
            articlePipeline -> apiGateway       "2. L0: GET /v1/extractions/sha256(url)"
            apiGateway      -> extractLambda    "3. Routes to extraction-cache Lambda"
            extractLambda   -> extractionStore  "4. Cache hit — fetches ContentNode JSON from S3"
            articlePipeline -> swiftUI          "5. ExtractedArticle returned (~80ms total)"
            autoLayout tb
            title "Premium User — Article Open Sequence (Cache Hit)"
            description "Another user already triggered extraction. This user gets the result instantly from S3 via DynamoDB index lookup."
        }

        styles {
            element "Person" {
                shape person
                background #0A84FF
                color #ffffff
            }
            element "External" {
                background #6C6C70
                color #ffffff
            }
            element "Software System" {
                background #1C1C1E
                color #ffffff
            }
            element "iOS" {
                background #2C2C2E
                color #ffffff
            }
            element "Slow" {
                background #FF453A
                color #ffffff
            }
            element "Lambda" {
                shape hexagon
                background #FF9500
                color #1C1C1E
            }
            element "Database" {
                shape cylinder
                background #E8B44B
                color #1C1C1E
            }
            element "Storage" {
                shape cylinder
                background #34C759
                color #ffffff
            }
            element "Gateway" {
                background #BF5AF2
                color #ffffff
            }
        }
    }
}
