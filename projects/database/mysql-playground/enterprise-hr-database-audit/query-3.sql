/* Extract female personnel hired strictly during the 1990 fiscal year */
SELECT emp_no, first_name, last_name, hire_date 
FROM employees 
WHERE gender = 'F' 
  AND hire_date BETWEEN '1990-01-01' AND '1990-12-31'
LIMIT 10;
