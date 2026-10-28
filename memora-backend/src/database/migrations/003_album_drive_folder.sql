ALTER TABLE albums ADD COLUMN IF NOT EXISTS drive_folder_id text;
ALTER TABLE memberships ADD COLUMN IF NOT EXISTS drive_permission_id text;
