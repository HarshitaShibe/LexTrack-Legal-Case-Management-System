-- =====================================================================
--  Legal Case Management System  —  transactions.sql   (file 7 of 7)
--  Demonstrates COMMIT, ROLLBACK, SAVEPOINT, automatic rollback on error
--  and row locking. Run after sample_data.sql.
--
--  Every demo leaves the database consistent, and errors are caught inside
--  procedures, so the script never stops halfway (also in MySQL Workbench).
--  Demo 1 and Demo 3 add one deadline and one note each time they run;
--  the others undo all their changes.
-- =====================================================================

USE legal_case_db;

-- ---------------------------------------------------------------------
-- DEMO 1 — COMMIT: schedule work for a case as one unit
--   A deadline and a case note are saved together.
-- ---------------------------------------------------------------------
START TRANSACTION;

INSERT INTO deadlines (case_id, deadline_type, due_date, responsible_user_id, reminder_date, description)
VALUES (6, 'Hearing Prep', '2026-12-08 17:00:00', 10, '2026-12-06 09:00:00', 'Prepare admission arguments');

INSERT INTO case_notes (case_id, user_id, note_title, note_content, is_private)
VALUES (6, 10, 'Admission hearing plan', 'Keep invoice ledger and supply orders ready.', 1);

COMMIT;

SELECT 'Demo 1 (COMMIT): both rows saved' AS demo;
SELECT deadline_id, deadline_type, due_date, status FROM deadlines WHERE case_id = 6 ORDER BY deadline_id DESC LIMIT 1;

-- ---------------------------------------------------------------------
-- DEMO 2 — ROLLBACK: undo a change before it is saved
-- ---------------------------------------------------------------------
SELECT 'Demo 2 (ROLLBACK): priority before' AS demo, case_number, priority FROM legal_cases WHERE case_id = 3;

START TRANSACTION;
UPDATE legal_cases SET priority = 'Urgent' WHERE case_id = 3;
SELECT 'inside the transaction' AS demo, case_number, priority FROM legal_cases WHERE case_id = 3;
ROLLBACK;

SELECT 'after ROLLBACK (unchanged)' AS demo, case_number, priority FROM legal_cases WHERE case_id = 3;

-- ---------------------------------------------------------------------
-- DEMO 3 — SAVEPOINT: keep the first part, undo only the second part
-- ---------------------------------------------------------------------
START TRANSACTION;

INSERT INTO case_notes (case_id, user_id, note_title, note_content, is_private)
VALUES (3, 4, 'Registry note', 'Respondent served through registered post.', 0);

SAVEPOINT after_note;

UPDATE deadlines SET status = 'Extended', due_date = '2026-12-31 17:00:00' WHERE case_id = 3 AND status = 'Missed';
SELECT 'Demo 3 (SAVEPOINT): deadline changed inside transaction' AS demo, deadline_id, status, due_date
FROM deadlines WHERE case_id = 3;

ROLLBACK TO SAVEPOINT after_note;   -- undo only the deadline change
COMMIT;                             -- the note is saved

SELECT 'after ROLLBACK TO SAVEPOINT + COMMIT' AS demo, deadline_id, status, due_date FROM deadlines WHERE case_id = 3;
SELECT note_id, note_title FROM case_notes WHERE case_id = 3 ORDER BY note_id DESC LIMIT 1;

-- ---------------------------------------------------------------------
-- DEMO 4 — Automatic ROLLBACK on error (atomicity)
--   A procedure tries to add a deadline AND a hearing. The hearing double-books
--   Justice Sandhu (already sitting in case CR/45/2026 on 3 Dec 2026, 12:00), so the
--   trigger rejects it. The error handler rolls back BOTH inserts and reports why.
-- ---------------------------------------------------------------------
DROP PROCEDURE IF EXISTS demo_atomic_schedule;

DELIMITER $$
CREATE PROCEDURE demo_atomic_schedule()
BEGIN
    DECLARE v_msg TEXT;
    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        GET DIAGNOSTICS CONDITION 1 v_msg = MESSAGE_TEXT;
        ROLLBACK;
        SELECT 'Demo 4: transaction ROLLED BACK' AS demo, v_msg AS reason;
    END;

    START TRANSACTION;
    INSERT INTO deadlines (case_id, deadline_type, due_date, responsible_user_id, description)
    VALUES (1, 'Hearing Prep', '2026-12-02 17:00:00', 8, 'DEMO 4 — should never be saved');

    -- judge 2 is a Substitute on case 1, but is already busy at this time in case 2
    INSERT INTO hearings (case_id, judge_id, hearing_date, start_time, hearing_type, courtroom)
    VALUES (1, 2, '2026-12-03', '12:00', 'Arguments', 'Court Room 4');

    COMMIT;
    SELECT 'Demo 4: committed (not expected)' AS demo;
END$$
DELIMITER ;

CALL demo_atomic_schedule();

SELECT 'Demo 4: rows saved by the failed transaction (expect 0)' AS demo, COUNT(*) AS saved_rows
FROM deadlines WHERE description = 'DEMO 4 — should never be saved';

DROP PROCEDURE IF EXISTS demo_atomic_schedule;

-- ---------------------------------------------------------------------
-- DEMO 5 — Evidence transfer inside a transaction, then ROLLBACK
--   Shows the custody chain changing and being restored.
-- ---------------------------------------------------------------------
SELECT 'Demo 5: location before' AS demo, current_location, current_holder_user_id
FROM v_evidence_current_location WHERE evidence_id = 1;

START TRANSACTION;
CALL sp_transfer_evidence(1, 11, 'Re-examination requested by defence', 'State Forensic Science Lab, Mohali');
SELECT 'inside the transaction' AS demo, current_location, current_holder_user_id
FROM v_evidence_current_location WHERE evidence_id = 1;
ROLLBACK;

SELECT 'after ROLLBACK (back in the evidence room)' AS demo, current_location, current_holder_user_id
FROM v_evidence_current_location WHERE evidence_id = 1;

-- ---------------------------------------------------------------------
-- DEMO 6 — A rule violation caught and reported (consistency)
--   Trying to pronounce the draft interim order of case 1 as 'Overturned'
--   breaks the allowed status flow; the database refuses it.
-- ---------------------------------------------------------------------
DROP PROCEDURE IF EXISTS demo_rule_violation;

DELIMITER $$
CREATE PROCEDURE demo_rule_violation()
BEGIN
    DECLARE v_msg TEXT;
    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        GET DIAGNOSTICS CONDITION 1 v_msg = MESSAGE_TEXT;
        ROLLBACK;
        SELECT 'Demo 6: change refused by the database' AS demo, v_msg AS reason;
    END;
    START TRANSACTION;
    UPDATE judgments SET status = 'Overturned' WHERE judgment_id = 3;
    COMMIT;
END$$
DELIMITER ;

CALL demo_rule_violation();
SELECT 'Demo 6: status after (still Draft)' AS demo, judgment_id, status FROM judgments WHERE judgment_id = 3;
DROP PROCEDURE IF EXISTS demo_rule_violation;

-- ---------------------------------------------------------------------
-- DEMO 7 — Row locking between two users (isolation)  — run by hand
--   Open TWO query tabs (or two terminals) and run the steps in order.
--
--   Tab A:  START TRANSACTION;
--           SELECT * FROM legal_cases WHERE case_id = 2 FOR UPDATE;   -- locks case 2
--
--   Tab B:  START TRANSACTION;
--           CALL sp_transfer_evidence(2, 3, 'Court inspection', 'Court Room 1');
--           -- waits: the custody trigger needs the lock on case 2
--
--   Tab A:  COMMIT;                                                 -- releases the lock
--   Tab B:  -- the transfer now completes
--           ROLLBACK;                                               -- undo the demo transfer
--
--   The same lock is what stops two people from recording conflicting custody
--   transfers, two Presiding judges, or overlapping assignments at the same moment.
-- ---------------------------------------------------------------------
