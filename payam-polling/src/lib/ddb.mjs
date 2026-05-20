// Shared DynamoDB clients. The Document client marshals plain JS values to
// AttributeValue maps so handlers don't have to.

import { DynamoDBClient } from '@aws-sdk/client-dynamodb';
import { DynamoDBDocumentClient } from '@aws-sdk/lib-dynamodb';

const region = process.env.AWS_REGION ?? 'us-west-2';

export const ddbBase = new DynamoDBClient({ region });
export const ddb = DynamoDBDocumentClient.from(ddbBase, {
  marshallOptions: { removeUndefinedValues: true, convertClassInstanceToMap: true },
});

export const TABLES = {
  registry: process.env.REGISTRY_TABLE,
  items: process.env.ITEMS_TABLE,
  userFeeds: process.env.USER_FEEDS_TABLE,
  userItemState: process.env.USER_ITEM_STATE_TABLE,
};

export const ITEMS_BY_FETCHED_INDEX = process.env.ITEMS_BY_FETCHED_INDEX ?? 'feedId-fetchedAt-index';
