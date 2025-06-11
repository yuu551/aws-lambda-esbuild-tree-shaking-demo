import { SNS } from '@aws-sdk/client-sns';
import { getUserById } from '../repositories/user-repository';

const sns = new SNS({});

export const sendUserNotification = async (
  userId: string,
  message: string
): Promise<void> => {
  // ユーザー情報の取得
  const user = await getUserById(userId);
  if (!user) {
    throw new Error(`User not found for notification: ${userId}`);
  }
  
  // 通知送信のロジック
  console.log(`Sending notification to user ${userId} (${user.email}):`, message);
  
  if (process.env.NOTIFICATION_TOPIC_ARN) {
    await sns.publish({
      TopicArn: process.env.NOTIFICATION_TOPIC_ARN,
      Subject: `Notification for ${user.name}`,
      Message: JSON.stringify({
        userId,
        userEmail: user.email,
        message,
        timestamp: new Date().toISOString()
      })
    });
  } else {
    console.warn('NOTIFICATION_TOPIC_ARN not configured, skipping SNS publish');
  }
};