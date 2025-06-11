export interface User {
  id: string;
  email: string;
  name: string;
  status: 'active' | 'inactive' | 'suspended';
  createdAt: string;
  updatedAt: string;
  lastBillingDate?: string;
  lastBillingAmount?: number;
}

export interface UserUpdate {
  email?: string;
  name?: string;
  status?: 'active' | 'inactive' | 'suspended';
  lastBillingDate?: string;
  lastBillingAmount?: number;
}