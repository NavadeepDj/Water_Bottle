-- Supabase Database Setup for Water Bottle App
-- Run this in your Supabase SQL Editor

-- 1. Create user_profiles table
CREATE TABLE IF NOT EXISTS user_profiles (
  id BIGSERIAL PRIMARY KEY,
  firebase_uid TEXT UNIQUE NOT NULL,
  display_name TEXT NOT NULL,
  photo_url TEXT,
  email TEXT,
  created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
  updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

-- 2. Create water_fetch_posts table
CREATE TABLE IF NOT EXISTS water_fetch_posts (
  id BIGSERIAL PRIMARY KEY,
  firebase_uid TEXT NOT NULL REFERENCES user_profiles(firebase_uid) ON DELETE CASCADE,
  message TEXT NOT NULL,
  fetch_type TEXT NOT NULL CHECK (fetch_type IN ('Single', 'Together')),
  partner_user_id TEXT,
  -- Use NUMERIC with two decimal places so values like 0.25 are preserved
  points NUMERIC(5,2) NOT NULL CHECK (points >= 0),
  verification_status TEXT NOT NULL DEFAULT 'pending' CHECK (verification_status IN ('pending', 'verified', 'rejected')),
  verified_by TEXT[] DEFAULT '{}',
  rejected_by TEXT[] DEFAULT '{}',
  created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
  updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

-- 3. Enable Row Level Security (RLS)
ALTER TABLE user_profiles ENABLE ROW LEVEL SECURITY;
ALTER TABLE water_fetch_posts ENABLE ROW LEVEL SECURITY;

-- 4. Create RLS policies for user_profiles
-- Users can read all profiles (for dropdown selection)
CREATE POLICY "Users can read all profiles" ON user_profiles
  FOR SELECT USING (true);

-- Users can only update their own profile
CREATE POLICY "Users can update own profile" ON user_profiles
  FOR UPDATE USING (firebase_uid = current_setting('request.jwt.claim.sub', true));

-- Users can insert their own profile
CREATE POLICY "Users can insert own profile" ON user_profiles
  FOR INSERT WITH CHECK (firebase_uid = current_setting('request.jwt.claim.sub', true));

-- 5. Create RLS policies for water_fetch_posts
-- Users can read all posts
CREATE POLICY "Users can read all posts" ON water_fetch_posts
  FOR SELECT USING (true);

-- Users can only insert their own posts
CREATE POLICY "Users can insert own posts" ON water_fetch_posts
  FOR INSERT WITH CHECK (firebase_uid = current_setting('request.jwt.claim.sub', true));

-- Users can update posts (for verification/rejection)
CREATE POLICY "Users can update posts" ON water_fetch_posts
  FOR UPDATE USING (true);

-- NOTE: By default there was no DELETE policy which prevents clients from
-- deleting rows when Row Level Security (RLS) is enabled. For development
-- convenience we add a permissive DELETE policy here. This will allow
-- deletes from the client. Tighten this policy before releasing to
-- production (for example, restrict deletes to post owners or perform
-- deletes from a secure server using the service_role key).
CREATE POLICY "Users can delete posts" ON water_fetch_posts
  FOR DELETE USING (true);

-- 6. Create indexes for better performance
CREATE INDEX IF NOT EXISTS idx_user_profiles_firebase_uid ON user_profiles(firebase_uid);
CREATE INDEX IF NOT EXISTS idx_water_fetch_posts_firebase_uid ON water_fetch_posts(firebase_uid);
CREATE INDEX IF NOT EXISTS idx_water_fetch_posts_created_at ON water_fetch_posts(created_at DESC);
CREATE INDEX IF NOT EXISTS idx_water_fetch_posts_verification_status ON water_fetch_posts(verification_status);

-- 7. Create function to update updated_at timestamp
CREATE OR REPLACE FUNCTION update_updated_at_column()
RETURNS TRIGGER AS $$
BEGIN
  NEW.updated_at = NOW();
  RETURN NEW;
END;
$$ language 'plpgsql';

-- 8. Create triggers for updated_at
CREATE TRIGGER update_user_profiles_updated_at 
  BEFORE UPDATE ON user_profiles 
  FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

CREATE TRIGGER update_water_fetch_posts_updated_at 
  BEFORE UPDATE ON water_fetch_posts 
  FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

-- 9. Insert sample data (optional - commented out)
-- INSERT INTO user_profiles (firebase_uid, display_name, photo_url, email) VALUES
--   ('sample_user_1', 'Sample User 1', 'https://example.com/photo1.jpg', 'user1@example.com'),
--   ('sample_user_2', 'Sample User 2', 'https://example.com/photo2.jpg', 'user2@example.com')
-- ON CONFLICT (firebase_uid) DO NOTHING;

-- 10. Grant necessary permissions
GRANT ALL ON user_profiles TO authenticated;
GRANT ALL ON water_fetch_posts TO authenticated;
GRANT USAGE ON SEQUENCE user_profiles_id_seq TO authenticated;
GRANT USAGE ON SEQUENCE water_fetch_posts_id_seq TO authenticated;

-- If you already have this table in your Supabase project, run this ALTER
-- to change the column precision without losing data (run in Supabase SQL
-- editor):
-- ALTER TABLE water_fetch_posts ALTER COLUMN points TYPE numeric(5,2) USING points::numeric(5,2);
