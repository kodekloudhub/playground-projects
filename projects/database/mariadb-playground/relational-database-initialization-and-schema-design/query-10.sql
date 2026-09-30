/* 1. Verify the active database context */
SELECT DATABASE();

/* 2. Check that both tables were successfully created */
SHOW TABLES;

/* 3. Verify the foreign key constraint on the posts table */
SHOW CREATE TABLE posts;
