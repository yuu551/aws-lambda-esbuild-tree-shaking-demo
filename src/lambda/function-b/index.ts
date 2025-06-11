import { SNS } from '@aws-sdk/client-sns';
import { format } from 'date-fns';
import { sendUserNotification } from '../../services/notification-service';

// SNS クライアントの初期化
const sns = new SNS({});

export const handler = async (event: any) => {
  console.log('Function B - Event:', JSON.stringify(event, null, 2));
  
  try {
    // 通知サービスの使用
    if (event.userId && event.message) {
      await sendUserNotification(event.userId, event.message);
    }
    
    // SNS への通知例
    const timestamp = format(new Date(), 'yyyy-MM-dd HH:mm:ss');
    await sns.publish({
      TopicArn: process.env.TOPIC_ARN,
      Subject: 'Function B Processing',
      Message: JSON.stringify({
        functionName: 'function-b',
        timestamp,
        eventData: event
      })
    });
    
    return {
      statusCode: 200,
      body: JSON.stringify({
        message: 'Function B processed successfully',
        timestamp
      })
    };
  } catch (error) {
    console.error('Error in Function B:', error);
    return {
      statusCode: 500,
      body: JSON.stringify({
        message: 'Error processing in Function B',
        error: error instanceof Error ? error.message : 'Unknown error'
      })
    };
  }
};