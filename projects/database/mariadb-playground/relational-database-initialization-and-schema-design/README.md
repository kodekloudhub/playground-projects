# Relational Database Initialization and Schema Design

**Level:** beginner  ·  **Playground:** MariaDB Playground

A [`commands.sh`](./commands.sh) with the runnable steps is included.

## Scenario
A digital marketing agency is launching a new corporate web publication and requires a robust, relational database. You are the Database Administrator tasked with setting up the environment using MariaDB, a high-performance, open-source database engine. To ensure the development team can seamlessly connect their application servers, your goal is to design and deploy the underlying logical architecture. This involves establishing secure command-line access, building a scalable multi-table schema for the `cms_production` database, and validating data integrity to prepare for live application traffic.

## What you'll build
You will initialize a fully functional MariaDB database directly from the terminal to store and manage the publication's content. This requires architecting a normalized data model within the `cms_production` database that accurately maps authors to their published articles. You will validate this architecture by executing core CRUD (Create, Read, Update, Delete) operations and complex relational queries using standard SQL commands to ensure the database is structurally sound and ready for development handover.

## Learning objectives
By the end you will be able to:
- Establish secure, authenticated connections to a MariaDB server utilizing the command-line client.
- Create databases and architect normalized, multi-table schemas.
- Enforce data integrity using strict data types, primary keys, and foreign key relationships.
- Populate relational tables with test data using `INSERT` statements.
- Extract, update, and delete targeted records securely using `JOIN`, `UPDATE`, and `DELETE` commands.

## Prerequisites
- Playground: **MariaDB** (open it before starting)

---

## Steps

### Task 1 — Database and Schema Setup
Access the database engine, create the application database, and construct the relational tables ensuring they are linked via foreign keys.

```bash
# 1. Access the MariaDB Terminal
# (When prompted for the password, type: caleston123)
mariadb -u bob -p
```

```sql
/* 2. Create the Database */
CREATE DATABASE cms_production;
USE cms_production;
```

```sql
/* 3. Create the authors Table */
CREATE TABLE authors (
    id INT AUTO_INCREMENT PRIMARY KEY,
    name VARCHAR(100) NOT NULL,
    email VARCHAR(150) NOT NULL
);
```

```sql
/* 4. Create the posts Table */
CREATE TABLE posts (
    id INT AUTO_INCREMENT PRIMARY KEY,
    author_id INT NOT NULL,
    title VARCHAR(255) NOT NULL,
    content TEXT,
    created_at DATETIME DEFAULT CURRENT_TIMESTAMP,
    FOREIGN KEY (author_id) REFERENCES authors(id)
);
```
> **Why:** The `posts` table includes a `FOREIGN KEY` constraint linking back to the `authors` table. This enforces relational integrity—you cannot create a post for an author that does not exist.

### Task 2 — Data Insertion
Populate your newly created schema with verified testing data to simulate active content.

```sql
/* 1. Insert Author Data */
INSERT INTO authors (name, email) 
VALUES ('Alice Smith', 'alice@example.com');
```

```sql
/* 2. Insert Post Data */
INSERT INTO posts (author_id, title, content) 
VALUES (1, 'Database Architecture Basics', 'This is a test post about relational schemas.');

INSERT INTO posts (author_id, title, content) 
VALUES (1, 'Terminal vs GUI', 'Exploring the differences in database management tools.');
```
> **Why:** By setting the `author_id` to `1`, you successfully link both of these new blog posts back to the 'Alice Smith' record.

### Task 3 — Querying and Modifying Data
Execute multi-table queries and perform targeted updates and deletions to ensure the database handles manipulation correctly.

```sql
/* 1. Run a JOIN Query */
SELECT posts.title, authors.name, posts.created_at
FROM posts
JOIN authors ON posts.author_id = authors.id;
```
> **Why:** A standalone `posts` table only shows the numerical `author_id`. Using a `JOIN` pulls the human-readable `name` from the `authors` table to display alongside the post `title`.

```sql
/* 2. Update a Record */
UPDATE posts 
SET content = 'This post has been successfully updated via the terminal.'
WHERE id = 1;
```
> **Critical:** Always use a `WHERE` clause when updating records, otherwise you will accidentally overwrite the content of every single row in the table!

```sql
/* 3. Delete a Record */
DELETE FROM posts 
WHERE id = 2;
```

```sql
/* 4. Verify the Changes */
SELECT * FROM posts;
```

---

## Validation
Run the following commands in your MariaDB prompt to verify your database state and schema design.

```sql
/* 1. Verify the active database context */
SELECT DATABASE();

/* 2. Check that both tables were successfully created */
SHOW TABLES;

/* 3. Verify the foreign key constraint on the posts table */
SHOW CREATE TABLE posts;
```

Expected result:
- [ ] You successfully initialized the `cms_production` database and accessed it via the command-line client.
- [ ] The schema includes multiple tables (`authors`, `posts`) properly linked with foreign keys.
- [ ] The primary keys and automated timestamps were configured correctly across the schema.
- [ ] The test data populated successfully without violating relational constraints.
- [ ] Your `JOIN` query successfully retrieved combined records displaying the author's name next to the post title.
- [ ] Your targeted `UPDATE` and `DELETE` commands executed securely, leaving `id = 1` successfully modified and `id = 2` entirely removed.

## References & further learning
- MariaDB Data Definition (`CREATE`, `ALTER`): https://mariadb.com/kb/en/data-definition/
- MariaDB Data Manipulation (`INSERT`, `UPDATE`, `DELETE`): https://mariadb.com/kb/en/data-manipulation/
- MariaDB `JOIN` Syntax: https://mariadb.com/kb/en/joins/
- KodeKloud course: Database Fundamentals: https://kodekloud.com/courses/database-fundamentals/
