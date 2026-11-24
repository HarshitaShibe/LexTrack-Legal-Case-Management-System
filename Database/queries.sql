-- =====================================================================
--  Legal Case Management System  —  queries.sql   (file 6 of 7)
--  Read-only: SELECT queries, JOINs, aggregation, subqueries, CTEs,
--  window functions, views and stored-procedure calls.
--  Safe to run any number of times.
-- =====================================================================

USE legal_case_db;

-- ---------------------------------------------------------------------
-- A. BASIC SELECT, WHERE, ORDER BY
-- ---------------------------------------------------------------------

-- Q1. All active cases, most urgent first
SELECT case_number, case_type, status, priority, filing_date
FROM legal_cases
WHERE is_active = 1
ORDER BY FIELD(priority, 'Urgent', 'High', 'Medium', 'Low'), filing_date;

-- Q2. Criminal and civil cases filed in 2026
SELECT case_number, case_type, filing_date
FROM legal_cases
WHERE case_type IN ('Criminal', 'Civil')
  AND filing_date BETWEEN '2026-01-01' AND '2026-12-31';

-- Q3. Search cases by keyword in the description
SELECT case_number, description
FROM legal_cases
WHERE description LIKE '%land%';

-- ---------------------------------------------------------------------
-- B. JOINS
-- ---------------------------------------------------------------------

-- Q4. Each case with its court and current presiding judge (INNER JOINs)
SELECT c.case_number, ct.court_name, ct.location, j.name AS presiding_judge
FROM legal_cases c
JOIN courts ct      ON ct.court_id = c.court_id
JOIN case_judges cj ON cj.case_id = c.case_id
                   AND cj.assignment_role = 'Presiding'
                   AND cj.end_date IS NULL
JOIN judges j       ON j.judge_id = cj.judge_id
ORDER BY c.case_number;

-- Q5. Parties and their lawyers for one case (M:N through link tables)
SELECT p.name AS party, cp.party_role, l.name AS lawyer, cl.representation_type
FROM case_parties cp
JOIN parties p       ON p.party_id = cp.party_id
JOIN case_lawyers cl ON cl.case_id = cp.case_id AND cl.end_date IS NULL
JOIN lawyers l       ON l.lawyer_id = cl.lawyer_id
WHERE cp.case_id = 1
  AND ((cp.party_role IN ('Plaintiff','Petitioner','Complainant','Appellant') AND cl.representation_type IN ('Counsel for Petitioner','Public Prosecutor'))
    OR (cp.party_role IN ('Defendant','Respondent','Accused')               AND cl.representation_type IN ('Counsel for Respondent','Defence Counsel')));

-- Q6. Cases with no scheduled hearing yet (LEFT JOIN ... IS NULL)
SELECT c.case_number, c.status
FROM legal_cases c
LEFT JOIN hearings h ON h.case_id = c.case_id AND h.status = 'Scheduled'
WHERE h.hearing_id IS NULL;

-- Q7. Evidence with who submitted it and where it is now (JOIN with a view)
SELECT e.evidence_id, c.case_number, e.evidence_type, e.description,
       u.full_name AS submitted_by, loc.current_location, holder.full_name AS current_holder
FROM evidence e
JOIN legal_cases c                  ON c.case_id = e.case_id
JOIN system_users u                 ON u.user_id = e.submitted_by_user_id
JOIN v_evidence_current_location loc ON loc.evidence_id = e.evidence_id
JOIN system_users holder            ON holder.user_id = loc.current_holder_user_id;

-- Q8. Full chain of custody for evidence item 1 (self-join style: two user joins)
SELECT coc.transfer_date, giver.full_name AS from_person, taker.full_name AS to_person,
       coc.transfer_reason, coc.location
FROM chain_of_custody coc
LEFT JOIN system_users giver ON giver.user_id = coc.from_user_id
JOIN system_users taker      ON taker.user_id = coc.to_user_id
WHERE coc.evidence_id = 1
ORDER BY coc.transfer_date, coc.custody_id;

-- ---------------------------------------------------------------------
-- C. AGGREGATION, GROUP BY, HAVING
-- ---------------------------------------------------------------------

-- Q9. Number of cases per court and type
SELECT ct.court_name, c.case_type, COUNT(*) AS cases
FROM legal_cases c
JOIN courts ct ON ct.court_id = c.court_id
GROUP BY ct.court_name, c.case_type
ORDER BY ct.court_name, cases DESC;

-- Q10. Lawyers handling more than one active case
SELECT l.name, COUNT(*) AS active_cases
FROM case_lawyers cl
JOIN lawyers l ON l.lawyer_id = cl.lawyer_id
WHERE cl.end_date IS NULL
GROUP BY l.lawyer_id, l.name
HAVING COUNT(*) > 1
ORDER BY active_cases DESC;

-- Q11. Hearing statistics per case
SELECT c.case_number,
       COUNT(h.hearing_id)                              AS total_hearings,
       SUM(h.status = 'Completed')                      AS completed,
       SUM(h.status = 'Adjourned')                      AS adjourned,
       SUM(h.status = 'Scheduled')                      AS upcoming
FROM legal_cases c
LEFT JOIN hearings h ON h.case_id = c.case_id
GROUP BY c.case_id, c.case_number
ORDER BY total_hearings DESC;

-- Q12. Judge workload: active assignments and upcoming hearings
SELECT j.name,
       (SELECT COUNT(*) FROM case_judges cj WHERE cj.judge_id = j.judge_id AND cj.end_date IS NULL) AS active_cases,
       (SELECT COUNT(*) FROM hearings h WHERE h.judge_id = j.judge_id AND h.status = 'Scheduled')   AS upcoming_hearings
FROM judges j
ORDER BY upcoming_hearings DESC;

-- Q13. Average number of days from filing to first hearing
SELECT ROUND(AVG(DATEDIFF(first_hearing, filing_date)), 1) AS avg_days_to_first_hearing
FROM (
    SELECT c.case_id, c.filing_date, MIN(h.hearing_date) AS first_hearing
    FROM legal_cases c
    JOIN hearings h ON h.case_id = c.case_id
    GROUP BY c.case_id, c.filing_date
) AS t;

-- ---------------------------------------------------------------------
-- D. SUBQUERIES
-- ---------------------------------------------------------------------

-- Q14. Cases that have at least one sensitive evidence item (EXISTS)
SELECT c.case_number, c.case_type
FROM legal_cases c
WHERE EXISTS (SELECT 1 FROM evidence e WHERE e.case_id = c.case_id AND e.is_sensitive = 1);

-- Q15. Users who have never uploaded a document (NOT IN)
SELECT full_name, user_role
FROM system_users
WHERE user_id NOT IN (SELECT uploaded_by_user_id FROM documents);

-- Q16. Latest hearing of every case (correlated subquery)
SELECT c.case_number, h.hearing_date, h.hearing_type, h.status
FROM hearings h
JOIN legal_cases c ON c.case_id = h.case_id
WHERE h.hearing_date = (SELECT MAX(h2.hearing_date) FROM hearings h2 WHERE h2.case_id = h.case_id);

-- Q17. Witnesses who appear in more than one case
SELECT w.name, w.is_expert
FROM witnesses w
WHERE w.witness_id IN (SELECT witness_id FROM case_witnesses GROUP BY witness_id HAVING COUNT(*) > 1);

-- ---------------------------------------------------------------------
-- E. CTEs AND WINDOW FUNCTIONS (MySQL 8)
-- ---------------------------------------------------------------------

-- Q18. Number every hearing within its case (ROW_NUMBER)
SELECT c.case_number, h.hearing_date, h.hearing_type, h.status,
       ROW_NUMBER() OVER (PARTITION BY h.case_id ORDER BY h.hearing_date) AS hearing_no
FROM hearings h
JOIN legal_cases c ON c.case_id = h.case_id
ORDER BY c.case_number, hearing_no;

-- Q19. Rank lawyers by current caseload (CTE + RANK)
WITH load_per_lawyer AS (
    SELECT l.lawyer_id, l.name, COUNT(cl.case_lawyer_id) AS active_cases
    FROM lawyers l
    LEFT JOIN case_lawyers cl ON cl.lawyer_id = l.lawyer_id AND cl.end_date IS NULL
    GROUP BY l.lawyer_id, l.name
)
SELECT name, active_cases, RANK() OVER (ORDER BY active_cases DESC) AS caseload_rank
FROM load_per_lawyer;

-- Q20. Gap in days between consecutive hearings of a case (LAG)
SELECT c.case_number, h.hearing_date,
       DATEDIFF(h.hearing_date, LAG(h.hearing_date) OVER (PARTITION BY h.case_id ORDER BY h.hearing_date)) AS days_since_previous
FROM hearings h
JOIN legal_cases c ON c.case_id = h.case_id
WHERE h.status <> 'Cancelled'
ORDER BY c.case_number, h.hearing_date;

-- ---------------------------------------------------------------------
-- F. CASE EXPRESSIONS AND DATES
-- ---------------------------------------------------------------------

-- Q21. Deadline tracker with a readable urgency label
SELECT c.case_number, d.deadline_type, d.due_date, d.status,
       CASE
           WHEN d.status = 'Completed'         THEN 'Done'
           WHEN d.status = 'Missed'            THEN 'Missed'
           WHEN d.due_date < NOW()             THEN 'Overdue'
           WHEN d.due_date < NOW() + INTERVAL 7 DAY THEN 'Due this week'
           ELSE 'Upcoming'
       END AS urgency
FROM deadlines d
JOIN legal_cases c ON c.case_id = d.case_id
ORDER BY d.due_date;

-- Q22. Document version history (current file + all earlier files)
SELECT d.title, d.version AS version_no, d.file_reference, 'current' AS kind
FROM documents d WHERE d.document_id IN (SELECT document_id FROM document_versions)
UNION ALL
SELECT d.title, v.version_number, v.file_reference, 'previous'
FROM document_versions v JOIN documents d ON d.document_id = v.document_id
ORDER BY title, version_no DESC;

-- ---------------------------------------------------------------------
-- G. VIEWS
-- ---------------------------------------------------------------------

-- Q23. Case dashboard
SELECT * FROM v_case_summary;

-- Q24. Hearing calendar
SELECT * FROM v_upcoming_hearings ORDER BY hearing_date, start_time;

-- Q25. Open deadlines
SELECT * FROM v_pending_deadlines ORDER BY due_date;

-- Q26. Next hearing per case
SELECT * FROM v_case_next_hearing;

-- ---------------------------------------------------------------------
-- H. STORED PROCEDURES
-- ---------------------------------------------------------------------

-- Q27. "My Cases" for Adv. Rajesh Sharma (lawyer_id 1)
CALL sp_lawyer_cases(1);

-- Q28. Timeline of case CS/101/2026 in Patiala (case_id 1)
CALL sp_case_timeline(1);

-- ---------------------------------------------------------------------
-- I. VERIFY THE INSTALLATION
-- ---------------------------------------------------------------------

-- Q29. Object counts: expect 20 tables, 6 views, 44 triggers, 11 procedures
SELECT
  (SELECT COUNT(*) FROM information_schema.tables   WHERE table_schema = 'legal_case_db' AND table_type = 'BASE TABLE') AS tables_count,
  (SELECT COUNT(*) FROM information_schema.tables   WHERE table_schema = 'legal_case_db' AND table_type = 'VIEW')       AS views_count,
  (SELECT COUNT(*) FROM information_schema.triggers WHERE trigger_schema = 'legal_case_db')                             AS triggers_count,
  (SELECT COUNT(*) FROM information_schema.routines WHERE routine_schema = 'legal_case_db' AND routine_type = 'PROCEDURE') AS procedures_count;
