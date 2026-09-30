/* 1. Calculate the Active Headcount (Departments > 50,000 employees) */
SELECT d.dept_name, COUNT(de.emp_no) AS total_active_employees
FROM departments d
JOIN dept_emp de ON d.dept_no = de.dept_no
WHERE de.to_date = '9999-01-01'
GROUP BY d.dept_name
HAVING total_active_employees > 50000
ORDER BY total_active_employees DESC;
