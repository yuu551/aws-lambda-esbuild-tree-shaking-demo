import { getUserById } from '../repositories/user-repository';

export interface BillingResult {
  totalAmount: number;
  details: {
    baseCharge: number;
    additionalCharges: number;
    discounts: number;
    tax: number;
  };
}

export const calculateUserBilling = async (
  userId: string, 
  billingPeriod?: string
): Promise<BillingResult> => {
  // ユーザー情報の取得
  const user = await getUserById(userId);
  if (!user) {
    throw new Error(`User not found for billing: ${userId}`);
  }
  
  // 請求計算のロジック（簡略化された例）
  const baseCharge = 1000;
  const additionalCharges = user.status === 'active' ? 500 : 0;
  const discounts = user.createdAt < '2023-01-01' ? 100 : 0; // 長期利用割引
  const subtotal = baseCharge + additionalCharges - discounts;
  const tax = Math.round(subtotal * 0.1);
  const totalAmount = subtotal + tax;
  
  console.log(`Billing calculated for user ${userId}:`, {
    baseCharge,
    additionalCharges,
    discounts,
    tax,
    totalAmount,
    billingPeriod: billingPeriod || 'current'
  });
  
  return {
    totalAmount,
    details: {
      baseCharge,
      additionalCharges,
      discounts,
      tax
    }
  };
};