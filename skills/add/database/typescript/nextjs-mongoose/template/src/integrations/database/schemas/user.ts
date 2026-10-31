import mongoose, { type Model } from 'mongoose';

// Plain interface — Mongoose discourages extending `Document` for schema types.
export interface IUser {
  email: string;
  name: string;
  createdAt: Date;
  updatedAt: Date;
}

const userSchema = new mongoose.Schema<IUser>(
  {
    email: { type: String, required: true, unique: true },
    name: { type: String, required: true },
  },
  { timestamps: true },
);

export const User =
  (mongoose.models.User as Model<IUser> | undefined) ?? mongoose.model<IUser>('User', userSchema);
