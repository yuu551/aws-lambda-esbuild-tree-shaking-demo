import { UserModel, UserDocument } from '../schemas/user';

// 基本的なCRUD操作のみを提供するリポジトリ
export const findUserById = async (id: string): Promise<UserDocument | null> => {
  try {
    return await UserModel.get(id);
  } catch (error) {
    console.error('Error finding user by id:', error);
    return null;
  }
};

export const findUserByEmail = async (email: string): Promise<UserDocument[]> => {
  try {
    return await UserModel.query('email').eq(email).using('emailIndex').exec();
  } catch (error) {
    console.error('Error finding user by email:', error);
    return [];
  }
};

export const createUser = async (userData: Partial<UserDocument>): Promise<UserDocument> => {
  return await UserModel.create(userData);
};

export const updateUser = async (id: string, updates: Partial<UserDocument>): Promise<void> => {
  await UserModel.update({ id }, updates);
};

export const updateUserStatus = async (id: string, status: UserDocument['status']): Promise<void> => {
  await UserModel.update({ id }, { status });
};

export const deleteUser = async (id: string): Promise<void> => {
  await UserModel.delete(id);
};