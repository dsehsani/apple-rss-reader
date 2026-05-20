workspace "OpenRSS — Feed Polling Flow" "Focused view on how centralized cloud polling replaces per-device RSS fetching." {

    model {

        # People
        freeUser    = person "Free User"    "Device polls RSS feeds directly. BGTask fires every 15-30min (iOS-controlled)."
        premiumUser = person "Premium User" "Cloud poller runs every 5min on a guaranteed server schedule."

        # External
        feedServers = softwareSystem "RSS Feed Servers" "The Verge, Hacker News, NYT, etc." "External"

        # iOS App (focused — only polling-relevant containers)
        iosApp = softwareSystem "OpenRSS iOS App" "On-device RSS reader." {

            bgTask       = container "BGTaskScheduler"       "Registered as com.openrss.riverRefresh. iOS controls when it fires — unreliable for Premium refresh targets." "iOS BGTask" {
                tags "iOS"
            }
            feedIngest   = container "FeedIngestService"     "Routes by source type: free users fetch RSS directly, Premium users call CloudFeedSyncService." "Swift" {
                tags "iOS"
            }
            cloudSync    = container "CloudFeedSyncService"  "NEW — calls GET /v1/river since timestamp. Gets pre-fetched delta back in under 200ms." "Swift" {
                tags "iOS"
            }
            sqliteStore  = container "SQLiteStore"           "feed_items table. upsertFeedItems writes new items. Pipeline reads from here." "SQLite3" {
                tags "iOS" "Database"
            }
            pipeline     = container "RiverPipeline"         "Cluster, RateGate, Decay, Snapshot — all on-device. Unchanged by cloud." "Swift / Combine" {
                tags "iOS"
            }
        }

        # Cloud (focused — only polling-relevant components)
        cloudBackend = softwareSystem "OpenRSS Cloud (AWS)" "Centralized feed polling engine." {

            apiGateway    = container "API Gateway"          "Routes GET /v1/river to river-sync Lambda." "AWS API Gateway" {
                tags "Gateway"
            }
            eventBridge   = container "EventBridge"          "Rule 1: every 5min for feeds with Premium subscribers. Rule 2: every 30min for all others." "AWS EventBridge" {
                tags "Scheduler"
            }
            pollerLambda  = container "feed-poller"          "Fetches each unique feed URL once via conditional GET. Diffs against last fetch. Writes only new items to DynamoDB." "AWS Lambda" {
                tags "Lambda"
            }
            syncLambda    = container "river-sync"           "Joins user-feeds, feed-items, user-item-state. Returns only items the device hasn't seen yet." "AWS Lambda" {
                tags "Lambda"
            }
            feedRegistry  = container "feed-registry"        "feedURL, etag, lastModified, lastFetched, subscriberCount. One row per unique feed URL." "DynamoDB" {
                tags "Database"
            }
            feedItemsTable = container "feed-items"          "One row per article, shared across ALL subscribers. Not per-user — content stored once." "DynamoDB" {
                tags "Database"
            }
            userFeedsTable = container "user-feeds"          "userId + feedId mapping. Tells river-sync which feeds belong to which user." "DynamoDB" {
                tags "Database"
            }
            userStateTable = container "user-item-state"     "userId + itemId + isRead + isBookmarked. Tiny rows. Per-user state only." "DynamoDB" {
                tags "Database"
            }
        }

        # Free user flow — device fetches directly
        freeUser    -> iosApp       "Opens app or BGTask fires"
        bgTask      -> feedIngest   "Triggers refresh cycle"
        feedIngest  -> feedServers  "Free: direct HTTP fetch per feed per device — N users x M feeds requests"
        feedIngest  -> sqliteStore  "Writes parsed FeedItems after dedup"
        sqliteStore -> pipeline     "Pipeline reads items, runs cluster/decay/snapshot"

        # Premium user flow — cloud already fetched
        premiumUser  -> iosApp      "Opens app or BGTask fires"
        bgTask       -> cloudSync   "Premium: triggers CloudFeedSyncService instead"
        cloudSync    -> apiGateway  "GET /v1/river?since=timestamp — JWT in header"
        apiGateway   -> syncLambda  "Routes to river-sync"
        syncLambda   -> userFeedsTable "Looks up user feed subscriptions"
        syncLambda   -> feedItemsTable "Fetches new items since timestamp"
        syncLambda   -> userStateTable "Attaches isRead/isBookmarked state"
        cloudSync    -> sqliteStore "Writes returned FeedItem delta via upsertFeedItems"
        sqliteStore  -> pipeline    "Same pipeline — no changes needed"

        # Server-side polling (runs independently of device)
        eventBridge  -> pollerLambda  "Fires on schedule — server controlled, not iOS"
        pollerLambda -> feedRegistry  "Reads last etag and lastModified per feed"
        pollerLambda -> feedServers   "1 request per unique feed URL regardless of subscriber count"
        pollerLambda -> feedRegistry  "Updates etag, lastModified, lastFetched after fetch"
        pollerLambda -> feedItemsTable "Writes only new items — diff against previous fetch"
    }

    views {

        container iosApp "iOSPolling" {
            include *
            autoLayout tb
            title "Feed Polling — iOS App (Free vs Premium)"
            description "Free users fetch RSS per-device. Premium users receive a pre-computed delta from the cloud poller."
        }

        container cloudBackend "CloudPolling" {
            include *
            autoLayout tb
            title "Feed Polling — Cloud Engine"
            description "EventBridge fires feed-poller on schedule. One fetch per unique feed URL. All users share the same item store."
        }

        systemContext iosApp "PollingContext" {
            include *
            autoLayout lr
            title "Polling — System Context"
            description "How the device, cloud, and feed servers relate for the polling use case."
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
            element "Database" {
                shape cylinder
                background #E8B44B
                color #1C1C1E
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
