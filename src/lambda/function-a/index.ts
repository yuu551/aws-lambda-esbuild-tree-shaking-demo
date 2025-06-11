import { DynamoDB } from '@aws-sdk/client-dynamodb';
import { DynamoDBDocument } from '@aws-sdk/lib-dynamodb';
import _ from 'lodash';
import { format } from 'date-fns';
import { getUserById } from '../../repositories/user-repository';

// DynamoDB クライアントの初期化
const client = new DynamoDB({});
const docClient = DynamoDBDocument.from(client);

export const handler = async (event: any) => {
  console.log('Function A - Event:', JSON.stringify(event, null, 2));
  
  try {
    // lodash を使った処理例
    const ids = _.map(event.records || [], 'id');
    console.log('Processing IDs:', ids);
    
    // date-fns を使った日付処理
    const currentDate = format(new Date(), 'yyyy-MM-dd HH:mm:ss');
    console.log('Current date:', currentDate);
    
    // リポジトリパターンの使用例
    if (event.userId) {
      const user = await getUserById(event.userId);
      console.log('User data:', user);
    }
    
    // DynamoDB への書き込み例
    await docClient.put({
      TableName: process.env.TABLE_NAME || 'test-table',
      Item: {
        id: `function-a-${Date.now()}`,
        processedAt: currentDate,
        processedIds: ids,
        functionName: 'function-a'
      }
    });
    
    return {
      statusCode: 200,
      body: JSON.stringify({
        message: 'Function A processed successfully',
        processedCount: ids.length,
        timestamp: currentDate
      })
    };
  } catch (error) {
    console.error('Error in Function A:', error);
    return {
      statusCode: 500,
      body: JSON.stringify({
        message: 'Error processing in Function A',
        error: error instanceof Error ? error.message : 'Unknown error'
      })
    };
  }
};