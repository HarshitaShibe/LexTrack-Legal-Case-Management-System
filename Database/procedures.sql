-- =====================================================================
--  Legal Case Management System  —  procedures.sql   (file 2 of 7)
--  Run after schema.sql and BEFORE triggers.sql (the triggers call the helpers below).
--
--  Part A  Helper procedures used by the triggers
--  Part B  Everyday procedures for the application / demo
-- =====================================================================

USE legal_case_db;

DROP PROCEDURE IF EXISTS sp_require_active_user;
DROP PROCEDURE IF EXISTS sp_require_active_case;
DROP PROCEDURE IF EXISTS sp_check_hearing_slot;
DROP PROCEDURE IF EXISTS sp_open_case;
DROP PROCEDURE IF EXISTS sp_assign_judge;
DROP PROCEDURE IF EXISTS sp_schedule_hearing;
DROP PROCEDURE IF EXISTS sp_transfer_evidence;
DROP PROCEDURE IF EXISTS sp_complete_deadline;
DROP PROCEDURE IF EXISTS sp_close_case;
DROP PROCEDURE IF EXISTS sp_lawyer_cases;
DROP PROCEDURE IF EXISTS sp_case_timeline;

DELIMITER $$

-- ---------------------------------------------------------------------
-- PART A — helpers used by triggers.sql
-- ---------------------------------------------------------------------

-- helper: new records may only reference an ACTIVE user account
CREATE PROCEDURE sp_require_active_user(IN p_user_id INT)
BEGIN
    IF p_user_id IS NOT NULL AND NOT EXISTS
        (SELECT 1 FROM system_users WHERE user_id = p_user_id AND is_active = 1) THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'user account is inactive (or does not exist)';
    END IF;
END$$

-- helper: new records may only be added to an ACTIVE (not archived) case
CREATE PROCEDURE sp_require_active_case(IN p_case_id INT)
BEGIN
    IF NOT EXISTS (SELECT 1 FROM legal_cases WHERE case_id = p_case_id AND is_active = 1) THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'case is archived (is_active = 0): no new records can be added';
    END IF;
END$$

-- helper: a hearing slot must be free for the judge and for the courtroom of that court
CREATE PROCEDURE sp_check_hearing_slot(IN p_hearing_id INT, IN p_case_id INT, IN p_judge_id INT,
                                       IN p_date DATE, IN p_start TIME, IN p_end TIME, IN p_courtroom VARCHAR(100))
BEGIN
    DECLARE v_court INT;
    DECLARE v_end TIME;
    SET v_end = COALESCE(p_end, ADDTIME(p_start, '00:00:01'));      -- no end time = occupies its start moment
    SELECT court_id INTO v_court FROM legal_cases WHERE case_id = p_case_id;
    -- lock judge and court rows so two bookings for the same slot are checked one at a time
    SELECT judge_id INTO @lock_j FROM judges WHERE judge_id = p_judge_id FOR UPDATE;
    SELECT court_id INTO @lock_c FROM courts WHERE court_id = v_court FOR UPDATE;
    IF NOT EXISTS (SELECT 1 FROM judges WHERE judge_id = p_judge_id AND is_active = 1) THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'judge is inactive';
    END IF;
    IF EXISTS (SELECT 1 FROM hearings h
               WHERE h.judge_id = p_judge_id AND h.hearing_date = p_date
                 AND h.hearing_id <> COALESCE(p_hearing_id, 0) AND h.status <> 'Cancelled'
                 AND h.start_time < v_end
                 AND COALESCE(h.end_time, ADDTIME(h.start_time, '00:00:01')) > p_start) THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'judge already has a hearing at this time';
    END IF;
    IF p_courtroom IS NOT NULL AND EXISTS
              (SELECT 1 FROM hearings h JOIN legal_cases c ON c.case_id = h.case_id
               WHERE c.court_id = v_court AND h.courtroom = p_courtroom AND h.hearing_date = p_date
                 AND h.hearing_id <> COALESCE(p_hearing_id, 0) AND h.status <> 'Cancelled'
                 AND h.start_time < v_end
                 AND COALESCE(h.end_time, ADDTIME(h.start_time, '00:00:01')) > p_start) THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'courtroom is already booked at this time';
    END IF;
END$$

-- ---------------------------------------------------------------------
-- PART B — everyday procedures
-- ---------------------------------------------------------------------

-- Open a new case; returns the new case_id
CREATE PROCEDURE sp_open_case(IN p_case_number VARCHAR(50), IN p_case_type VARCHAR(30),
                              IN p_filing_date DATE, IN p_court_id INT, IN p_description TEXT,
                              OUT p_case_id INT)
BEGIN
    INSERT INTO legal_cases (case_number, case_type, filing_date, court_id, description)
    VALUES (p_case_number, p_case_type, p_filing_date, p_court_id, p_description);
    SET p_case_id = LAST_INSERT_ID();
END$$

-- Assign a judge to a case. A new Presiding judge automatically ends the current
-- Presiding assignment the day before. Both steps succeed or both are rolled back.
-- (Call it on its own, not inside another open transaction: START TRANSACTION commits any open one.)
CREATE PROCEDURE sp_assign_judge(IN p_case_id INT, IN p_judge_id INT, IN p_role VARCHAR(20), IN p_from DATE)
BEGIN
    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        ROLLBACK;
        RESIGNAL;
    END;
    START TRANSACTION;
    IF p_role = 'Presiding' THEN
        UPDATE case_judges
           SET end_date = DATE_SUB(p_from, INTERVAL 1 DAY)
         WHERE case_id = p_case_id AND assignment_role = 'Presiding' AND end_date IS NULL;
    END IF;
    INSERT INTO case_judges (case_id, judge_id, assignment_date, assignment_role)
    VALUES (p_case_id, p_judge_id, p_from, p_role);
    COMMIT;
END$$

-- Schedule a hearing; returns the new hearing_id
-- (the triggers check the judge's assignment and double-booking)
CREATE PROCEDURE sp_schedule_hearing(IN p_case_id INT, IN p_judge_id INT, IN p_date DATE,
                                     IN p_start TIME, IN p_end TIME, IN p_type VARCHAR(20),
                                     IN p_courtroom VARCHAR(100), IN p_purpose TEXT,
                                     OUT p_hearing_id INT)
BEGIN
    INSERT INTO hearings (case_id, judge_id, hearing_date, start_time, end_time, hearing_type, courtroom, purpose)
    VALUES (p_case_id, p_judge_id, p_date, p_start, p_end, p_type, p_courtroom, p_purpose);
    SET p_hearing_id = LAST_INSERT_ID();
END$$

-- Hand an evidence item to someone else. The current holder is looked up automatically.
CREATE PROCEDURE sp_transfer_evidence(IN p_evidence_id INT, IN p_to_user_id INT,
                                      IN p_reason VARCHAR(255), IN p_location VARCHAR(255))
BEGIN
    DECLARE v_holder INT;
    SELECT to_user_id INTO v_holder
      FROM chain_of_custody
     WHERE evidence_id = p_evidence_id
     ORDER BY transfer_date DESC, custody_id DESC
     LIMIT 1;
    INSERT INTO chain_of_custody (evidence_id, from_user_id, to_user_id, transfer_reason, location)
    VALUES (p_evidence_id, v_holder, p_to_user_id, p_reason, p_location);
END$$

-- Mark a deadline as completed now
CREATE PROCEDURE sp_complete_deadline(IN p_deadline_id INT)
BEGIN
    UPDATE deadlines
       SET status = 'Completed', completed_at = NOW()
     WHERE deadline_id = p_deadline_id;
END$$

-- Close a case (Disposed / Closed / Dismissed / Withdrawn) with its closing date
CREATE PROCEDURE sp_close_case(IN p_case_id INT, IN p_status VARCHAR(20), IN p_closed DATE)
BEGIN
    IF p_status NOT IN ('Disposed','Closed','Dismissed','Withdrawn') THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'closing status must be Disposed, Closed, Dismissed or Withdrawn';
    END IF;
    UPDATE legal_cases
       SET status = p_status, closed_date = p_closed
     WHERE case_id = p_case_id;
END$$

-- "My Cases": a lawyer's current cases with court and next hearing
CREATE PROCEDURE sp_lawyer_cases(IN p_lawyer_id INT)
BEGIN
    SELECT c.case_id, c.case_number, c.case_type, c.status, c.priority,
           ct.court_name, cl.representation_type,
           (SELECT MIN(h.hearing_date) FROM hearings h
             WHERE h.case_id = c.case_id AND h.status = 'Scheduled' AND h.hearing_date >= CURRENT_DATE) AS next_hearing
      FROM case_lawyers cl
      JOIN legal_cases c ON c.case_id = cl.case_id
      JOIN courts ct     ON ct.court_id = c.court_id
     WHERE cl.lawyer_id = p_lawyer_id
       AND cl.end_date IS NULL
       AND c.is_active = 1
     ORDER BY next_hearing IS NULL, next_hearing;
END$$

-- Case timeline: hearings, documents, judgments and deadlines in date order
CREATE PROCEDURE sp_case_timeline(IN p_case_id INT)
BEGIN
    SELECT event_date, event_type, details
      FROM (
            SELECT TIMESTAMP(hearing_date, start_time) AS event_date, 'Hearing' AS event_type,
                   CONCAT(hearing_type, ' hearing — ', status) AS details
              FROM hearings WHERE case_id = p_case_id
            UNION ALL
            SELECT uploaded_date, 'Document', CONCAT(document_type, ': ', title, ' (v', version, ')')
              FROM documents WHERE case_id = p_case_id
            UNION ALL
            SELECT TIMESTAMP(judgment_date), 'Judgment', CONCAT(judgment_type, ' — ', status)
              FROM judgments WHERE case_id = p_case_id
            UNION ALL
            SELECT due_date, 'Deadline', CONCAT(deadline_type, ' — ', status)
              FROM deadlines WHERE case_id = p_case_id
           ) AS t
     ORDER BY event_date;
END$$

DELIMITER ;
