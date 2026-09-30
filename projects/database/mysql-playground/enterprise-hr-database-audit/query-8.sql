/* 1. Verify the active database context */
SELECT DATABASE();

/* 2. Verify the persistent view was successfully created */
SHOW FULL TABLES IN employees WHERE TABLE_TYPE LIKE 'VIEW';

/* 3. Verify the view returns the aggregated departmental salary data */
SELECT * FROM current_dept_salaries LIMIT 5;
