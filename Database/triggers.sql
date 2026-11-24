-- =====================================================================
--  Legal Case Management System  —  triggers.sql   (file 3 of 7)
--  Run after procedures.sql (several triggers CALL the helper procedures).
--
--  Rules enforced here (the database refuses anything that breaks them):
--   * no hard delete of cases, documents, evidence, judgments, custody records,
--     document versions or assignments  (soft delete / end_date instead)
--   * chain_of_custody and document_versions are append-only; custody forms an
--     unbroken chain (from = current holder, no back-dating); every new evidence
--     item gets an automatic intake record
--   * evidence provenance (hash, case, submitter, date) and document case/type are locked
--   * documents: new file => version + 1 and the old file is saved in document_versions
--   * judgments: allowed status transitions only; content locked after Draft;
--     linked document must be a Filed/Accepted Judgment/Order of the same case
--   * judges/lawyers/parties assignments: no overlapping periods, history locked
--     (only end_date can be set, once), judge from the case's own court,
--     one active Presiding judge per case
--   * hearings/judgments: judge must be assigned to the case on that date;
--     no double-booking of a judge or a courtroom
--   * inactive users, judges, lawyers, parties, witnesses, courts and archived cases
--     can't be used in new records; linked judge/lawyer logins keep their role
-- =====================================================================

USE legal_case_db;

DROP TRIGGER IF EXISTS trg_coc_no_update;
DROP TRIGGER IF EXISTS trg_coc_no_delete;
DROP TRIGGER IF EXISTS trg_evidence_no_delete;
DROP TRIGGER IF EXISTS trg_evidence_lock_hash;
DROP TRIGGER IF EXISTS trg_coc_chain;
DROP TRIGGER IF EXISTS trg_judgments_no_delete;
DROP TRIGGER IF EXISTS trg_judgments_lock;
DROP TRIGGER IF EXISTS trg_cases_no_delete;
DROP TRIGGER IF EXISTS trg_documents_no_delete;
DROP TRIGGER IF EXISTS trg_documents_version;
DROP TRIGGER IF EXISTS trg_judgments_doc_case;
DROP TRIGGER IF EXISTS trg_judges_role_ins;
DROP TRIGGER IF EXISTS trg_judges_role_upd;
DROP TRIGGER IF EXISTS trg_lawyers_role_ins;
DROP TRIGGER IF EXISTS trg_lawyers_role_upd;
DROP TRIGGER IF EXISTS trg_users_role_lock;
DROP TRIGGER IF EXISTS trg_cases_court_lock;
DROP TRIGGER IF EXISTS trg_case_judges_ins;
DROP TRIGGER IF EXISTS trg_case_judges_upd;
DROP TRIGGER IF EXISTS trg_case_judges_no_delete;
DROP TRIGGER IF EXISTS trg_case_lawyers_ins;
DROP TRIGGER IF EXISTS trg_case_lawyers_upd;
DROP TRIGGER IF EXISTS trg_case_lawyers_no_delete;
DROP TRIGGER IF EXISTS trg_case_parties_ins;
DROP TRIGGER IF EXISTS trg_case_parties_upd;
DROP TRIGGER IF EXISTS trg_case_parties_no_delete;
DROP TRIGGER IF EXISTS trg_hearings_judge_ins;
DROP TRIGGER IF EXISTS trg_hearings_judge_upd;
DROP TRIGGER IF EXISTS trg_evidence_intake;
DROP TRIGGER IF EXISTS trg_documents_keep_old;
DROP TRIGGER IF EXISTS trg_docver_no_update;
DROP TRIGGER IF EXISTS trg_docver_no_delete;
DROP TRIGGER IF EXISTS trg_documents_active;
DROP TRIGGER IF EXISTS trg_evidence_active;
DROP TRIGGER IF EXISTS trg_deadlines_active_ins;
DROP TRIGGER IF EXISTS trg_deadlines_active_upd;
DROP TRIGGER IF EXISTS trg_notes_active;
DROP TRIGGER IF EXISTS trg_notes_lock;
DROP TRIGGER IF EXISTS trg_cases_court_active;
DROP TRIGGER IF EXISTS trg_case_wit_active;
DROP TRIGGER IF EXISTS trg_ev_wit_ins;
DROP TRIGGER IF EXISTS trg_ev_wit_upd;
DROP TRIGGER IF EXISTS trg_case_wit_upd;
DROP TRIGGER IF EXISTS trg_case_wit_del;

DELIMITER $$

-- chain_of_custody is append-only
CREATE TRIGGER trg_coc_no_update BEFORE UPDATE ON chain_of_custody
FOR EACH ROW
BEGIN
    SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT = 'chain_of_custody is append-only: insert a new transfer instead of updating';
END$$

CREATE TRIGGER trg_coc_no_delete BEFORE DELETE ON chain_of_custody
FOR EACH ROW
BEGIN
    SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT = 'chain_of_custody records cannot be deleted';
END$$

-- evidence: no hard delete, integrity_hash is immutable
CREATE TRIGGER trg_evidence_no_delete BEFORE DELETE ON evidence
FOR EACH ROW
BEGIN
    SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT = 'evidence cannot be deleted: set is_active = 0 or change status';
END$$

-- evidence provenance is immutable: hash, owning case, submitter, submission time
CREATE TRIGGER trg_evidence_lock_hash BEFORE UPDATE ON evidence
FOR EACH ROW
BEGIN
    IF NOT (NEW.integrity_hash <=> OLD.integrity_hash) THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'evidence.integrity_hash cannot be changed';
    END IF;
    IF NOT (NEW.case_id <=> OLD.case_id
        AND NEW.submitted_by_user_id <=> OLD.submitted_by_user_id
        AND NEW.submission_date <=> OLD.submission_date) THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'evidence case_id / submitted_by_user_id / submission_date cannot be changed';
    END IF;
END$$

-- chain_of_custody must form an unbroken chain
CREATE TRIGGER trg_coc_chain BEFORE INSERT ON chain_of_custody
FOR EACH ROW
BEGIN
    DECLARE last_holder INT DEFAULT NULL;
    DECLARE last_date DATETIME DEFAULT NULL;
    DECLARE n INT DEFAULT 0;
    DECLARE dummy INT;
    DECLARE v_case INT;
    CALL sp_require_active_user(NEW.to_user_id);
    -- lock the evidence's case row: concurrent transfers of the same item wait for each other
    SELECT case_id INTO v_case FROM evidence WHERE evidence_id = NEW.evidence_id;
    SELECT case_id INTO dummy FROM legal_cases WHERE case_id = v_case FOR UPDATE;
    -- locking reads always see the latest committed transfers
    SELECT COUNT(*) INTO n FROM chain_of_custody WHERE evidence_id = NEW.evidence_id FOR SHARE;
    IF n = 0 THEN
        IF NEW.from_user_id IS NOT NULL THEN
            SIGNAL SQLSTATE '45000'
                SET MESSAGE_TEXT = 'first custody entry (intake) must have from_user_id = NULL';
        END IF;
    ELSE
        SELECT to_user_id, transfer_date INTO last_holder, last_date FROM chain_of_custody
        WHERE evidence_id = NEW.evidence_id
        ORDER BY transfer_date DESC, custody_id DESC LIMIT 1 FOR SHARE;
        IF NEW.transfer_date < last_date THEN
            SIGNAL SQLSTATE '45000'
                SET MESSAGE_TEXT = 'transfer_date cannot be earlier than the previous transfer';
        END IF;
        IF NOT (NEW.from_user_id <=> last_holder) THEN
            SIGNAL SQLSTATE '45000'
                SET MESSAGE_TEXT = 'from_user_id must be the current holder of the evidence';
        END IF;
        IF NEW.from_user_id = NEW.to_user_id THEN
            SIGNAL SQLSTATE '45000'
                SET MESSAGE_TEXT = 'from_user_id and to_user_id cannot be the same';
        END IF;
    END IF;
END$$

-- judgments: no delete; content editable only while Draft (status can still move on)
CREATE TRIGGER trg_judgments_no_delete BEFORE DELETE ON judgments
FOR EACH ROW
BEGIN
    SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT = 'judgments cannot be deleted';
END$$

CREATE TRIGGER trg_judgments_lock BEFORE UPDATE ON judgments
FOR EACH ROW
BEGIN
    IF NOT (NEW.case_id <=> OLD.case_id AND NEW.judge_id <=> OLD.judge_id AND NEW.judgment_date <=> OLD.judgment_date) THEN
        IF NOT EXISTS (SELECT 1 FROM case_judges cj
                       WHERE cj.case_id = NEW.case_id AND cj.judge_id = NEW.judge_id
                         AND NEW.judgment_date >= cj.assignment_date
                         AND (cj.end_date IS NULL OR NEW.judgment_date <= cj.end_date)) THEN
            SIGNAL SQLSTATE '45000'
                SET MESSAGE_TEXT = 'judgment judge must be assigned to the case on the judgment date';
        END IF;
    END IF;
    IF NEW.document_id IS NOT NULL AND NOT EXISTS
        (SELECT 1 FROM documents d WHERE d.document_id = NEW.document_id AND d.document_type IN ('Judgment','Order')) THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'a judgment can only link a document of type Judgment or Order';
    END IF;
    -- allowed status changes:
    --   Draft -> Pronounced | Voided
    --   Pronounced -> Appealed | Voided
    --   Appealed -> Pronounced (appeal dismissed) | Overturned | Voided
    --   Overturned, Voided -> final
    IF NOT (NEW.status <=> OLD.status) AND NOT (
           (OLD.status = 'Draft'      AND NEW.status IN ('Pronounced','Voided'))
        OR (OLD.status = 'Pronounced' AND NEW.status IN ('Appealed','Voided'))
        OR (OLD.status = 'Appealed'   AND NEW.status IN ('Pronounced','Overturned','Voided'))) THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'invalid judgment status change';
    END IF;
    IF NEW.document_id IS NOT NULL AND NEW.status <> 'Draft' AND NOT EXISTS
        (SELECT 1 FROM documents d WHERE d.document_id = NEW.document_id AND d.status IN ('Filed','Accepted')) THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'a pronounced judgment can only link a Filed or Accepted document';
    END IF;
    IF NEW.document_id IS NOT NULL AND NOT EXISTS
        (SELECT 1 FROM documents d WHERE d.document_id = NEW.document_id AND d.case_id = NEW.case_id) THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'judgments.document_id must belong to the same case';
    END IF;
    IF OLD.status <> 'Draft' AND NOT (
            NEW.case_id       <=> OLD.case_id
        AND NEW.judge_id      <=> OLD.judge_id
        AND NEW.document_id   <=> OLD.document_id
        AND NEW.judgment_type <=> OLD.judgment_type
        AND NEW.judgment_date <=> OLD.judgment_date
        AND NEW.decision      <=> OLD.decision
        AND NEW.penalties     <=> OLD.penalties
    ) THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'judgment content is locked once it is no longer Draft (only status/notes can change)';
    END IF;
END$$

-- legal_cases and documents: soft delete only
CREATE TRIGGER trg_cases_no_delete BEFORE DELETE ON legal_cases
FOR EACH ROW
BEGIN
    SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT = 'legal_cases cannot be deleted: set is_active = 0 or close the case';
END$$

CREATE TRIGGER trg_documents_no_delete BEFORE DELETE ON documents
FOR EACH ROW
BEGIN
    SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT = 'documents cannot be deleted: set is_active = 0';
END$$

-- documents: new file => version + 1 automatically
CREATE TRIGGER trg_documents_version BEFORE UPDATE ON documents
FOR EACH ROW
BEGIN
    IF NOT (NEW.case_id <=> OLD.case_id) THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'documents.case_id cannot be changed (a filed document stays with its case)';
    END IF;
    IF NOT (NEW.uploaded_by_user_id <=> OLD.uploaded_by_user_id) AND (NEW.file_reference <=> OLD.file_reference) THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'uploaded_by_user_id changes only when a new file is uploaded';
    END IF;
    IF NOT (NEW.uploaded_by_user_id <=> OLD.uploaded_by_user_id AND NEW.file_reference <=> OLD.file_reference) THEN
        CALL sp_require_active_user(NEW.uploaded_by_user_id);   -- new file or new uploader: account must be active
    END IF;
    IF NOT (NEW.document_type <=> OLD.document_type) THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'documents.document_type cannot be changed after filing';
    END IF;
    IF NOT (NEW.file_reference <=> OLD.file_reference) THEN
        SET NEW.version = OLD.version + 1;
        SET NEW.uploaded_date = CURRENT_TIMESTAMP;
    ELSE
        SET NEW.version = OLD.version;   -- version can't be edited by hand
    END IF;
END$$

-- judgments: linked document must be from the same case (insert)
CREATE TRIGGER trg_judgments_doc_case BEFORE INSERT ON judgments
FOR EACH ROW
BEGIN
    CALL sp_require_active_case(NEW.case_id);
    IF NOT EXISTS (SELECT 1 FROM case_judges cj
                   WHERE cj.case_id = NEW.case_id AND cj.judge_id = NEW.judge_id
                     AND NEW.judgment_date >= cj.assignment_date
                     AND (cj.end_date IS NULL OR NEW.judgment_date <= cj.end_date)) THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'judgment judge must be assigned to the case on the judgment date';
    END IF;
    IF NEW.status NOT IN ('Draft','Pronounced') THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'a new judgment must start as Draft or Pronounced';
    END IF;
    IF NEW.document_id IS NOT NULL AND NOT EXISTS
        (SELECT 1 FROM documents d WHERE d.document_id = NEW.document_id AND d.document_type IN ('Judgment','Order')) THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'a judgment can only link a document of type Judgment or Order';
    END IF;
    IF NEW.document_id IS NOT NULL AND NOT EXISTS
        (SELECT 1 FROM documents d WHERE d.document_id = NEW.document_id AND d.case_id = NEW.case_id) THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'judgments.document_id must belong to the same case';
    END IF;
    IF NEW.document_id IS NOT NULL AND NEW.status <> 'Draft' AND NOT EXISTS
        (SELECT 1 FROM documents d WHERE d.document_id = NEW.document_id AND d.status IN ('Filed','Accepted')) THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'a pronounced judgment can only link a Filed or Accepted document';
    END IF;
END$$

-- judges.user_id must point to a 'Judge' account, lawyers.user_id to a 'Lawyer' account
CREATE TRIGGER trg_judges_role_ins BEFORE INSERT ON judges
FOR EACH ROW
BEGIN
    IF NEW.user_id IS NOT NULL AND NOT EXISTS
        (SELECT 1 FROM system_users u WHERE u.user_id = NEW.user_id AND u.user_role = 'Judge') THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'judges.user_id must be a user with role Judge';
    END IF;
    CALL sp_require_active_user(NEW.user_id);
END$$

CREATE TRIGGER trg_judges_role_upd BEFORE UPDATE ON judges
FOR EACH ROW
BEGIN
    IF NOT (NEW.court_id <=> OLD.court_id) AND EXISTS
        (SELECT 1 FROM case_judges WHERE judge_id = OLD.judge_id AND end_date IS NULL) THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'judge has active case assignments: end them before changing court';
    END IF;
    IF NEW.user_id IS NOT NULL AND NOT EXISTS
        (SELECT 1 FROM system_users u WHERE u.user_id = NEW.user_id AND u.user_role = 'Judge') THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'judges.user_id must be a user with role Judge';
    END IF;
    CALL sp_require_active_user(NEW.user_id);
END$$

CREATE TRIGGER trg_lawyers_role_ins BEFORE INSERT ON lawyers
FOR EACH ROW
BEGIN
    IF NEW.user_id IS NOT NULL AND NOT EXISTS
        (SELECT 1 FROM system_users u WHERE u.user_id = NEW.user_id AND u.user_role = 'Lawyer') THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'lawyers.user_id must be a user with role Lawyer';
    END IF;
    CALL sp_require_active_user(NEW.user_id);
END$$

CREATE TRIGGER trg_lawyers_role_upd BEFORE UPDATE ON lawyers
FOR EACH ROW
BEGIN
    IF NEW.user_id IS NOT NULL AND NOT EXISTS
        (SELECT 1 FROM system_users u WHERE u.user_id = NEW.user_id AND u.user_role = 'Lawyer') THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'lawyers.user_id must be a user with role Lawyer';
    END IF;
    CALL sp_require_active_user(NEW.user_id);
END$$

-- a linked judge/lawyer account cannot have its role changed away from Judge/Lawyer
CREATE TRIGGER trg_users_role_lock BEFORE UPDATE ON system_users
FOR EACH ROW
BEGIN
    IF NEW.user_role <> OLD.user_role THEN
        IF NEW.user_role <> 'Judge' AND EXISTS (SELECT 1 FROM judges WHERE user_id = OLD.user_id) THEN
            SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'user is linked to a judge: role must stay Judge';
        END IF;
        IF NEW.user_role <> 'Lawyer' AND EXISTS (SELECT 1 FROM lawyers WHERE user_id = OLD.user_id) THEN
            SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'user is linked to a lawyer: role must stay Lawyer';
        END IF;
    END IF;
END$$

-- a case can't move to another court while judges are actively assigned to it
CREATE TRIGGER trg_cases_court_lock BEFORE UPDATE ON legal_cases
FOR EACH ROW
BEGIN
    IF NOT (NEW.court_id <=> OLD.court_id) AND EXISTS
        (SELECT 1 FROM case_judges WHERE case_id = OLD.case_id AND end_date IS NULL) THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'case has active judge assignments: end them before transferring court';
    END IF;
    IF NOT (NEW.court_id <=> OLD.court_id) AND NOT EXISTS
        (SELECT 1 FROM courts WHERE court_id = NEW.court_id AND is_active = 1) THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'court is inactive';
    END IF;
END$$

-- ---------------- case_judges: assignment history ----------------
-- rules: judge from the case's court; no overlapping period for the same judge on the same case
--        (re-appointment allowed after the previous one ended); one active Presiding judge per case;
--        once created only end_date may be set (once); no delete
CREATE TRIGGER trg_case_judges_ins BEFORE INSERT ON case_judges
FOR EACH ROW
BEGIN
    DECLARE dummy INT;
    CALL sp_require_active_case(NEW.case_id);
    -- lock the case row so concurrent assignments for the same case are checked one at a time
    SELECT case_id INTO dummy FROM legal_cases WHERE case_id = NEW.case_id FOR UPDATE;
    IF NOT EXISTS (SELECT 1 FROM judges j JOIN legal_cases c ON c.court_id = j.court_id
                   WHERE j.judge_id = NEW.judge_id AND c.case_id = NEW.case_id) THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'judge must belong to the same court as the case';
    END IF;
    IF NOT EXISTS (SELECT 1 FROM judges WHERE judge_id = NEW.judge_id AND is_active = 1) THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'judge is inactive';
    END IF;
    IF EXISTS (SELECT 1 FROM case_judges WHERE case_id = NEW.case_id AND judge_id = NEW.judge_id
               AND assignment_date <= COALESCE(NEW.end_date, '9999-12-31')
               AND COALESCE(end_date, '9999-12-31') >= NEW.assignment_date FOR SHARE) THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'judge already assigned to this case for an overlapping period';
    END IF;
    IF NEW.assignment_role = 'Presiding' AND NEW.end_date IS NULL AND EXISTS
        (SELECT 1 FROM case_judges WHERE case_id = NEW.case_id AND assignment_role = 'Presiding' AND end_date IS NULL FOR SHARE) THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'case already has an active Presiding judge: end that assignment first';
    END IF;
END$$

CREATE TRIGGER trg_case_judges_upd BEFORE UPDATE ON case_judges
FOR EACH ROW
BEGIN
    IF NOT (NEW.case_id <=> OLD.case_id AND NEW.judge_id <=> OLD.judge_id
            AND NEW.assignment_date <=> OLD.assignment_date AND NEW.assignment_role <=> OLD.assignment_role) THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'assignment history is locked: only end_date can be set';
    END IF;
    IF OLD.end_date IS NOT NULL AND NOT (NEW.end_date <=> OLD.end_date) THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'assignment already ended: add a new assignment instead';
    END IF;
    IF NOT (NEW.end_date <=> OLD.end_date) AND EXISTS
        (SELECT 1 FROM case_judges WHERE case_id = NEW.case_id AND judge_id = NEW.judge_id
         AND case_judge_id <> NEW.case_judge_id
         AND assignment_date <= COALESCE(NEW.end_date, '9999-12-31')
         AND COALESCE(end_date, '9999-12-31') >= NEW.assignment_date) THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'new end_date would overlap another period for the same case';
    END IF;
    IF NEW.end_date IS NOT NULL AND OLD.end_date IS NULL AND (
         EXISTS (SELECT 1 FROM hearings WHERE case_id = NEW.case_id AND judge_id = NEW.judge_id
                 AND status <> 'Cancelled' AND hearing_date > NEW.end_date)
      OR EXISTS (SELECT 1 FROM judgments WHERE case_id = NEW.case_id AND judge_id = NEW.judge_id
                 AND status <> 'Voided' AND judgment_date > NEW.end_date)) THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'judge has hearings or judgments after this end_date: reassign them or choose a later date';
    END IF;
END$$

CREATE TRIGGER trg_case_judges_no_delete BEFORE DELETE ON case_judges
FOR EACH ROW
BEGIN
    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'judge assignments cannot be deleted: set end_date instead';
END$$

-- ---------------- case_lawyers / case_parties: same history rules ----------------
CREATE TRIGGER trg_case_lawyers_ins BEFORE INSERT ON case_lawyers
FOR EACH ROW
BEGIN
    DECLARE dummy INT;
    CALL sp_require_active_case(NEW.case_id);
    -- lock the case row so concurrent assignments for the same case are checked one at a time
    SELECT case_id INTO dummy FROM legal_cases WHERE case_id = NEW.case_id FOR UPDATE;
    IF NOT EXISTS (SELECT 1 FROM lawyers WHERE lawyer_id = NEW.lawyer_id AND is_active = 1) THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'lawyer is inactive';
    END IF;
    IF EXISTS (SELECT 1 FROM case_lawyers WHERE case_id = NEW.case_id AND lawyer_id = NEW.lawyer_id
               AND start_date <= COALESCE(NEW.end_date, '9999-12-31')
               AND COALESCE(end_date, '9999-12-31') >= NEW.start_date) THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'lawyer already on this case for an overlapping period';
    END IF;
END$$

CREATE TRIGGER trg_case_lawyers_upd BEFORE UPDATE ON case_lawyers
FOR EACH ROW
BEGIN
    IF NOT (NEW.case_id <=> OLD.case_id AND NEW.lawyer_id <=> OLD.lawyer_id
            AND NEW.start_date <=> OLD.start_date AND NEW.representation_type <=> OLD.representation_type) THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'representation history is locked: only end_date can be set';
    END IF;
    IF OLD.end_date IS NOT NULL AND NOT (NEW.end_date <=> OLD.end_date) THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'representation already ended: add a new row instead';
    END IF;
    IF NOT (NEW.end_date <=> OLD.end_date) AND EXISTS
        (SELECT 1 FROM case_lawyers WHERE case_id = NEW.case_id AND lawyer_id = NEW.lawyer_id
         AND case_lawyer_id <> NEW.case_lawyer_id
         AND start_date <= COALESCE(NEW.end_date, '9999-12-31')
         AND COALESCE(end_date, '9999-12-31') >= NEW.start_date) THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'new end_date would overlap another period for the same case';
    END IF;
END$$

CREATE TRIGGER trg_case_lawyers_no_delete BEFORE DELETE ON case_lawyers
FOR EACH ROW
BEGIN
    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'lawyer assignments cannot be deleted: set end_date instead';
END$$

CREATE TRIGGER trg_case_parties_ins BEFORE INSERT ON case_parties
FOR EACH ROW
BEGIN
    DECLARE dummy INT;
    CALL sp_require_active_case(NEW.case_id);
    -- lock the case row so concurrent assignments for the same case are checked one at a time
    SELECT case_id INTO dummy FROM legal_cases WHERE case_id = NEW.case_id FOR UPDATE;
    IF NOT EXISTS (SELECT 1 FROM parties WHERE party_id = NEW.party_id AND is_active = 1) THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'party is inactive';
    END IF;
    IF EXISTS (SELECT 1 FROM case_parties WHERE case_id = NEW.case_id AND party_id = NEW.party_id
               AND party_role = NEW.party_role
               AND start_date <= COALESCE(NEW.end_date, '9999-12-31')
               AND COALESCE(end_date, '9999-12-31') >= NEW.start_date) THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'party already holds this role in the case for an overlapping period';
    END IF;
END$$

CREATE TRIGGER trg_case_parties_upd BEFORE UPDATE ON case_parties
FOR EACH ROW
BEGIN
    IF NOT (NEW.case_id <=> OLD.case_id AND NEW.party_id <=> OLD.party_id
            AND NEW.start_date <=> OLD.start_date AND NEW.party_role <=> OLD.party_role) THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'party history is locked: only end_date can be set';
    END IF;
    IF OLD.end_date IS NOT NULL AND NOT (NEW.end_date <=> OLD.end_date) THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'party role already ended: add a new row instead';
    END IF;
    IF NOT (NEW.end_date <=> OLD.end_date) AND EXISTS
        (SELECT 1 FROM case_parties WHERE case_id = NEW.case_id AND party_id = NEW.party_id AND party_role = NEW.party_role
         AND case_party_id <> NEW.case_party_id
         AND start_date <= COALESCE(NEW.end_date, '9999-12-31')
         AND COALESCE(end_date, '9999-12-31') >= NEW.start_date) THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'new end_date would overlap another period for the same case';
    END IF;
END$$

CREATE TRIGGER trg_case_parties_no_delete BEFORE DELETE ON case_parties
FOR EACH ROW
BEGIN
    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'party assignments cannot be deleted: set end_date instead';
END$$

-- ---------------- hearings: judge must be assigned to the case ON the hearing date ----------------
-- (any assigned role may sit; a stand-in is added to case_judges as 'Substitute')
CREATE TRIGGER trg_hearings_judge_ins BEFORE INSERT ON hearings
FOR EACH ROW
BEGIN
    CALL sp_require_active_case(NEW.case_id);
    IF NOT EXISTS (SELECT 1 FROM case_judges cj
                   WHERE cj.case_id = NEW.case_id AND cj.judge_id = NEW.judge_id
                     AND NEW.hearing_date >= cj.assignment_date
                     AND (cj.end_date IS NULL OR NEW.hearing_date <= cj.end_date)) THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'hearing judge must be assigned to the case on the hearing date';
    END IF;
    IF NEW.status <> 'Cancelled' THEN
        CALL sp_check_hearing_slot(NULL, NEW.case_id, NEW.judge_id, NEW.hearing_date, NEW.start_time, NEW.end_time, NEW.courtroom);
    END IF;
END$$

CREATE TRIGGER trg_hearings_judge_upd BEFORE UPDATE ON hearings
FOR EACH ROW
BEGIN
    IF NEW.status <> 'Cancelled'
       AND NOT (NEW.case_id <=> OLD.case_id AND NEW.judge_id <=> OLD.judge_id
                AND NEW.hearing_date <=> OLD.hearing_date AND NEW.status <=> OLD.status)
       AND NOT EXISTS (SELECT 1 FROM case_judges cj
                   WHERE cj.case_id = NEW.case_id AND cj.judge_id = NEW.judge_id
                     AND NEW.hearing_date >= cj.assignment_date
                     AND (cj.end_date IS NULL OR NEW.hearing_date <= cj.end_date)) THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'hearing judge must be assigned to the case on the hearing date';
    END IF;
    IF NEW.status <> 'Cancelled' AND NOT (
            NEW.case_id <=> OLD.case_id AND NEW.judge_id <=> OLD.judge_id AND NEW.hearing_date <=> OLD.hearing_date
        AND NEW.start_time <=> OLD.start_time AND NEW.end_time <=> OLD.end_time
        AND NEW.courtroom <=> OLD.courtroom AND NEW.status <=> OLD.status) THEN
        CALL sp_check_hearing_slot(NEW.hearing_id, NEW.case_id, NEW.judge_id, NEW.hearing_date, NEW.start_time, NEW.end_time, NEW.courtroom);
    END IF;
END$$

-- ---------------- evidence: every item gets an intake custody record automatically ----------------
CREATE TRIGGER trg_evidence_intake AFTER INSERT ON evidence
FOR EACH ROW
BEGIN
    INSERT INTO chain_of_custody (evidence_id, from_user_id, to_user_id, transfer_date, transfer_reason, location)
    VALUES (NEW.evidence_id, NULL, NEW.submitted_by_user_id, NEW.submission_date, 'Intake', 'With submitter');
END$$

-- ---------------- document versions: old file saved automatically, history append-only ----------------
CREATE TRIGGER trg_documents_keep_old AFTER UPDATE ON documents
FOR EACH ROW
BEGIN
    IF NOT (NEW.file_reference <=> OLD.file_reference) THEN
        INSERT INTO document_versions (document_id, version_number, file_reference, uploaded_by_user_id, uploaded_at)
        VALUES (OLD.document_id, OLD.version, OLD.file_reference, OLD.uploaded_by_user_id, OLD.uploaded_date);
    END IF;
END$$

CREATE TRIGGER trg_docver_no_update BEFORE UPDATE ON document_versions
FOR EACH ROW
BEGIN
    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'document_versions is append-only';
END$$

CREATE TRIGGER trg_docver_no_delete BEFORE DELETE ON document_versions
FOR EACH ROW
BEGIN
    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'document_versions is append-only';
END$$

-- ---------------- inactive users / courts / witnesses can't be used in NEW records ----------------
CREATE TRIGGER trg_documents_active BEFORE INSERT ON documents
FOR EACH ROW
BEGIN
    CALL sp_require_active_case(NEW.case_id);
    CALL sp_require_active_user(NEW.uploaded_by_user_id);
END$$

CREATE TRIGGER trg_evidence_active BEFORE INSERT ON evidence
FOR EACH ROW
BEGIN
    CALL sp_require_active_case(NEW.case_id);
    CALL sp_require_active_user(NEW.submitted_by_user_id);
END$$

CREATE TRIGGER trg_deadlines_active_ins BEFORE INSERT ON deadlines
FOR EACH ROW
BEGIN
    CALL sp_require_active_case(NEW.case_id);
    CALL sp_require_active_user(NEW.responsible_user_id);
END$$

CREATE TRIGGER trg_deadlines_active_upd BEFORE UPDATE ON deadlines
FOR EACH ROW
BEGIN
    IF NOT (NEW.responsible_user_id <=> OLD.responsible_user_id) THEN
        CALL sp_require_active_user(NEW.responsible_user_id);
    END IF;
END$$

CREATE TRIGGER trg_notes_active BEFORE INSERT ON case_notes
FOR EACH ROW
BEGIN
    CALL sp_require_active_case(NEW.case_id);
    CALL sp_require_active_user(NEW.user_id);
END$$

-- a note stays with its case and its author
CREATE TRIGGER trg_notes_lock BEFORE UPDATE ON case_notes
FOR EACH ROW
BEGIN
    IF NOT (NEW.case_id <=> OLD.case_id AND NEW.user_id <=> OLD.user_id) THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'case_notes.case_id / user_id cannot be changed';
    END IF;
END$$

CREATE TRIGGER trg_cases_court_active BEFORE INSERT ON legal_cases
FOR EACH ROW
BEGIN
    IF NOT EXISTS (SELECT 1 FROM courts WHERE court_id = NEW.court_id AND is_active = 1) THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'court is inactive';
    END IF;
END$$

CREATE TRIGGER trg_case_wit_active BEFORE INSERT ON case_witnesses
FOR EACH ROW
BEGIN
    CALL sp_require_active_case(NEW.case_id);
    IF NOT EXISTS (SELECT 1 FROM witnesses WHERE witness_id = NEW.witness_id AND is_active = 1) THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'witness is inactive';
    END IF;
END$$

-- evidence_witnesses: the witness must be registered on the evidence's case
CREATE TRIGGER trg_ev_wit_ins BEFORE INSERT ON evidence_witnesses
FOR EACH ROW
BEGIN
    IF NOT EXISTS (SELECT 1 FROM evidence e JOIN case_witnesses cw ON cw.case_id = e.case_id
                   WHERE e.evidence_id = NEW.evidence_id AND cw.witness_id = NEW.witness_id) THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'witness must be registered on the same case as the evidence (case_witnesses)';
    END IF;
END$$

CREATE TRIGGER trg_ev_wit_upd BEFORE UPDATE ON evidence_witnesses
FOR EACH ROW
BEGIN
    IF NOT EXISTS (SELECT 1 FROM evidence e JOIN case_witnesses cw ON cw.case_id = e.case_id
                   WHERE e.evidence_id = NEW.evidence_id AND cw.witness_id = NEW.witness_id) THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'witness must be registered on the same case as the evidence (case_witnesses)';
    END IF;
END$$

-- case_witnesses: can't remove/move a witness who is still linked to evidence in that case
CREATE TRIGGER trg_case_wit_upd BEFORE UPDATE ON case_witnesses
FOR EACH ROW
BEGIN
    IF NOT (NEW.case_id <=> OLD.case_id AND NEW.witness_id <=> OLD.witness_id) THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'case_id / witness_id cannot be changed: add a new row instead';
    END IF;
END$$

CREATE TRIGGER trg_case_wit_del BEFORE DELETE ON case_witnesses
FOR EACH ROW
BEGIN
    IF EXISTS (SELECT 1 FROM evidence_witnesses ew JOIN evidence e ON e.evidence_id = ew.evidence_id
               WHERE e.case_id = OLD.case_id AND ew.witness_id = OLD.witness_id) THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'witness is linked to evidence in this case: remove evidence_witnesses rows first';
    END IF;
END$$

DELIMITER ;
