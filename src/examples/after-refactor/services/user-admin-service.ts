import { findUserById, updateUserStatus, deleteUser } from '../repositories/user-repository';
import { sendUserNotification } from './notification-service';

// 管理機能のみを提供するサービス
export const suspendUser = async (
  userId: string,
  reason: string,
  notifyUser: boolean = true
): Promise<void> => {
  const user = await findUserById(userId);
  if (!user) {
    throw new Error(`User not found: ${userId}`);
  }

  // ユーザーステータスを更新
  await updateUserStatus(userId, 'suspended');

  // 通知を送信
  if (notifyUser) {
    await sendUserNotification(
      userId,
      `Your account has been suspended. Reason: ${reason}`,
      { forceEmail: true } // 強制的にメール送信
    );
  }

  // 監査ログの記録
  console.log(`User ${userId} suspended by admin. Reason: ${reason}`);
};

export const reactivateUser = async (userId: string): Promise<void> => {
  const user = await findUserById(userId);
  if (!user) {
    throw new Error(`User not found: ${userId}`);
  }

  if (user.status !== 'suspended') {
    throw new Error(`User ${userId} is not suspended`);
  }

  await updateUserStatus(userId, 'active');

  // 再アクティベーション通知
  await sendUserNotification(
    userId,
    'Your account has been reactivated. Welcome back!',
    { forceEmail: true }
  );

  console.log(`User ${userId} reactivated`);
};

export const deleteUserAccount = async (
  userId: string,
  options?: {
    hardDelete?: boolean;
    reason?: string;
  }
): Promise<void> => {
  const user = await findUserById(userId);
  if (!user) {
    throw new Error(`User not found: ${userId}`);
  }

  if (options?.hardDelete) {
    // 完全削除
    await deleteUser(userId);
    console.log(`User ${userId} permanently deleted`);
  } else {
    // ソフト削除（ステータス変更のみ）
    await updateUserStatus(userId, 'inactive');
    console.log(`User ${userId} soft deleted`);
  }

  // 削除理由の記録
  if (options?.reason) {
    console.log(`Deletion reason: ${options.reason}`);
  }
};

// ユーザーアクティビティの分析（管理者用）
export const analyzeUserActivity = async (userId: string): Promise<{
  userId: string;
  status: string;
  billingPlan: string;
  accountAge: number;
  lastActivity: string;
}> => {
  const user = await findUserById(userId);
  if (!user) {
    throw new Error(`User not found: ${userId}`);
  }

  const accountAge = Math.floor(
    (new Date().getTime() - new Date(user.createdAt).getTime()) / (1000 * 60 * 60 * 24)
  );

  return {
    userId: user.id,
    status: user.status,
    billingPlan: user.billingPlan,
    accountAge, // days
    lastActivity: user.updatedAt,
  };
};