/* Map employees to current roles, excluding historical jobs */
SELECT e.first_name, e.last_name, t.title 
FROM employees e 
JOIN titles t ON e.emp_no = t.emp_no 
WHERE t.to_date = '9999-01-01'
LIMIT 10;
