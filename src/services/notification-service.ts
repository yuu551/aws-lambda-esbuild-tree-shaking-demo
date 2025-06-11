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
// === 追加された機能（billing-processorでは未参照） ===
export const sendBulkNotifications = async (
  userIds: string[],
  message: string
): Promise<void> => {
  console.log("Sending bulk notifications to multiple users...");
  
  // 重い処理をシミュレート
  const heavyProcessing = Array.from({length: 5000}, (_, i) => 
    Math.sin(i) * Math.cos(i * 2) + Math.random()
  ).reduce((sum, val) => sum + val, 0);
  
  for (const userId of userIds) {
    await sendUserNotification(userId, `[BULK] ${message}`);
    // 処理結果をログに記録
    console.log(`Bulk notification sent to ${userId}, processing result: ${heavyProcessing}`);
  }
};

export const scheduleNotification = async (
  userId: string,
  message: string,
  scheduleTime: Date
): Promise<string> => {
  console.log(`Scheduling notification for ${userId} at ${scheduleTime.toISOString()}`);
  
  // スケジューリングロジック（重い処理）
  const schedulingData = {
    userId,
    message,
    scheduleTime: scheduleTime.toISOString(),
    created: new Date().toISOString(),
    // 複雑な計算結果
    priority: Math.floor(Math.random() * 10) + 1,
    retryCount: 0,
    metadata: {
      source: 'scheduled-notification',
      version: '2.0.0',
      features: ['bulk', 'schedule', 'retry'],
    }
  };
  
  // 実際のシステムではDBに保存
  console.log('Scheduled notification data:', JSON.stringify(schedulingData, null, 2));
  
  return `scheduled-${Date.now()}`;
};

// 通知統計機能
export const getNotificationStats = async (userId: string): Promise<{
  totalSent: number;
  totalScheduled: number;
  successRate: number;
}> => {
  // 統計計算（重い処理）
  const mockStats = {
    totalSent: Math.floor(Math.random() * 1000),
    totalScheduled: Math.floor(Math.random() * 100),
    successRate: 0.85 + Math.random() * 0.15,
  };
  
  console.log(`Notification stats for ${userId}:`, mockStats);
  return mockStats;
};
