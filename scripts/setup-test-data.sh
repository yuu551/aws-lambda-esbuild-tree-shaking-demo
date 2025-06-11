#!/bin/bash

# テストデータ作成スクリプト
set -e

echo "Setting up test data for Lambda functions..."

REGION=${AWS_DEFAULT_REGION:-us-east-1}
USERS_TABLE="sample-users-table"

# テストユーザーの作成
echo "Creating test user..."
aws dynamodb put-item \
  --region "$REGION" \
  --table-name "$USERS_TABLE" \
  --item '{
    "id": {"S": "test-user-123"},
    "email": {"S": "test@example.com"},
    "name": {"S": "Test User"},
    "status": {"S": "active"},
    "billingPlan": {"S": "standard"},
    "notificationSettings": {
      "M": {
        "email": {"BOOL": true},
        "sms": {"BOOL": false},
        "push": {"BOOL": true}
      }
    },
    "createdAt": {"S": "'$(date -u +"%Y-%m-%dT%H:%M:%S.%3NZ")'"},
    "updatedAt": {"S": "'$(date -u +"%Y-%m-%dT%H:%M:%S.%3NZ")'"}
  }'

echo "Test data created successfully!"
echo "Test user ID: test-user-123"