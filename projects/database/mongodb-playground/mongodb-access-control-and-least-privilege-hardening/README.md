# MongoDB Access Control and Least Privilege Hardening

**Level:** intermediate  ·  **Playground:** MongoDB Playground

▶ **[Launch the playground](https://kodekloud.com/playgrounds/playground-mongodb)** — open it, then copy the files below.

A [`commands.sh`](./commands.sh) with the runnable steps is included.

## Scenario
The internal development team is building a new entertainment recommendation portal using MongoDB as the backend document database. During a recent architecture review, the security team flagged a critical misconfiguration: the application currently connects to the database using full administrative privileges. 

You are the Lead Database Security Engineer. Your task is to log into the staging sandbox and demonstrate the danger of this setup by simulating how a compromised application can easily inject rogue data into the production tables. Once the threat is proven, you will secure the environment by provisioning a strictly scoped, read-only application user to enforce the principle of least privilege and completely block unauthorized writes.

## What you'll build
Starting from a baseline sandbox environment containing a pre-loaded `movies` database, you will authenticate using the terminal shell (`mongosh`). You will explore the `tvshows` collection, simulate a rogue write operation using the over-privileged account, and provision a dedicated, read-only database user. Finally, you will prove your security perimeter works by attempting the same write operation with the new credentials and watching it fail.

## Learning objectives
By the end you will be able to:
- Authenticate to the MongoDB daemon using `mongosh` and specific authentication databases.
- Perform basic data discovery commands to analyze document schemas.
- Simulate unauthorized data injection to identify privilege escalation vulnerabilities.
- Provision customized database users utilizing Role-Based Access Control (RBAC).
- Enforce and validate the Principle of Least Privilege on a production collection.

## Prerequisites
- Playground: **MongoDB** (open it before starting)

---

## Steps

### Task 1 — Terminal Authentication & Data Discovery
Authenticate directly with the database engine using the administrative credentials provided for this sandbox, then inspect the collection schema.

```bash
# 1. Access the MongoDB Shell
mongosh --authenticationDatabase "admin" -u "myUserAdmin" -p

# (When prompted for the password, type: Admin#123)
```

```javascript
// 2. Explore the Target Database
use movies;
db.tvshows.findOne();
```
> **Why:** Switching the active context to the pre-loaded `movies` database and querying a single document allows you to understand the schema the frontend application interacts with before performing any simulations.

### Task 2 — Threat Simulation (Unauthorized Write)
Because the application is running as `myUserAdmin`, anyone who compromises the frontend can write or delete data. Simulate this threat by inserting a completely unauthorized record into the collection.

```javascript
// 1. Simulate a Rogue Data Injection
db.tvshows.insertOne({ name: "HACKED: Rogue Entry", status: "Compromised" });
```
> **Why:** The shell will output an `acknowledged: true` message along with an `insertedId`, proving the database blindly accepted the unauthorized data because the connecting user possesses administrative rights.

### Task 3 — Implementing Least Privilege
To eliminate this massive security hole, create a dedicated, low-privilege user. This user will only have permission to read data within the `movies` database.

```javascript
// 1. Provision the Application User
db.createUser({
  user: "app_reader",
  pwd: "AppPassword123!",
  roles: [
    { role: "read", db: "movies" }
  ]
});
```

```javascript
// 2. Verify the User Creation
db.getUsers();

// 3. Exit the administrative session
exit;
```
> **Why:** The `read` role inherently strips away the ability to alter records (`insert`, `update`, `delete`). We verify the user exists in the active database's user list before exiting to test the new perimeter.

### Task 4 — Perimeter Validation
To prove the security hardening worked, log back in using the new restricted credentials. Since this user was created specifically inside the `movies` database, you must pass that as the authentication database.

```bash
# 1. Authenticate as the Application User
mongosh --authenticationDatabase "movies" -u "app_reader" -p

# (When prompted, type: AppPassword123!)
```

```javascript
// 2. Test Read Access (Authorized)
use movies;
db.tvshows.findOne();
```

```javascript
// 3. Test Write Access (Unauthorized)
db.tvshows.insertOne({ name: "HACKED: Second Attempt" });
```
> **Why:** Your `findOne()` command will successfully return a document, proving the frontend can still operate normally. However, your `insertOne()` command will instantly trigger a `MongoServerError` stating the user is not authorized, proving your environment is now secured.

---

## Validation
Run the following commands in your `mongosh` prompt (as `app_reader`) to verify your database state and ensure your RBAC restrictions are functioning perfectly.

```javascript
// 1. Verify you are connected as the correct user
db.runCommand({ connectionStatus: 1 }).authInfo.authenticatedUsers;

// 2. Verify you have read privileges (Should return a document)
db.tvshows.find().limit(1);

// 3. Verify write privileges are blocked (Should return an authorization error)
db.tvshows.deleteOne({ name: "HACKED: Rogue Entry" });
```

Expected result:
- [ ] You successfully authenticated in the terminal using the `mongosh` command as the admin.
- [ ] You were able to switch to the `movies` database and view sample documents in the `tvshows` collection.
- [ ] You successfully inserted the first rogue document using the administrative credentials.
- [ ] You successfully created the `app_reader` user with the restricted `read` role.
- [ ] The `connectionStatus` check confirms you are operating as `app_reader@movies`.
- [ ] Your final `deleteOne` or `insertOne` attempts are actively blocked by the database with a `MongoServerError: not authorized on movies...` message.

## References & further learning
- MongoDB `mongosh` Authentication: https://www.mongodb.com/docs/mongodb-shell/authenticate/
- MongoDB Built-In Roles (`read`): https://www.mongodb.com/docs/manual/reference/built-in-roles/
- MongoDB `createUser` Command: https://www.mongodb.com/docs/manual/reference/method/db.createUser/
- KodeKloud course: Database Fundamentals: https://kodekloud.com/courses/database-fundamentals/
- KodeKloud course: DevOps Pre-Requisite Course: https://kodekloud.com/courses/devops-pre-requisite-course/
