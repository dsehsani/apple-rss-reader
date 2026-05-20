workspace "OpenRSS — API Contract" "Container view showing every API endpoint, which device component calls it, which Lambda handles it, and what data it touches. Corresponds to the API contract table in the architecture plan." {

    model {

        freeUser    = person "Free User"    "Never calls our cloud API. Zero endpoints used."
        premiumUser = person "Premium User" "Uses all six endpoints below."

        iosApp = softwareSystem "OpenRSS iOS App" "" {

            storeKitSvc     = container "StoreKitService"         "Calls /v1/auth/validate after a verified StoreKit 2 transaction." "Swift / StoreKit 2" {
                tags "iOS"
            }
            cloudSync       = container "CloudFeedSyncService"    "Calls /v1/river to pull feed delta. Calls /v1/state to push read/bookmark changes." "Swift" {
                tags "iOS"
            }
            articlePipeline = container "ArticlePipelineService"  "Calls /v1/extractions to check shared extraction cache before falling back to WKWebView." "Swift" {
                tags "iOS"
            }
            discoverView    = container "DiscoverView"            "Calls /v1/discovery for Discovery Agent Tier 2 and 3 queries." "Swift / SwiftUI" {
                tags "iOS"
            }
            articleView     = container "ArticleReaderView"       "Calls /v1/summaries when user taps the Summarize button." "Swift / SwiftUI" {
                tags "iOS"
            }
            affinitySync    = container "AffinitySyncService"     "Calls /v1/affinity to upload source affinity scores for AI personalization." "Swift" {
                tags "iOS"
            }
        }

        cloudBackend = softwareSystem "OpenRSS Cloud (AWS)" "" {

            apiGateway = container "API Gateway" "Base URL: https://api.openrss.app/v1. All requests require Authorization: Bearer JWT except /v1/auth/validate." "AWS API Gateway" {
                tags "Gateway"
            }

            # One container per endpoint — makes the diagram self-documenting
            authEndpoint    = container "POST /v1/auth/validate"    "Input: StoreKit receipt. Validates with Apple IAP. Writes userId + tier to DynamoDB users table. Returns RS256 JWT with 24hr expiry. Only endpoint callable without a JWT." "AWS Lambda" {
                tags "Lambda" "AuthEndpoint"
            }
            riverEndpoint   = container "GET /v1/river"             "Input: since (epoch timestamp) in query param. JWT required. Returns FeedItem array — only items newer than since that belong to the user. JOINs user_feeds + feed_items + user_item_state in Aurora PostgreSQL." "AWS Lambda" {
                tags "Lambda" "SyncEndpoint"
            }
            stateEndpoint   = container "POST /v1/state"            "Input: array of itemId + isRead + isBookmarked. JWT required. Writes to user_item_state in Aurora PostgreSQL. Cloud is source of truth for Premium read/bookmark state (Correction 5)." "AWS Lambda" {
                tags "Lambda" "SyncEndpoint"
            }
            extractEndpoint = container "GET /v1/extractions/:hash" "Input: SHA256 of article URL as path param. JWT required. Checks DynamoDB extraction-index. On hit, returns ContentNode JSON from S3 (~80ms). On miss, dispatches to ECS Fargate extraction service via SQS. 404 triggers on-device WKWebView fallback." "AWS Lambda" {
                tags "Lambda" "ExtractionEndpoint"
            }
            discoveryEndpoint = container "GET /v1/discovery"       "Input: q (query string) + optional affinity vector. JWT required. Tier 2: DynamoDB feed-index vector search. Tier 3: Claude Haiku if confidence low. Results cached 72hr in DynamoDB ai-result-cache." "AWS Lambda" {
                tags "Lambda" "AIEndpoint"
            }
            summaryEndpoint = container "GET /v1/summaries/:hash"   "Input: SHA256 of article URL as path param. JWT required. Returns plain-text summary + key points. Claude Haiku on cache miss. Cached 72hr in DynamoDB ai-result-cache." "AWS Lambda" {
                tags "Lambda" "AIEndpoint"
            }
            affinityEndpoint = container "POST /v1/affinity"        "Input: array of sourceId + affinityScore rows. JWT required. Writes to DynamoDB affinity store. Used to personalize Discovery Agent results." "AWS Lambda" {
                tags "Lambda" "AIEndpoint"
            }
        }

        # Who calls what
        freeUser        -> iosApp           "Uses app — never touches our cloud"

        premiumUser     -> storeKitSvc      "Subscribes via App Store"
        storeKitSvc     -> apiGateway       "POST /v1/auth/validate"
        apiGateway      -> authEndpoint     "Routes"

        premiumUser     -> cloudSync        "BGTask fires, APNs silent push received, or app opens"
        cloudSync       -> apiGateway       "GET /v1/river?since=timestamp"
        apiGateway      -> riverEndpoint    "Routes"
        cloudSync       -> apiGateway       "POST /v1/state"
        apiGateway      -> stateEndpoint    "Routes"

        premiumUser     -> articlePipeline  "Opens article"
        articlePipeline -> apiGateway       "GET /v1/extractions/sha256"
        apiGateway      -> extractEndpoint  "Routes"

        premiumUser     -> discoverView     "Types discovery query"
        discoverView    -> apiGateway       "GET /v1/discovery?q=query"
        apiGateway      -> discoveryEndpoint "Routes"

        premiumUser     -> articleView      "Taps Summarize"
        articleView     -> apiGateway       "GET /v1/summaries/sha256"
        apiGateway      -> summaryEndpoint  "Routes"

        affinitySync    -> apiGateway       "POST /v1/affinity"
        apiGateway      -> affinityEndpoint "Routes"
    }

    views {

        # All endpoints in one view
        container cloudBackend "AllEndpoints" {
            include *
            autoLayout tb
            title "API Contract — All Endpoints"
            description "Every cloud endpoint, what it accepts, what it returns, and which device component calls it."
        }

        # Auth endpoint only
        container cloudBackend "AuthEndpointView" {
            include ->authEndpoint->
            include storeKitSvc
            include apiGateway
            autoLayout lr
            title "API Contract — Auth Endpoint"
            description "POST /v1/auth/validate. The only endpoint callable without a JWT. Foundation for all Premium features."
        }

        # Feed sync endpoints
        container cloudBackend "SyncEndpoints" {
            include ->riverEndpoint->
            include ->stateEndpoint->
            include cloudSync
            include apiGateway
            autoLayout tb
            title "API Contract — Feed Sync Endpoints"
            description "GET /v1/river pulls new items via Aurora PostgreSQL JOIN. POST /v1/state pushes read and bookmark changes back. Cloud is source of truth for Premium item state."
        }

        # AI endpoints
        container cloudBackend "AIEndpoints" {
            include ->extractEndpoint->
            include ->discoveryEndpoint->
            include ->summaryEndpoint->
            include ->affinityEndpoint->
            include articlePipeline
            include discoverView
            include articleView
            include affinitySync
            include apiGateway
            autoLayout tb
            title "API Contract — AI and Extraction Endpoints"
            description "Extraction cache (DynamoDB + S3 + ECS Fargate), Discovery Agent, article summaries, and affinity upload."
        }

        styles {
            element "Person" {
                shape person
                background #0A84FF
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
            element "Gateway" {
                background #BF5AF2
                color #ffffff
            }
            element "AuthEndpoint" {
                shape hexagon
                background #34C759
                color #1C1C1E
            }
            element "SyncEndpoint" {
                shape hexagon
                background #0A84FF
                color #ffffff
            }
            element "ExtractionEndpoint" {
                shape hexagon
                background #FF9500
                color #1C1C1E
            }
            element "AIEndpoint" {
                shape hexagon
                background #BF5AF2
                color #ffffff
            }
        }
    }
}
