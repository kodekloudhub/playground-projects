/* 2. Aggregate Active Compensation */
SELECT d.dept_name, ROUND(AVG(s.salary), 2) AS average_active_salary
FROM departments d
JOIN dept_emp de ON d.dept_no = de.dept_no
JOIN salaries s ON de.emp_no = s.emp_no
WHERE de.to_date = '9999-01-01' 
  AND s.to_date = '9999-01-01'
GROUP BY d.dept_name
ORDER BY average_active_salary DESC;
