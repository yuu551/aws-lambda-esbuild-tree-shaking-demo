import { getUserById, updateUser } from '../../repositories/user-repository';
import { calculateUserBilling } from '../../services/billing-service';
import { format } from 'date-fns';

export const handler = async (event: any) => {
  console.log('Billing Processor - Event:', JSON.stringify(event, null, 2));
  
  try {
    const { userId, billingPeriod } = event;
    
    if (!userId) {
      throw new Error('userId is required');
    }
    
    // ユーザー情報の取得
    const user = await getUserById(userId);
    if (!user) {
      throw new Error(`User not found: ${userId}`);
    }
    
    // 請求計算（notification-service は import していない）
    const billingResult = await calculateUserBilling(userId, billingPeriod);
    
    // ユーザー情報の更新
    await updateUser(userId, {
      lastBillingDate: format(new Date(), 'yyyy-MM-dd'),
      lastBillingAmount: billingResult.totalAmount
    });
    
    return {
      statusCode: 200,
      body: JSON.stringify({
        message: 'Billing processed successfully',
        userId,
        billingAmount: billingResult.totalAmount,
        billingDetails: billingResult.details
      })
    };
  } catch (error) {
    console.error('Error in Billing Processor:', error);
    return {
      statusCode: 500,
      body: JSON.stringify({
        message: 'Error processing billing',
        error: error instanceof Error ? error.message : 'Unknown error'
      })
    };
  }
};