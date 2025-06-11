import * as dynamoose from 'dynamoose';
import { Document } from 'dynamoose';

// Before: 密結合な Model クラス（全ての機能が1つのクラスに集約）
interface UserDocument extends Document {
  id: string;
  email: string;
  name: string;
  status: 'active' | 'inactive' | 'suspended';
  billingPlan: 'free' | 'standard' | 'premium';
  lastBillingDate?: string;
  notificationSettings: {
    email: boolean;
    sms: boolean;
    push: boolean;
  };
  createdAt: string;
  updatedAt: string;
}

const userSchema = new dynamoose.Schema({
  id: {
    type: String,
    hashKey: true,
  },
  email: {
    type: String,
    required: true,
    index: {
      name: 'emailIndex',
      global: true,
    },
  },
  name: {
    type: String,
    required: true,
  },
  status: {
    type: String,
    enum: ['active', 'inactive', 'suspended'],
    default: 'active',
  },
  billingPlan: {
    type: String,
    enum: ['free', 'standard', 'premium'],
    default: 'free',
  },
  lastBillingDate: String,
  notificationSettings: {
    type: Object,
    schema: {
      email: { type: Boolean, default: true },
      sms: { type: Boolean, default: false },
      push: { type: Boolean, default: false },
    },
  },
}, {
  timestamps: true,
});

export class UserModel {
  private model = dynamoose.model<UserDocument>('User', userSchema);

  // 基本的なCRUD操作
  async findById(id: string): Promise<UserDocument | null> {
    try {
      return await this.model.get(id);
    } catch (error) {
      return null;
    }
  }

  async findByEmail(email: string): Promise<UserDocument[]> {
    return await this.model.query('email').eq(email).using('emailIndex').exec();
  }

  async create(userData: Partial<UserDocument>): Promise<UserDocument> {
    return await this.model.create(userData);
  }

  async updateStatus(id: string, status: UserDocument['status']): Promise<void> {
    await this.model.update({ id }, { status });
  }

  // 請求関連の機能（一部のLambdaしか使わない）
  async calculateBilling(id: string): Promise<number> {
    const user = await this.findById(id);
    if (!user) throw new Error('User not found');

    const planPrices = {
      free: 0,
      standard: 1000,
      premium: 5000,
    };

    const basePrice = planPrices[user.billingPlan];
    const tax = basePrice * 0.1;
    return basePrice + tax;
  }

  async updateBillingInfo(id: string, billingDate: string, amount: number): Promise<void> {
    await this.model.update({ id }, { 
      lastBillingDate: billingDate,
      // 他の請求関連フィールドの更新
    });
  }

  async getBillingHistory(id: string): Promise<any[]> {
    // 請求履歴の取得ロジック
    console.log(`Getting billing history for user ${id}`);
    return [];
  }

  // 通知関連の機能（一部のLambdaしか使わない）
  async sendNotification(id: string, message: string): Promise<void> {
    const user = await this.findById(id);
    if (!user) throw new Error('User not found');

    if (user.notificationSettings.email) {
      await this.sendEmailNotification(user.email, message);
    }
    if (user.notificationSettings.sms) {
      await this.sendSmsNotification(user, message);
    }
    if (user.notificationSettings.push) {
      await this.sendPushNotification(user, message);
    }
  }

  private async sendEmailNotification(email: string, message: string): Promise<void> {
    console.log(`Sending email to ${email}: ${message}`);
    // Email送信ロジック
  }

  private async sendSmsNotification(user: UserDocument, message: string): Promise<void> {
    console.log(`Sending SMS to user ${user.id}: ${message}`);
    // SMS送信ロジック
  }

  private async sendPushNotification(user: UserDocument, message: string): Promise<void> {
    console.log(`Sending push notification to user ${user.id}: ${message}`);
    // Push通知ロジック
  }

  // ユーザー分析機能（一部のLambdaしか使わない）
  async analyzeUserActivity(id: string): Promise<any> {
    const user = await this.findById(id);
    if (!user) throw new Error('User not found');

    // ユーザーアクティビティの分析ロジック
    return {
      userId: id,
      activityScore: Math.random() * 100,
      lastActive: new Date(),
    };
  }

  // 管理機能（管理系Lambdaしか使わない）
  async suspendUser(id: string, reason: string): Promise<void> {
    await this.updateStatus(id, 'suspended');
    await this.sendNotification(id, `Your account has been suspended: ${reason}`);
    // 監査ログの記録など
  }

  async deleteUser(id: string): Promise<void> {
    await this.model.delete(id);
    // 関連データの削除など
  }
}

// 使用例：全てのLambdaがこの巨大なクラスをimportすることになる
export const userModel = new UserModel();