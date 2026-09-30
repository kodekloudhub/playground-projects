# Enterprise HR Database Audit

**Level:** intermediate  ·  **Playground:** MySQL Playground

▶ **[Launch the playground](https://kodekloud.com/playgrounds/playground-mysql)** — open it, then copy the files below.

A [`commands.sh`](./commands.sh) with the runnable steps is included.

## Scenario
A rapidly expanding enterprise is conducting a comprehensive end-of-year organizational audit. You are the HR Database Analyst tasked with extracting critical workforce intelligence from the company's core human capital management system. The HR Director urgently needs accurate reports on employee demographics, historical hiring trends, departmental headcounts, and current salary distributions to finalize the upcoming fiscal budget. 

Your goal is to navigate the corporate MySQL database, map its relational structure, and write advanced SQL queries to deliver these business insights directly from the command line.

## What you'll build
You will access a live MySQL server and perform a comprehensive data extraction on the existing HR database. You will first inspect the database schema to understand how personnel, financial, and organizational records are linked together through junction tables and unique identifiers. Then, you will utilize various SQL queries to filter employee profiles, apply aggregation functions to calculate average compensation, execute multi-table `JOIN`s to map personnel to active job titles, and create a persistent SQL `VIEW` for future use.

## Learning objectives
By the end you will be able to:
- Authenticate and navigate a MySQL database environment via the command line.
- Inspect and map relational schemas using `DESCRIBE`.
- Execute multi-table `JOIN` statements to connect normalized data.
- Utilize aggregation functions (`AVG`, `COUNT`) and grouping (`GROUP BY`, `HAVING`) to generate business intelligence.
- Create persistent database views (`CREATE VIEW`) to operationalize complex queries for non-technical users.

## Prerequisites
- Playground: **MySQL** (open it before starting)

---

## Steps

### Task 1 — Environment Authentication & Schema Discovery
Authenticate to the database server, select the target HR database, and map out the architecture to identify the primary and foreign keys.

```bash
# 1. Securely Access the Database 
# (When prompted, enter the password: p@sSw0Rd)
mysql -ubob -p
```

```sql
/* 2. Contextualize the Session */
USE employees;
```

```sql
/* 3. Discover the Relational Schema */
SHOW TABLES;
DESCRIBE employees;
DESCRIBE dept_emp;
DESCRIBE departments;
```
> **Why:** Before extracting data, you must understand the architecture. Inspecting the structure of the core personnel tables reveals how `emp_no` and `dept_no` serve as primary and foreign keys to link records together.

### Task 2 — Targeted Demographic Extraction
The HR Director has requested a demographic subset to audit historical hiring practices.

```sql
/* Extract female personnel hired strictly during the 1990 fiscal year */
SELECT emp_no, first_name, last_name, hire_date 
FROM employees 
WHERE gender = 'F' 
  AND hire_date BETWEEN '1990-01-01' AND '1990-12-31'
LIMIT 10;
```
> **Why:** Using the `WHERE` and `BETWEEN` clauses allows us to accurately slice specific historical date ranges from massive datasets without overwhelming the terminal (thanks to `LIMIT`).

### Task 3 — Active Title Identification
Historical data is kept for auditing, but HR needs current operational data. Construct a multi-table query joining the primary employees table to the titles table.

```sql
/* Map employees to current roles, excluding historical jobs */
SELECT e.first_name, e.last_name, t.title 
FROM employees e 
JOIN titles t ON e.emp_no = t.emp_no 
WHERE t.to_date = '9999-01-01'
LIMIT 10;
```
> **Why:** Filtering for the `'9999-01-01'` end date (the system's standard placeholder for an active, ongoing role) ensures you do not report on expired or previous job positions.

### Task 4 — Departmental Aggregation Reporting
Calculate the active headcount and financial distribution per department using aggregation and junction tables.

```sql
/* 1. Calculate the Active Headcount (Departments > 50,000 employees) */
SELECT d.dept_name, COUNT(de.emp_no) AS total_active_employees
FROM departments d
JOIN dept_emp de ON d.dept_no = de.dept_no
WHERE de.to_date = '9999-01-01'
GROUP BY d.dept_name
HAVING total_active_employees > 50000
ORDER BY total_active_employees DESC;
```

```sql
/* 2. Aggregate Active Compensation */
SELECT d.dept_name, ROUND(AVG(s.salary), 2) AS average_active_salary
FROM departments d
JOIN dept_emp de ON d.dept_no = de.dept_no
JOIN salaries s ON de.emp_no = s.emp_no
WHERE de.to_date = '9999-01-01' 
  AND s.to_date = '9999-01-01'
GROUP BY d.dept_name
ORDER BY average_active_salary DESC;
```
> **Why:** `GROUP BY` paired with aggregation functions (`COUNT`, `AVG`) transforms raw rows into actionable business intelligence. We must filter `to_date = '9999-01-01'` on both the department assignment and the salary to ensure accuracy.

### Task 5 — Report Operationalization
The HR Director needs to run the compensation report regularly but cannot write complex multi-table `JOIN`s. Save the logic permanently as a View.

```sql
/* 1. Create a Persistent HR View */
CREATE VIEW current_dept_salaries AS
SELECT d.dept_name, ROUND(AVG(s.salary), 2) AS average_active_salary
FROM departments d
JOIN dept_emp de ON d.dept_no = de.dept_no
JOIN salaries s ON de.emp_no = s.emp_no
WHERE de.to_date = '9999-01-01' 
  AND s.to_date = '9999-01-01'
GROUP BY d.dept_name;
```

---

## Validation
Run the following commands in your MySQL prompt to verify your database state and ensure your view was created successfully.

```sql
/* 1. Verify the active database context */
SELECT DATABASE();

/* 2. Verify the persistent view was successfully created */
SHOW FULL TABLES IN employees WHERE TABLE_TYPE LIKE 'VIEW';

/* 3. Verify the view returns the aggregated departmental salary data */
SELECT * FROM current_dept_salaries LIMIT 5;
```

Expected result:
- [ ] `SELECT DATABASE();` returns `employees`, confirming you are in the correct context.
- [ ] The `SHOW FULL TABLES` command lists `current_dept_salaries` as a `VIEW`.
- [ ] Querying the view successfully returns a table with `dept_name` and `average_active_salary` columns without syntax errors.
- [ ] Your earlier manual queries successfully filtered the 1990 hires and linked current active job titles (`to_date = '9999-01-01'`).

## References & further learning
- MySQL `JOIN` Syntax Documentation: https://dev.mysql.com/doc/refman/8.0/en/join.html
- MySQL `CREATE VIEW` Documentation: https://dev.mysql.com/doc/refman/8.0/en/create-view.html
- MySQL Aggregate Functions: https://dev.mysql.com/doc/refman/8.0/en/aggregate-functions.html
- KodeKloud course: Database Fundamentals: https://kodekloud.com/courses/database-fundamentals
