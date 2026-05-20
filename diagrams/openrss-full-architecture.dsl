workspace "OpenRSS Cloud Architecture" "C4 model — full system including iOS app, AWS cloud backend, and external dependencies." {

    model {

        # People
        freeUser    = person "Free User"    "Uses the full on-device RSS experience. Zero calls to our cloud."
        premiumUser = person "Premium User" "Pays $5.99/mo. Gets cloud polling, extraction cache, integrations, and AI features."

        # External systems
        feedServers  = softwareSystem "RSS Feed Servers"        "The Verge, Hacker News, NYT, etc. Serve standard RSS/Atom XML." "External"
        appleIAP     = softwareSystem "Apple StoreKit / IAP"    "Validates in-app purchase receipts. Confirms Premium subscription status." "External"
        anthropicAPI = softwareSystem "Anthropic API"           "Claude Haiku. Powers Discovery Agent Tier 3 and article summaries." "External"
        iCloud       = softwareSystem "Apple iCloud / CloudKit" "Syncs SwiftData models across devices. Free — Apple infrastructure." "External"
        apns         = softwareSystem "Apple APNs"              "Silent push notifications. Wakes device on new content." "External"

        # iOS App
        iosApp = softwareSystem "OpenRSS iOS App" "Native SwiftUI RSS reader. On-device pipeline: ingest, cluster, decay-score, snapshot." {

            swiftUI         = container "SwiftUI Views"           "TodayView, ArticleReaderView, DiscoverView, SettingsView." "Swift / SwiftUI" {
                tags "iOS"
            }
            riverPipeline   = container "RiverPipeline"           "5-stage pipeline: FeedIngest, SemanticCluster, RateGate, DecayScore, Snapshot. Runs via BGTask and foreground refresh." "Swift / Combine" {
                tags "iOS"
            }
            sqliteStore     = container "SQLiteStore"             "WAL-mode SQLite. Tables: feed_items, source_affinity, interaction_events." "SQLite3" {
                tags "iOS" "Database"
            }
            swiftData       = container "SwiftData Store"         "CloudKit-backed persistence: FolderModel, FeedModel, UserProfile, UserPreferences." "SwiftData / CloudKit" {
                tags "iOS" "Database"
            }
            articlePipeline = container "ArticlePipelineService"  "Extraction cache: L0 cloud ~80ms, L1 NSCache instant, L2 SwiftData fast, L3 WKWebView 2-20s fallback." "Swift / WKWebView" {
                tags "iOS"
            }
            authManager     = container "AuthenticationManager"   "Sign in with Apple lifecycle. Holds JWT in Keychain. Configures CloudKit on auth state." "Swift / AuthenticationServices" {
                tags "iOS"
            }
            storeKitSvc     = container "StoreKitService"         "StoreKit 2 products, purchase flow, Transaction.updates listener. Triggers JWT refresh on renewal." "Swift / StoreKit 2" {
                tags "iOS"
            }
            cloudSync       = container "CloudFeedSyncService"    "NEW — Premium only. Calls GET /v1/river since timestamp. Writes FeedItem deltas to SQLiteStore." "Swift" {
                tags "iOS"
            }
            affinitySync    = container "AffinitySyncService"     "NEW — uploads source_affinity scores from SQLiteStore to cloud for AI personalization." "Swift" {
                tags "iOS"
            }
        }

        # Cloud Backend
        cloudBackend = softwareSystem "OpenRSS Cloud (AWS)" "Serverless backend. Lambda, API Gateway, Aurora PostgreSQL, DynamoDB, ECS, S3. Scales to zero when idle." {

            apiGateway     = container "API Gateway"           "Entry point for all app-to-cloud traffic. Routes to Lambdas. Validates JWT on Premium endpoints." "AWS API Gateway" {
                tags "Gateway"
            }
            authLambda     = container "auth-validate-receipt" "Validates StoreKit receipt with Apple. Writes user tier to DynamoDB. Returns RS256 JWT with 24hr expiry." "AWS Lambda" {
                tags "Lambda"
            }

            # Feed polling — SQS fan-out (Correction 3)
            orchestratorLambda = container "feed-poller-orchestrator" "EventBridge-triggered. Queries Aurora for feeds due for refresh. Writes one SQS message per feed URL." "AWS Lambda" {
                tags "Lambda"
            }
            sqsQueue       = container "SQS Feed Queue"       "Fan-out queue. One message per feed URL. Provides backpressure if feed servers are slow." "AWS SQS" {
                tags "Queue"
            }
            workerLambda   = container "feed-poller-worker"    "SQS-triggered. Fetches one feed via conditional GET. Diffs against previous fetch. Writes only new items to Aurora." "AWS Lambda" {
                tags "Lambda"
            }

            syncLambda     = container "river-sync"            "Called by device. JOINs user_feeds, feed_items, user_item_state in Aurora PostgreSQL. Returns FeedItem delta since timestamp." "AWS Lambda" {
                tags "Lambda"
            }

            # Article extraction — ECS, not Lambda (Correction 2)
            extractLambda  = container "extraction-cache"      "Thin proxy. Checks DynamoDB for cached extraction by URL hash. On hit, returns from S3 (~80ms). On miss, dispatches to ECS via SQS." "AWS Lambda" {
                tags "Lambda"
            }
            ecsExtraction  = container "ECS Extraction Service" "Fargate tasks with warm Puppeteer pool. SQS-triggered. Runs Readability.js, stores ContentNode JSON in S3. No cold starts. Scales via SQS queue depth." "AWS ECS Fargate" {
                tags "ECS"
            }
            extractionSQS  = container "Extraction SQS Queue"  "Buffers extraction requests from Lambda to ECS workers." "AWS SQS" {
                tags "Queue"
            }

            discoverLambda = container "discovery-agent"       "Receives query and user affinity vector. Tier 2: vector search on DynamoDB feed index. Tier 3: escalates to Claude Haiku." "AWS Lambda" {
                tags "Lambda"
            }
            summaryLambda  = container "article-summary"       "Checks DynamoDB AI cache by URL hash. On miss, calls Claude Haiku. Stores result with 72hr TTL." "AWS Lambda" {
                tags "Lambda"
            }
            eventBridge    = container "EventBridge Scheduler" "Triggers orchestrator Lambda every 5 minutes." "AWS EventBridge" {
                tags "Scheduler"
            }

            # APNs delivery (Correction 4)
            snsService     = container "SNS → APNs"           "Fires silent push (content-available: 1) to subscriber devices when new items arrive. Free via APNs." "AWS SNS" {
                tags "Queue"
            }

            # --- Aurora PostgreSQL (relational — Correction 1) ---
            auroraDB       = container "Aurora PostgreSQL"    "Aurora Serverless v2. Tables: feed_registry, feed_items, user_feeds, user_item_state. Scales to zero ACUs when idle. Supports JOIN queries for delta sync." "Aurora Serverless v2" {
                tags "RelationalDB"
            }

            # --- DynamoDB (key-value) ---
            usersTable      = container "users"            "userId, tier, expiresAt. Written by auth Lambda. Read by API Gateway authorizer." "DynamoDB" {
                tags "Database"
            }
            deviceTokens    = container "device-tokens"    "userId, [apnsToken], updatedAt. Stores APNs tokens for silent push. Multiple tokens per user for multi-device." "DynamoDB" {
                tags "Database"
            }
            extractionIndex = container "extraction-index" "urlHash, s3Key, cachedAt, ttl. Index for extraction cache lookups. Auto-deletes at 72hr." "DynamoDB" {
                tags "Database"
            }
            aiCache         = container "ai-result-cache"  "queryHash, result, ttl. Shared across all users — same query never hits Claude twice within 72hr." "DynamoDB" {
                tags "Database"
            }
            feedIndex       = container "feed-index"       "feedId, name, url, category, descriptionEmbedding. 10k+ curated feeds with embeddings for Discovery Agent Tier 2." "DynamoDB" {
                tags "Database"
            }
            extractionStore = container "openrss-extractions" "S3 bucket. urlHash.json files — JSON-serialized ContentNode arrays. Same schema ArticlePipelineService produces on-device." "AWS S3" {
                tags "Storage"
            }
        }

        # People -> Systems
        freeUser    -> iosApp "Reads RSS feeds, manages subscriptions, browses Discover"
        premiumUser -> iosApp "Same as free plus cloud polling, fast extraction, integrations, AI"

        # iOS App -> External
        iosApp -> iCloud       "Syncs folders, feeds, user profile via CloudKit (Apple infrastructure)"
        iosApp -> feedServers  "Free users: device fetches RSS directly via FeedIngestService"
        iosApp -> cloudBackend "Premium users: JWT-authenticated API calls"

        # iOS containers -> each other
        swiftUI         -> riverPipeline  "Subscribes to RiverPipeline.snapshotPublisher"
        swiftUI         -> articlePipeline "Calls process on article open"
        riverPipeline   -> sqliteStore    "All pipeline stages read and write feed_items, source_affinity"
        riverPipeline   -> cloudSync      "Premium: triggers cloud sync before ingest stage"
        cloudSync       -> sqliteStore    "Writes FeedItem deltas via upsertFeedItems"
        articlePipeline -> cloudSync      "L0: checks cloud extraction cache"
        authManager     -> swiftData      "Reads and writes UserProfile, configures CloudKit container"
        storeKitSvc     -> authManager    "Notifies on verified transaction, triggers JWT refresh"
        affinitySync    -> sqliteStore    "Reads source_affinity rows to upload"
        swiftUI         -> swiftData      "Query for FolderModel, FeedModel, UserPreferences"

        # iOS -> Cloud
        storeKitSvc     -> apiGateway "POST /v1/auth/validate — sends receipt, receives JWT"
        cloudSync       -> apiGateway "GET /v1/river since epoch — fetch FeedItem delta"
        cloudSync       -> apiGateway "POST /v1/state — sync isRead and isBookmarked"
        articlePipeline -> apiGateway "GET /v1/extractions/sha256 — fetch cached extraction"
        swiftUI         -> apiGateway "GET /v1/discovery?q= — Discovery Agent"
        swiftUI         -> apiGateway "GET /v1/summaries/sha256 — article summary"
        affinitySync    -> apiGateway "POST /v1/affinity — upload source affinity scores"

        # API Gateway -> Lambdas
        apiGateway -> authLambda          "POST /v1/auth/validate"
        apiGateway -> syncLambda          "GET /v1/river"
        apiGateway -> extractLambda       "GET /v1/extractions"
        apiGateway -> discoverLambda      "GET /v1/discovery"
        apiGateway -> summaryLambda       "GET /v1/summaries"

        # Feed polling flow (Correction 3: SQS fan-out)
        eventBridge        -> orchestratorLambda "Scheduled trigger — every 5 minutes"
        orchestratorLambda -> auroraDB           "Queries feed_registry for feeds due for refresh"
        orchestratorLambda -> sqsQueue           "Writes one SQS message per feed URL"
        sqsQueue           -> workerLambda       "Auto-scales up to 1,000 concurrent workers"
        workerLambda       -> feedServers        "HTTP conditional GET per unique feed URL"
        workerLambda       -> auroraDB           "Writes new FeedItems after diff to feed_items"

        # APNs silent push flow (Correction 4)
        workerLambda       -> deviceTokens       "Reads subscriber device tokens"
        workerLambda       -> snsService         "Triggers silent push for subscribers of updated feeds"
        snsService         -> apns               "Delivers content-available: 1 silent push"

        # Auth Lambda
        authLambda     -> usersTable     "Writes userId, tier, expiresAt"
        authLambda     -> appleIAP       "Validates StoreKit receipt"

        # Sync Lambda -> Aurora (Correction 1: relational JOINs)
        syncLambda     -> auroraDB       "JOINs user_feeds + feed_items + user_item_state for delta"

        # Extraction flow (Correction 2: ECS, not Lambda-based Puppeteer)
        extractLambda  -> extractionIndex "Checks cached extraction by URL hash"
        extractLambda  -> extractionStore "Reads ContentNode JSON from S3 on cache hit"
        extractLambda  -> extractionSQS  "On cache miss: dispatches URL to extraction queue"
        extractionSQS  -> ecsExtraction  "Triggers Fargate task from queue"
        ecsExtraction  -> extractionStore "Writes ContentNode JSON to S3"
        ecsExtraction  -> extractionIndex "Writes index entry to DynamoDB"

        # AI Lambdas
        discoverLambda -> feedIndex      "Vector similarity search on feed descriptions"
        discoverLambda -> aiCache        "Checks and stores Discovery Agent results"
        discoverLambda -> anthropicAPI   "Claude Haiku call on Tier 3 escalation"
        summaryLambda  -> aiCache        "Checks and stores summary results"
        summaryLambda  -> anthropicAPI   "Claude Haiku call on cache miss"
    }

    views {

        # View 1 — System Context (big picture, good for stakeholder slides)
        systemContext iosApp "SystemContext" {
            include *
            autoLayout lr
            title "OpenRSS — System Context"
            description "How OpenRSS relates to users, Apple, feed servers, and the cloud backend."
        }

        # View 2 — Cloud Backend internals
        container cloudBackend "CloudContainers" {
            include *
            autoLayout tb
            title "OpenRSS Cloud (AWS) — Containers"
            description "Lambda functions, Aurora PostgreSQL, DynamoDB tables, ECS extraction, SQS queues, S3, and API Gateway."
        }

        # View 3 — iOS App internals
        container iosApp "iOSContainers" {
            include *
            autoLayout tb
            title "OpenRSS iOS App — Containers"
            description "Service layer inside the app and how it connects to the cloud."
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
            element "Lambda" {
                shape hexagon
                background #FF9500
                color #1C1C1E
            }
            element "ECS" {
                shape hexagon
                background #30D158
                color #1C1C1E
            }
            element "RelationalDB" {
                shape cylinder
                background #0A84FF
                color #ffffff
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
            element "Queue" {
                background #FF375F
                color #ffffff
            }
            element "Gateway" {
                background #BF5AF2
                color #ffffff
            }
            element "Scheduler" {
                background #FF375F
                color #ffffff
            }
        }
    }
}
