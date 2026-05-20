workspace "OpenRSS — Data Model" "Component-level view of every database table, what it stores, and which Lambda reads or writes it. Corresponds to the table map in the architecture plan." {

    model {

        # Lambdas as people/actors for this focused view
        authLambda        = person "auth-validate-receipt" "Validates StoreKit receipt. Issues JWT."
        orchestratorLambda = person "feed-poller-orchestrator" "Queries Aurora for feeds due. Writes URLs to SQS."
        workerLambda      = person "feed-poller-worker"   "Fetches one feed from SQS. Diffs and writes new items to Aurora."
        syncLambda        = person "river-sync"            "Assembles per-user delta for device via Aurora JOIN."
        extractLambda     = person "extraction-cache"      "Checks DynamoDB index. Dispatches to ECS on miss."
        discoverLambda    = person "discovery-agent"       "Runs feed discovery queries."
        summaryLambda     = person "article-summary"       "Runs AI summary requests."
        deviceApp         = person "iOS App"               "Reads and writes via API Gateway."

        # Infrastructure
        sqsQueue    = softwareSystem "SQS Feed Queue"         "Fan-out queue. One message per feed URL due for refresh." "Infrastructure"
        ecsService  = softwareSystem "ECS Extraction Service" "Fargate tasks with warm Puppeteer pool. SQS-triggered." "Infrastructure"

        # Apple as external
        appleIAP     = softwareSystem "Apple StoreKit / IAP" "Validates receipts." "External"
        anthropicAPI = softwareSystem "Anthropic API"        "Claude Haiku for AI features." "External"

        dataLayer = softwareSystem "OpenRSS Data Layer (Aurora + DynamoDB + S3)" "All persistent cloud storage for the OpenRSS backend." {

            # --- Aurora PostgreSQL (relational) ---

            feedRegistry = container "feed_registry" "Primary key: feed_url (TEXT). Fields: etag, last_modified, last_fetched_at, subscriber_count, velocity_tier. One row per unique feed URL across all users." "Aurora PostgreSQL" {
                tags "RelationalData"
            }

            feedItemsTable = container "feed_items" "Primary key: id (UUID). Fields: feed_id, title, link, published_at, fetched_at, excerpt, image_url, audio_url, author, velocity_tier. Index on (feed_id, published_at DESC). ONE row per article shared across ALL subscribers." "Aurora PostgreSQL" {
                tags "RelationalData"
            }

            userFeedsTable = container "user_feeds" "Primary key: (user_id, feed_id). Fields: added_at. Maps each user to the feeds they subscribe to." "Aurora PostgreSQL" {
                tags "RelationalData"
            }

            userStateTable = container "user_item_state" "Primary key: (user_id, item_id). Fields: is_read, is_bookmarked, updated_at. Tiny rows — only per-user state. Article content lives in feed_items." "Aurora PostgreSQL" {
                tags "RelationalData"
            }

            # --- DynamoDB (key-value) ---

            usersTable = container "users" "Primary key: userId. Fields: tier (free/premium/founding), expiresAt. Written on subscription. Read on every API call to verify tier." "DynamoDB" {
                tags "KeyValueData"
            }

            deviceTokens = container "device-tokens" "Primary key: userId. Fields: [apnsToken], updatedAt. Stores one or more APNs tokens per user for silent push delivery." "DynamoDB" {
                tags "KeyValueData"
            }

            extractionIndex = container "extraction-index" "Primary key: urlHash (SHA256 of article URL). Fields: s3Key, cachedAt, ttl. TTL field triggers auto-delete after 72 hours. Pointer to S3 — does not store content directly." "DynamoDB" {
                tags "KeyValueData"
            }

            aiCache = container "ai-result-cache" "Primary key: queryHash (SHA256 of query + top affinity feeds). Fields: result, cachedAt, ttl. Shared across ALL users — the same Discovery or summary query from any user hits this cache instead of Claude." "DynamoDB" {
                tags "KeyValueData"
            }

            feedIndex = container "feed-index" "Primary key: feedId. Fields: name, url, category, description, descriptionEmbedding (vector). 10,000+ curated feeds pre-embedded for Discovery Agent Tier 2 vector similarity search." "DynamoDB" {
                tags "KeyValueData"
            }

            # --- S3 ---

            extractionStore = container "openrss-extractions" "S3 bucket. Key: urlHash.json. Value: JSON-serialized ContentNode array — same format ArticlePipelineService produces on-device. Objects expire at 72hr via S3 lifecycle rule." "AWS S3" {
                tags "StorageData"
            }
        }

        # Who reads/writes what
        authLambda          -> usersTable       "Writes userId, tier, expiresAt on subscription verify"
        authLambda          -> appleIAP         "Validates receipt before writing"
        deviceApp           -> usersTable       "API Gateway reads tier to authorize Premium endpoints"

        orchestratorLambda  -> feedRegistry     "Reads to find feeds due for refresh"
        orchestratorLambda  -> sqsQueue         "Writes one SQS message per feed URL"
        workerLambda        -> sqsQueue         "Reads feed URLs from queue"
        workerLambda        -> feedRegistry     "Updates etag, lastModified, lastFetched after fetch"
        workerLambda        -> feedItemsTable   "Writes new FeedItems after diff — only items not already present"
        workerLambda        -> deviceTokens     "Reads subscriber device tokens to fire APNs silent push"

        deviceApp           -> userFeedsTable   "Writes on feed add or remove"
        syncLambda          -> userFeedsTable   "Reads to know which feeds belong to requesting user"
        syncLambda          -> feedItemsTable   "Reads items since requested timestamp via JOIN"
        syncLambda          -> userStateTable   "Reads isRead and isBookmarked to attach to delta"
        deviceApp           -> userStateTable   "Writes on article read or bookmark"

        extractLambda       -> extractionIndex  "Reads on every article open request. Writes index on cache miss."
        extractLambda       -> extractionStore  "Reads ContentNode JSON on cache hit."
        extractLambda       -> ecsService       "Dispatches to ECS Fargate on cache miss via SQS"
        ecsService          -> extractionStore  "Writes ContentNode JSON after Puppeteer extraction"
        ecsService          -> extractionIndex  "Writes index entry after extraction"

        discoverLambda      -> feedIndex        "Vector similarity search against descriptionEmbedding"
        discoverLambda      -> aiCache          "Reads on query. Writes result on Claude cache miss."
        discoverLambda      -> anthropicAPI     "Claude Haiku — only on Tier 3 escalation, after cache miss"

        summaryLambda       -> aiCache          "Reads on summary request. Writes on Claude cache miss."
        summaryLambda       -> anthropicAPI     "Claude Haiku — only on extraction cache miss"
    }

    views {

        # Full data layer — all tables and who touches them
        container dataLayer "FullDataModel" {
            include *
            autoLayout tb
            title "OpenRSS — Full Data Model"
            description "Aurora PostgreSQL tables, DynamoDB tables, and S3 bucket, with the Lambdas and services that read and write each one."
        }

        # Auth data only
        container dataLayer "AuthData" {
            include ->usersTable->
            include authLambda
            include deviceApp
            include appleIAP
            autoLayout lr
            title "Data Model — Auth and Entitlement"
            description "The users table (DynamoDB) and what reads and writes it."
        }

        # Polling data only (Aurora PostgreSQL)
        container dataLayer "PollingData" {
            include ->feedRegistry->
            include ->feedItemsTable->
            include ->userFeedsTable->
            include ->userStateTable->
            include ->deviceTokens->
            include orchestratorLambda
            include workerLambda
            include syncLambda
            include deviceApp
            include sqsQueue
            autoLayout tb
            title "Data Model — Feed Polling Tables (Aurora PostgreSQL)"
            description "The four relational tables that power the polling engine and per-user feed delivery, plus device tokens for APNs push."
        }

        # Extraction cache data only
        container dataLayer "ExtractionData" {
            include ->extractionIndex->
            include ->extractionStore->
            include extractLambda
            include ecsService
            include deviceApp
            autoLayout lr
            title "Data Model — Extraction Cache"
            description "DynamoDB index pointing to S3. ECS Fargate with Puppeteer pool on cache miss. TTL auto-expires at 72hr."
        }

        # AI data only
        container dataLayer "AIData" {
            include ->aiCache->
            include ->feedIndex->
            include discoverLambda
            include summaryLambda
            include anthropicAPI
            autoLayout lr
            title "Data Model — AI Cache and Feed Index"
            description "Shared AI result cache (DynamoDB) and the curated feed index used by Discovery Agent Tier 2."
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
            element "Infrastructure" {
                background #48484A
                color #ffffff
            }
            element "Software System" {
                background #1C1C1E
                color #ffffff
            }
            element "RelationalData" {
                shape cylinder
                background #0A84FF
                color #ffffff
            }
            element "KeyValueData" {
                shape cylinder
                background #E8B44B
                color #1C1C1E
            }
            element "StorageData" {
                shape cylinder
                background #34C759
                color #ffffff
            }
        }
    }
}
