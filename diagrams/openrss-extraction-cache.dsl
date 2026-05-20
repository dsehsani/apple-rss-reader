workspace "OpenRSS — Article Extraction Cache" "Focused view on how the shared cloud extraction cache replaces per-device WKWebView extraction." {

    model {

        # People
        userA = person "User A"  "First person to open a given article. Pays extraction cost once."
        userB = person "User B"  "Any subsequent user opening the same article. Gets result instantly from cache."

        # External
        articleServers = softwareSystem "Article Web Servers" "The live article pages. JS-rendered sites, possible paywalls after publication." "External"

        # iOS App (focused — only extraction-relevant containers)
        iosApp = softwareSystem "OpenRSS iOS App" "On-device RSS reader." {

            articleView     = container "ArticleReaderView"       "SwiftUI view. Calls ArticlePipelineService.process on open." "Swift / SwiftUI" {
                tags "iOS"
            }
            articlePipeline = container "ArticlePipelineService"  "Multi-level cache: L0 cloud, L1 NSCache, L2 SwiftData, L3 WKWebView fallback." "Swift" {
                tags "iOS"
            }
            nsCache         = container "L1 — NSCache"            "In-memory. 30MB limit, 50 items. Instant. Lost on app kill." "NSCache" {
                tags "iOS" "Cache"
            }
            swiftDataCache  = container "L2 — SwiftData"          "On-disk. Survives app relaunch. Per-device only." "SwiftData" {
                tags "iOS" "Cache"
            }
            webView         = container "L3 — WKWebView"          "Fallback only. Loads live URL, waits 2.5s for JS, runs Readability.js. Takes 2-20 seconds." "WKWebView / Readability.js" {
                tags "iOS" "Slow"
            }
        }

        # Cloud (focused — extraction cache only)
        cloudBackend = softwareSystem "OpenRSS Cloud (AWS)" "Shared extraction cache. First user pays cost, everyone else gets instant result." {

            apiGateway      = container "API Gateway"             "Routes GET /v1/extractions/sha256 to extraction-cache Lambda." "AWS API Gateway" {
                tags "Gateway"
            }
            extractLambda   = container "extraction-cache Lambda" "Checks DynamoDB index. On hit: fetches from S3 and returns. On miss: runs Puppeteer, stores result, returns." "AWS Lambda / Puppeteer" {
                tags "Lambda"
            }
            extractionIndex = container "extraction-index"        "DynamoDB. urlHash maps to s3Key. TTL auto-expires at 72hr." "DynamoDB" {
                tags "Database"
            }
            extractionStore = container "openrss-extractions"     "S3 bucket. urlHash.json files — ContentNode JSON arrays. Same format ArticlePipelineService produces on-device." "AWS S3" {
                tags "Storage"
            }
        }

        # User A — first to open the article (cache miss)
        userA -> articleView     "Taps article"
        articleView -> articlePipeline "process(item)"
        articlePipeline -> nsCache    "L1 miss — not in memory"
        articlePipeline -> swiftDataCache "L2 miss — not on disk"
        articlePipeline -> apiGateway "L0: GET /v1/extractions/sha256(url)"
        apiGateway -> extractLambda  "Routes to Lambda"
        extractLambda -> extractionIndex "Cache miss — no entry in DynamoDB"
        extractLambda -> articleServers  "Fetches article URL via Puppeteer (2-5s)"
        extractLambda -> extractionIndex "Writes urlHash, s3Key, ttl=72hr"
        extractLambda -> extractionStore "Writes ContentNode JSON to S3"
        extractLambda -> articlePipeline "Returns ContentNode array (~3-6s total first time)"

        # User B — any subsequent user (cache hit, ~80ms)
        userB -> articleView      "Taps same article"
        articleView -> articlePipeline "process(item)"
        articlePipeline -> apiGateway "L0: GET /v1/extractions/sha256(url)"
        apiGateway -> extractLambda   "Routes to Lambda"
        extractLambda -> extractionIndex "Cache HIT — entry found in DynamoDB"
        extractLambda -> extractionStore "Fetches ContentNode JSON from S3"
        extractLambda -> articlePipeline "Returns ContentNode array (~80ms)"
    }

    views {

        # Main view — iOS extraction pipeline with cloud L0 layer
        container iosApp "ExtractioniOS" {
            include *
            autoLayout tb
            title "Article Extraction — iOS Cache Layers"
            description "L0 cloud check sits in front of existing L1/L2/L3 cache layers. Cache miss falls through to WKWebView as before."
        }

        # Cloud extraction cache internals
        container cloudBackend "ExtractionCloud" {
            include *
            autoLayout tb
            title "Article Extraction — Cloud Cache"
            description "DynamoDB index + S3 storage. First user triggers Puppeteer extraction. Every subsequent user gets the cached result."
        }

        # System context — who calls what
        systemContext iosApp "ExtractionContext" {
            include *
            autoLayout lr
            title "Article Extraction — System Context"
            description "iOS app checks cloud cache before falling back to on-device WKWebView extraction."
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
            element "Cache" {
                background #30D158
                color #1C1C1E
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
