-- =====================================================================
--  Legal Case Management System  —  views.sql   (file 5 of 7)
--  Views replace stored "derived" columns and give ready-made reports.
--  Safe to re-run (CREATE OR REPLACE).
-- =====================================================================

USE legal_case_db;

-- Next upcoming hearing per case (replaces hearings.next_hearing_date)
CREATE OR REPLACE VIEW v_case_next_hearing AS
SELECT c.case_id,
       c.case_number,
       h.hearing_id,
       h.hearing_date AS next_hearing_date,
       h.start_time,
       h.judge_id,
       h.courtroom
FROM legal_cases c
LEFT JOIN hearings h
       ON h.hearing_id = (
            SELECT h2.hearing_id
            FROM hearings h2
            WHERE h2.case_id = c.case_id
              AND h2.status = 'Scheduled'
              AND TIMESTAMP(h2.hearing_date, h2.start_time) >= NOW()
            ORDER BY h2.hearing_date, h2.start_time, h2.hearing_id
            LIMIT 1);

-- Current location/holder of each evidence item (replaces evidence.storage_location)
CREATE OR REPLACE VIEW v_evidence_current_location AS
SELECT coc.evidence_id,
       coc.location      AS current_location,
       coc.to_user_id    AS current_holder_user_id,
       coc.transfer_date AS since
FROM chain_of_custody coc
WHERE coc.custody_id = (
    SELECT c2.custody_id
    FROM chain_of_custody c2
    WHERE c2.evidence_id = coc.evidence_id
    ORDER BY c2.transfer_date DESC, c2.custody_id DESC
    LIMIT 1
);

-- ---------------------------------------------------------------------
-- Report views
-- ---------------------------------------------------------------------

-- Hearing calendar: all upcoming scheduled hearings
CREATE OR REPLACE VIEW v_upcoming_hearings AS
SELECT h.hearing_id,
       h.hearing_date,
       h.start_time,
       h.end_time,
       c.case_number,
       c.case_type,
       ct.court_name,
       h.courtroom,
       j.name        AS judge_name,
       h.hearing_type,
       h.purpose
FROM hearings h
JOIN legal_cases c ON c.case_id  = h.case_id
JOIN courts ct     ON ct.court_id = c.court_id
JOIN judges j      ON j.judge_id  = h.judge_id
WHERE h.status = 'Scheduled'
  AND TIMESTAMP(h.hearing_date, h.start_time) >= NOW();

-- Deadline tracker: open deadlines with days left and an overdue flag
CREATE OR REPLACE VIEW v_pending_deadlines AS
SELECT d.deadline_id,
       c.case_number,
       d.deadline_type,
       d.due_date,
       d.reminder_date,
       d.status,
       u.full_name                              AS responsible_person,
       DATEDIFF(DATE(d.due_date), CURRENT_DATE) AS days_left,
       (d.due_date < NOW())                     AS is_overdue
FROM deadlines d
JOIN legal_cases c  ON c.case_id = d.case_id
JOIN system_users u ON u.user_id = d.responsible_user_id
WHERE d.status IN ('Pending','Extended');

-- Case dashboard: one row per active case
CREATE OR REPLACE VIEW v_case_summary AS
SELECT c.case_id,
       c.case_number,
       c.case_type,
       c.status,
       c.priority,
       ct.court_name,
       (SELECT j.name FROM case_judges cj JOIN judges j ON j.judge_id = cj.judge_id
         WHERE cj.case_id = c.case_id AND cj.assignment_role = 'Presiding' AND cj.end_date IS NULL
         LIMIT 1)                                                         AS presiding_judge,
       (SELECT COUNT(*) FROM case_parties cp
         WHERE cp.case_id = c.case_id AND cp.end_date IS NULL)            AS parties,
       (SELECT COUNT(*) FROM case_lawyers cl
         WHERE cl.case_id = c.case_id AND cl.end_date IS NULL)            AS lawyers,
       (SELECT MIN(h.hearing_date) FROM hearings h
         WHERE h.case_id = c.case_id AND h.status = 'Scheduled'
           AND h.hearing_date >= CURRENT_DATE)                            AS next_hearing,
       (SELECT COUNT(*) FROM deadlines d
         WHERE d.case_id = c.case_id AND d.status IN ('Pending','Extended')) AS open_deadlines
FROM legal_cases c
JOIN courts ct ON ct.court_id = c.court_id
WHERE c.is_active = 1;

-- Lawyer workload: current cases per lawyer
CREATE OR REPLACE VIEW v_lawyer_active_cases AS
SELECT l.lawyer_id,
       l.name AS lawyer_name,
       c.case_id,
       c.case_number,
       c.status AS case_status,
       cl.representation_type,
       cl.start_date
FROM case_lawyers cl
JOIN lawyers l     ON l.lawyer_id = cl.lawyer_id
JOIN legal_cases c ON c.case_id  = cl.case_id
WHERE cl.end_date IS NULL
  AND c.is_active = 1;
