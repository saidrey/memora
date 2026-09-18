DROP TABLE IF EXISTS session_jtis, refresh_tokens, nfc_qr_tags, share_links, invitations, memberships, album_photos, photos, albums, users;
DELETE FROM schema_migrations WHERE version = '001_initial';
