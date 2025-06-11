import * as dynamoose from 'dynamoose';
import { Document } from 'dynamoose';

// After: スキーマ定義のみを分離
export interface UserDocument extends Document {
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

export const userSchema = new dynamoose.Schema({
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

// 軽量なモデルのエクスポート
export const UserModel = dynamoose.model<UserDocument>('User', userSchema);