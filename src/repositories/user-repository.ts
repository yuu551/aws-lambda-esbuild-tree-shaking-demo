import { DynamoDB } from '@aws-sdk/client-dynamodb';
import { DynamoDBDocument } from '@aws-sdk/lib-dynamodb';
import { User, UserUpdate } from '../shared/models/user';

const client = new DynamoDB({});
const docClient = DynamoDBDocument.from(client);
const TABLE_NAME = process.env.USERS_TABLE || 'users';

export const getUserById = async (userId: string): Promise<User | null> => {
  try {
    const result = await docClient.get({
      TableName: TABLE_NAME,
      Key: { id: userId }
    });
    
    return result.Item as User || null;
  } catch (error) {
    console.error('Error getting user:', error);
    throw error;
  }
};

export const updateUser = async (userId: string, updates: UserUpdate): Promise<void> => {
  try {
    const updateExpression: string[] = [];
    const expressionAttributeNames: Record<string, string> = {};
    const expressionAttributeValues: Record<string, any> = {};
    
    Object.entries(updates).forEach(([key, value], index) => {
      const attrName = `#attr${index}`;
      const attrValue = `:val${index}`;
      
      updateExpression.push(`${attrName} = ${attrValue}`);
      expressionAttributeNames[attrName] = key;
      expressionAttributeValues[attrValue] = value;
    });
    
    if (updateExpression.length > 0) {
      await docClient.update({
        TableName: TABLE_NAME,
        Key: { id: userId },
        UpdateExpression: `SET ${updateExpression.join(', ')}, updatedAt = :updatedAt`,
        ExpressionAttributeNames: expressionAttributeNames,
        ExpressionAttributeValues: {
          ...expressionAttributeValues,
          ':updatedAt': new Date().toISOString()
        }
      });
    }
  } catch (error) {
    console.error('Error updating user:', error);
    throw error;
  }
};