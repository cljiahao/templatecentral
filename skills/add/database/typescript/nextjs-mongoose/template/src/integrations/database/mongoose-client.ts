import mongoose from 'mongoose';

const MONGODB_URL = process.env.MONGODB_URL;

if (!MONGODB_URL) {
  throw new Error('MONGODB_URL environment variable is not defined');
}

interface MongooseCache {
  conn: typeof mongoose | null;
  promise: Promise<typeof mongoose> | null;
}

const globalForMongoose = globalThis as unknown as { mongoose: MongooseCache };

const cached: MongooseCache = globalForMongoose.mongoose ?? { conn: null, promise: null };

if (!globalForMongoose.mongoose) {
  globalForMongoose.mongoose = cached;
}

export async function connectDB(): Promise<typeof mongoose> {
  if (cached.conn) return cached.conn;

  if (!cached.promise) {
    cached.promise = mongoose.connect(MONGODB_URL, {
      // Fail fast instead of holding a serverless invocation open for the 30s default
      serverSelectionTimeoutMS: 5_000,
      // Each serverless instance keeps its own pool — a small cap avoids exhausting
      // the cluster's connection limit as instances scale out
      maxPoolSize: 10,
    });
  }

  try {
    const conn = await cached.promise;
    // Mongoose builds indexes in the background; wait so unique constraints exist before the first write.
    await Promise.all(conn.modelNames().map((name) => conn.model(name).init()));
    cached.conn = conn;
  } catch (error) {
    // Drop the rejected promise so the next request retries instead of failing forever.
    cached.promise = null;
    throw error;
  }
  return cached.conn;
}
