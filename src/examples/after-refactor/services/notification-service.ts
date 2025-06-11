import { SNS } from '@aws-sdk/client-sns';
import { SES } from '@aws-sdk/client-ses';
import { findUserById } from '../repositories/user-repository';

// 通知関連の機能のみを提供するサービス
const sns = new SNS({});
const ses = new SES({});

export const sendUserNotification = async (
  userId: string,
  message: string,
  options?: {
    forceEmail?: boolean;
    forceSms?: boolean;
    forcePush?: boolean;
  }
): Promise<void> => {
  const user = await findUserById(userId);
  if (!user) {
    throw new Error(`User not found: ${userId}`);
  }

  const promises: Promise<any>[] = [];

  // Email通知
  if (user.notificationSettings.email || options?.forceEmail) {
    promises.push(sendEmailNotification(user.email, user.name, message));
  }

  // SMS通知
  if (user.notificationSettings.sms || options?.forceSms) {
    promises.push(sendSmsNotification(userId, message));
  }

  // Push通知
  if (user.notificationSettings.push || options?.forcePush) {
    promises.push(sendPushNotification(userId, message));
  }

  await Promise.all(promises);
};

const sendEmailNotification = async (
  email: string,
  name: string,
  message: string
): Promise<void> => {
  try {
    await ses.sendEmail({
      Source: 'noreply@example.com',
      Destination: {
        ToAddresses: [email],
      },
      Message: {
        Subject: {
          Data: 'Notification from Your App',
        },
        Body: {
          Text: {
            Data: `Hello ${name},\n\n${message}\n\nBest regards,\nYour App Team`,
          },
        },
      },
    });
    console.log(`Email sent to ${email}`);
  } catch (error) {
    console.error('Error sending email:', error);
    throw error;
  }
};

const sendSmsNotification = async (userId: string, message: string): Promise<void> => {
  try {
    // 実際の実装では電話番号を取得
    await sns.publish({
      Message: message,
      TopicArn: process.env.SMS_TOPIC_ARN,
      MessageAttributes: {
        userId: {
          DataType: 'String',
          StringValue: userId,
        },
      },
    });
    console.log(`SMS notification queued for user ${userId}`);
  } catch (error) {
    console.error('Error sending SMS:', error);
    throw error;
  }
};

const sendPushNotification = async (userId: string, message: string): Promise<void> => {
  try {
    await sns.publish({
      Message: JSON.stringify({
        default: message,
        GCM: JSON.stringify({
          notification: {
            title: 'New Notification',
            body: message,
          },
        }),
      }),
      TopicArn: process.env.PUSH_TOPIC_ARN,
      MessageStructure: 'json',
      MessageAttributes: {
        userId: {
          DataType: 'String',
          StringValue: userId,
        },
      },
    });
    console.log(`Push notification sent for user ${userId}`);
  } catch (error) {
    console.error('Error sending push notification:', error);
    throw error;
  }
};

// 通知設定の更新
export const updateNotificationSettings = async (
  userId: string,
  settings: {
    email?: boolean;
    sms?: boolean;
    push?: boolean;
  }
): Promise<void> => {
  const { updateUser } = await import('../repositories/user-repository');
  
  const user = await findUserById(userId);
  if (!user) {
    throw new Error(`User not found: ${userId}`);
  }

  await updateUser(userId, {
    notificationSettings: {
      ...user.notificationSettings,
      ...settings,
    },
  });
};