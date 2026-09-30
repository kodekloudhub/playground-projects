/* 1. Run a JOIN Query */
SELECT posts.title, authors.name, posts.created_at
FROM posts
JOIN authors ON posts.author_id = authors.id;
