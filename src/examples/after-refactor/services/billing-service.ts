import { findUserById, updateUser } from '../repositories/user-repository';
import { UserDocument } from '../schemas/user';

// 請求関連の機能のみを提供するサービス
const PLAN_PRICES = {
  free: 0,
  standard: 1000,
  premium: 5000,
} as const;

export const calculateUserBilling = async (userId: string): Promise<{
  amount: number;
  breakdown: {
    basePrice: number;
    tax: number;
    total: number;
  };
}> => {
  const user = await findUserById(userId);
  if (!user) {
    throw new Error(`User not found: ${userId}`);
  }

  const basePrice = PLAN_PRICES[user.billingPlan];
  const tax = Math.round(basePrice * 0.1);
  const total = basePrice + tax;

  return {
    amount: total,
    breakdown: {
      basePrice,
      tax,
      total,
    },
  };
};

export const updateUserBillingInfo = async (
  userId: string,
  billingDate: string,
  amount: number
): Promise<void> => {
  await updateUser(userId, {
    lastBillingDate: billingDate,
  });

  // 請求履歴の記録（別のテーブルに保存するなど）
  console.log(`Billing updated for user ${userId}: ${amount} on ${billingDate}`);
};

export const getUserBillingHistory = async (userId: string): Promise<any[]> => {
  // 実際の実装では請求履歴テーブルから取得
  const user = await findUserById(userId);
  if (!user) {
    throw new Error(`User not found: ${userId}`);
  }

  return [
    {
      date: user.lastBillingDate,
      amount: PLAN_PRICES[user.billingPlan],
      plan: user.billingPlan,
    },
  ];
};

// 請求プランの変更
export const changeUserBillingPlan = async (
  userId: string,
  newPlan: UserDocument['billingPlan']
): Promise<void> => {
  const user = await findUserById(userId);
  if (!user) {
    throw new Error(`User not found: ${userId}`);
  }

  await updateUser(userId, {
    billingPlan: newPlan,
  });

  console.log(`Billing plan changed for user ${userId}: ${user.billingPlan} -> ${newPlan}`);
};