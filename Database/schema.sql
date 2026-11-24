-- =====================================================================
--  Legal Case Management System  —  schema.sql   (file 1 of 7)
--  MySQL 8.0.16 or newer
--
--  Creates the database and all 20 tables with their keys and constraints.
--  Run order:  schema.sql -> procedures.sql -> triggers.sql -> sample_data.sql
--              -> views.sql -> queries.sql -> transactions.sql
--
--  Design summary (matches the ER diagram):
--   * 20 tables, 32 foreign-key relationships (R1–R32 on the diagram)
--   * every FK: ON DELETE RESTRICT ON UPDATE CASCADE (legal records are never cascade-deleted)
--   * soft delete with is_active on master tables, cases, documents and evidence
--   * created_at / updated_at on every table (append-only tables: created_at only)
--   * fixed value lists are ENUMs; yes/no columns are CHECKed to 0/1
--   * business rules (CRUD rules, assignment history, custody chain, judgment locking,
--     hearing double-booking, inactive records) are enforced by triggers.sql
--
--  First-time install only: this script never drops data. If the tables already exist,
--  CREATE TABLE fails instead of erasing records. Apply later changes as ALTER TABLE scripts.
--  To rebuild from scratch on a test machine:  DROP DATABASE legal_case_db;  then run again.
-- =====================================================================

CREATE DATABASE IF NOT EXISTS legal_case_db CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
USE legal_case_db;

-- ---------------------------------------------------------------------
-- MASTER TABLES
-- ---------------------------------------------------------------------

CREATE TABLE system_users (
    user_id        INT AUTO_INCREMENT PRIMARY KEY,
    username       VARCHAR(100) NOT NULL,
    password_hash  VARCHAR(255) NOT NULL,
    full_name      VARCHAR(150) NOT NULL,
    email          VARCHAR(150) NOT NULL,
    user_role      ENUM('Admin','Judge','Lawyer','Clerk','Registrar','Viewer') NOT NULL DEFAULT 'Viewer',
    organization   VARCHAR(150),
    last_login_at  DATETIME NULL,
    is_active      TINYINT(1) NOT NULL DEFAULT 1 CHECK (is_active IN (0,1)),
    created_at     TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at     TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    CONSTRAINT uq_users_username UNIQUE (username),
    CONSTRAINT uq_users_email    UNIQUE (email)
) ENGINE=InnoDB;

CREATE TABLE courts (
    court_id     INT AUTO_INCREMENT PRIMARY KEY,
    court_name   VARCHAR(150) NOT NULL,
    location     VARCHAR(150) NOT NULL,
    court_type   ENUM('Supreme Court','High Court','District Court','Sessions Court','Tribunal','Other') NOT NULL,
    address      TEXT,
    phone        VARCHAR(20),
    email        VARCHAR(150),
    is_active    TINYINT(1) NOT NULL DEFAULT 1 CHECK (is_active IN (0,1)),
    created_at   TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at   TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    CONSTRAINT uq_courts_name_location UNIQUE (court_name, location)
) ENGINE=InnoDB;

CREATE TABLE judges (
    judge_id        INT AUTO_INCREMENT PRIMARY KEY,
    name            VARCHAR(150) NOT NULL,
    specialization  VARCHAR(150),
    phone           VARCHAR(20),
    email           VARCHAR(150),
    court_id        INT NOT NULL,
    user_id         INT NULL,
    is_active       TINYINT(1) NOT NULL DEFAULT 1 CHECK (is_active IN (0,1)),
    created_at      TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at      TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    CONSTRAINT uq_judges_user UNIQUE (user_id),
    CONSTRAINT fk_judges_court FOREIGN KEY (court_id) REFERENCES courts(court_id)
        ON DELETE RESTRICT ON UPDATE CASCADE,
    CONSTRAINT fk_judges_user  FOREIGN KEY (user_id)  REFERENCES system_users(user_id)
        ON DELETE RESTRICT ON UPDATE CASCADE
) ENGINE=InnoDB;

CREATE TABLE lawyers (
    lawyer_id            INT AUTO_INCREMENT PRIMARY KEY,
    registration_number  VARCHAR(100) NOT NULL,
    name                 VARCHAR(150) NOT NULL,
    specialization       VARCHAR(150),
    phone                VARCHAR(20),
    email                VARCHAR(150),
    address              TEXT,
    user_id              INT NULL,
    is_active            TINYINT(1) NOT NULL DEFAULT 1 CHECK (is_active IN (0,1)),
    created_at           TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at           TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    CONSTRAINT uq_lawyers_regno UNIQUE (registration_number),
    CONSTRAINT uq_lawyers_user  UNIQUE (user_id),
    CONSTRAINT fk_lawyers_user FOREIGN KEY (user_id) REFERENCES system_users(user_id)
        ON DELETE RESTRICT ON UPDATE CASCADE
) ENGINE=InnoDB;

CREATE TABLE parties (
    party_id           INT AUTO_INCREMENT PRIMARY KEY,
    name               VARCHAR(150) NOT NULL,
    party_type         ENUM('Individual','Organization','Government') NOT NULL,
    phone              VARCHAR(20),
    email              VARCHAR(150),
    address            TEXT,
    organization_name  VARCHAR(150),
    is_active          TINYINT(1) NOT NULL DEFAULT 1 CHECK (is_active IN (0,1)),
    created_at         TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at         TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP
) ENGINE=InnoDB;

CREATE TABLE witnesses (
    witness_id  INT AUTO_INCREMENT PRIMARY KEY,
    name        VARCHAR(150) NOT NULL,
    phone       VARCHAR(20),
    email       VARCHAR(150),
    address     TEXT,
    is_expert   TINYINT(1) NOT NULL DEFAULT 0 CHECK (is_expert IN (0,1)),
    is_active   TINYINT(1) NOT NULL DEFAULT 1 CHECK (is_active IN (0,1)),
    created_at  TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at  TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP
) ENGINE=InnoDB;

-- ---------------------------------------------------------------------
-- CORE: LEGAL CASES
-- ---------------------------------------------------------------------

CREATE TABLE legal_cases (
    case_id      INT AUTO_INCREMENT PRIMARY KEY,
    case_number  VARCHAR(50) NOT NULL,
    case_type    ENUM('Civil','Criminal','Family','Corporate','Constitutional','Labour','Tax','Other') NOT NULL,
    filing_date  DATE NOT NULL,
    status       ENUM('Filed','Pending','Under Trial','Disposed','Closed','Dismissed','Withdrawn') NOT NULL DEFAULT 'Filed',
    priority     ENUM('Low','Medium','High','Urgent') NOT NULL DEFAULT 'Medium',
    description  TEXT,
    court_id     INT NOT NULL,
    closed_date  DATE NULL,                          -- set when the case is closed/disposed
    is_active    TINYINT(1) NOT NULL DEFAULT 1 CHECK (is_active IN (0,1)),
    created_at   TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at   TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    CONSTRAINT uq_cases_number UNIQUE (court_id, case_number),   -- same number may exist in another court
    CONSTRAINT chk_cases_closed CHECK (closed_date IS NULL OR closed_date >= filing_date),
    CONSTRAINT fk_cases_court FOREIGN KEY (court_id) REFERENCES courts(court_id)
        ON DELETE RESTRICT ON UPDATE CASCADE
) ENGINE=InnoDB;

-- ---------------------------------------------------------------------
-- LINK TABLES (case <-> judge / party / lawyer / witness)
-- ---------------------------------------------------------------------

CREATE TABLE case_judges (
    case_judge_id    INT AUTO_INCREMENT PRIMARY KEY,
    case_id          INT NOT NULL,
    judge_id         INT NOT NULL,
    assignment_date  DATE NOT NULL,
    end_date         DATE NULL,
    assignment_role  ENUM('Presiding','Associate','Bench Member','Substitute') NOT NULL DEFAULT 'Presiding',
    created_at       TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at       TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    INDEX idx_cj_period (case_id, judge_id, assignment_date, end_date),
    CONSTRAINT chk_case_judges_dates CHECK (end_date IS NULL OR end_date >= assignment_date),
    CONSTRAINT fk_cj_case  FOREIGN KEY (case_id)  REFERENCES legal_cases(case_id)
        ON DELETE RESTRICT ON UPDATE CASCADE,
    CONSTRAINT fk_cj_judge FOREIGN KEY (judge_id) REFERENCES judges(judge_id)
        ON DELETE RESTRICT ON UPDATE CASCADE
) ENGINE=InnoDB;

CREATE TABLE case_parties (
    case_party_id  INT AUTO_INCREMENT PRIMARY KEY,
    case_id        INT NOT NULL,
    party_id       INT NOT NULL,
    party_role     ENUM('Petitioner','Respondent','Plaintiff','Defendant','Appellant','Complainant','Accused','Intervenor') NOT NULL,
    start_date     DATE NOT NULL,
    end_date       DATE NULL,
    created_at     TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at     TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    INDEX idx_cp_period (case_id, party_id, party_role, start_date, end_date),
    CONSTRAINT chk_case_parties_dates CHECK (end_date IS NULL OR end_date >= start_date),
    CONSTRAINT fk_cp_case  FOREIGN KEY (case_id)  REFERENCES legal_cases(case_id)
        ON DELETE RESTRICT ON UPDATE CASCADE,
    CONSTRAINT fk_cp_party FOREIGN KEY (party_id) REFERENCES parties(party_id)
        ON DELETE RESTRICT ON UPDATE CASCADE
) ENGINE=InnoDB;

CREATE TABLE case_lawyers (
    case_lawyer_id       INT AUTO_INCREMENT PRIMARY KEY,
    case_id              INT NOT NULL,
    lawyer_id            INT NOT NULL,
    representation_type  ENUM('Counsel for Petitioner','Counsel for Respondent','Public Prosecutor','Defence Counsel','Amicus Curiae','Legal Aid') NOT NULL,
    start_date           DATE NOT NULL,
    end_date             DATE NULL,
    created_at           TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at           TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    INDEX idx_cl_period (case_id, lawyer_id, start_date, end_date),
    CONSTRAINT chk_case_lawyers_dates CHECK (end_date IS NULL OR end_date >= start_date),
    CONSTRAINT fk_cl_case   FOREIGN KEY (case_id)   REFERENCES legal_cases(case_id)
        ON DELETE RESTRICT ON UPDATE CASCADE,
    CONSTRAINT fk_cl_lawyer FOREIGN KEY (lawyer_id) REFERENCES lawyers(lawyer_id)
        ON DELETE RESTRICT ON UPDATE CASCADE
) ENGINE=InnoDB;

CREATE TABLE case_witnesses (
    case_witness_id      INT AUTO_INCREMENT PRIMARY KEY,
    case_id              INT NOT NULL,
    witness_id           INT NOT NULL,
    witness_role         ENUM('Prosecution','Defence','Court') NOT NULL,   -- expert status lives in witnesses.is_expert
    statement_date       DATE NULL,
    statement_reference  VARCHAR(255) NULL,          -- a statement belongs to one case
    status               ENUM('Listed','Summoned','Examined','Cross-Examined','Discharged','Hostile') NOT NULL DEFAULT 'Listed',
    notes                TEXT,
    created_at           TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at           TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    CONSTRAINT uq_case_witness UNIQUE (case_id, witness_id),
    CONSTRAINT fk_cw_case    FOREIGN KEY (case_id)    REFERENCES legal_cases(case_id)
        ON DELETE RESTRICT ON UPDATE CASCADE,
    CONSTRAINT fk_cw_witness FOREIGN KEY (witness_id) REFERENCES witnesses(witness_id)
        ON DELETE RESTRICT ON UPDATE CASCADE
) ENGINE=InnoDB;

-- ---------------------------------------------------------------------
-- HEARINGS, DOCUMENTS, JUDGMENTS, DEADLINES
-- ---------------------------------------------------------------------

CREATE TABLE hearings (
    hearing_id    INT AUTO_INCREMENT PRIMARY KEY,
    case_id       INT NOT NULL,
    judge_id      INT NOT NULL,
    hearing_date  DATE NOT NULL,
    start_time    TIME NOT NULL,
    end_time      TIME NULL,
    hearing_type  ENUM('Preliminary','Evidence','Arguments','Interim','Final','Bail','Other') NOT NULL,
    purpose       TEXT,
    outcome       TEXT,
    status        ENUM('Scheduled','Completed','Adjourned','Cancelled') NOT NULL DEFAULT 'Scheduled',
    courtroom     VARCHAR(100),
    notes         TEXT,
    -- next hearing per case: see view v_case_next_hearing
    created_at    TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at    TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    CONSTRAINT chk_hearing_times CHECK (end_time IS NULL OR end_time > start_time),
    CONSTRAINT fk_hearings_case  FOREIGN KEY (case_id)  REFERENCES legal_cases(case_id)
        ON DELETE RESTRICT ON UPDATE CASCADE,
    CONSTRAINT fk_hearings_judge FOREIGN KEY (judge_id) REFERENCES judges(judge_id)
        ON DELETE RESTRICT ON UPDATE CASCADE,
    INDEX idx_hearings_case_date (case_id, hearing_date),
    INDEX idx_hearings_judge_slot (judge_id, hearing_date, start_time),
    INDEX idx_hearings_room_slot (hearing_date, courtroom, start_time)
) ENGINE=InnoDB;

CREATE TABLE documents (
    document_id          INT AUTO_INCREMENT PRIMARY KEY,
    case_id              INT NOT NULL,
    uploaded_by_user_id  INT NOT NULL,
    document_type        ENUM('Petition','Affidavit','Order','Judgment','Evidence','Notice','Correspondence','Other') NOT NULL,
    title                VARCHAR(255) NOT NULL,
    uploaded_date        DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    file_reference       VARCHAR(500) NOT NULL,
    version              INT NOT NULL DEFAULT 1,
    status               ENUM('Draft','Filed','Accepted','Rejected','Archived') NOT NULL DEFAULT 'Filed',
    is_active            TINYINT(1) NOT NULL DEFAULT 1 CHECK (is_active IN (0,1)),
    created_at           TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at           TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    CONSTRAINT chk_documents_version CHECK (version >= 1),
    CONSTRAINT fk_documents_case FOREIGN KEY (case_id) REFERENCES legal_cases(case_id)
        ON DELETE RESTRICT ON UPDATE CASCADE,
    CONSTRAINT fk_documents_user FOREIGN KEY (uploaded_by_user_id) REFERENCES system_users(user_id)
        ON DELETE RESTRICT ON UPDATE CASCADE
) ENGINE=InnoDB;

-- previous files of a document (filled automatically when file_reference changes; append-only)
CREATE TABLE document_versions (
    version_id           INT AUTO_INCREMENT PRIMARY KEY,
    document_id          INT NOT NULL,
    version_number       INT NOT NULL,
    file_reference       VARCHAR(500) NOT NULL,
    uploaded_by_user_id  INT NOT NULL,
    uploaded_at          DATETIME NOT NULL,
    created_at           TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT uq_docver UNIQUE (document_id, version_number),
    CONSTRAINT fk_docver_document FOREIGN KEY (document_id) REFERENCES documents(document_id)
        ON DELETE RESTRICT ON UPDATE CASCADE,
    CONSTRAINT fk_docver_user FOREIGN KEY (uploaded_by_user_id) REFERENCES system_users(user_id)
        ON DELETE RESTRICT ON UPDATE CASCADE
) ENGINE=InnoDB;

CREATE TABLE judgments (
    judgment_id    INT AUTO_INCREMENT PRIMARY KEY,
    case_id        INT NOT NULL,
    judge_id       INT NOT NULL,                     -- judge who delivered it
    document_id    INT NULL,
    judgment_type  ENUM('Interim','Final','Order','Decree') NOT NULL,
    judgment_date  DATE NOT NULL,
    decision       TEXT NOT NULL,
    penalties      TEXT,
    status         ENUM('Draft','Pronounced','Appealed','Overturned','Voided') NOT NULL DEFAULT 'Draft',
    notes          TEXT,
    created_at     TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at     TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    CONSTRAINT uq_judgments_document UNIQUE (document_id),   -- one signed copy per judgment
    CONSTRAINT fk_judgments_case     FOREIGN KEY (case_id)     REFERENCES legal_cases(case_id)
        ON DELETE RESTRICT ON UPDATE CASCADE,
    CONSTRAINT fk_judgments_judge    FOREIGN KEY (judge_id)    REFERENCES judges(judge_id)
        ON DELETE RESTRICT ON UPDATE CASCADE,
    CONSTRAINT fk_judgments_document FOREIGN KEY (document_id) REFERENCES documents(document_id)
        ON DELETE RESTRICT ON UPDATE CASCADE
) ENGINE=InnoDB;

CREATE TABLE deadlines (
    deadline_id          INT AUTO_INCREMENT PRIMARY KEY,
    case_id              INT NOT NULL,
    deadline_type        ENUM('Filing','Response','Hearing Prep','Appeal','Compliance','Other') NOT NULL,
    due_date             DATETIME NOT NULL,
    responsible_user_id  INT NOT NULL,
    status               ENUM('Pending','Completed','Missed','Extended') NOT NULL DEFAULT 'Pending',
    reminder_date        DATETIME NULL,
    completed_at         DATETIME NULL,
    description          TEXT,
    created_at           TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at           TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    INDEX idx_deadlines_status_due (status, due_date),
    CONSTRAINT chk_deadlines_reminder  CHECK (reminder_date IS NULL OR reminder_date <= due_date),
    CONSTRAINT chk_deadlines_completed CHECK ((status = 'Completed') = (completed_at IS NOT NULL)),
    CONSTRAINT fk_deadlines_case FOREIGN KEY (case_id) REFERENCES legal_cases(case_id)
        ON DELETE RESTRICT ON UPDATE CASCADE,
    CONSTRAINT fk_deadlines_user FOREIGN KEY (responsible_user_id) REFERENCES system_users(user_id)
        ON DELETE RESTRICT ON UPDATE CASCADE
) ENGINE=InnoDB;

-- internal working notes on a case (not court documents; the app shows private notes only to their author)
CREATE TABLE case_notes (
    note_id       INT AUTO_INCREMENT PRIMARY KEY,
    case_id       INT NOT NULL,
    user_id       INT NOT NULL,
    note_title    VARCHAR(200) NOT NULL,
    note_content  TEXT NOT NULL,
    is_private    TINYINT(1) NOT NULL DEFAULT 1 CHECK (is_private IN (0,1)),
    created_at    TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at    TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    CONSTRAINT fk_notes_case FOREIGN KEY (case_id) REFERENCES legal_cases(case_id)
        ON DELETE RESTRICT ON UPDATE CASCADE,
    CONSTRAINT fk_notes_user FOREIGN KEY (user_id) REFERENCES system_users(user_id)
        ON DELETE RESTRICT ON UPDATE CASCADE
) ENGINE=InnoDB;

-- ---------------------------------------------------------------------
-- EVIDENCE, CHAIN OF CUSTODY, EVIDENCE <-> WITNESS
-- ---------------------------------------------------------------------

CREATE TABLE evidence (
    evidence_id            INT AUTO_INCREMENT PRIMARY KEY,
    case_id                INT NOT NULL,
    submitted_by_user_id   INT NOT NULL,
    evidence_type          ENUM('Documentary','Physical','Digital','Forensic','Testimonial','Other') NOT NULL,
    description            TEXT,
    submission_date        DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    status                 ENUM('Submitted','Under Review','Admitted','Rejected','Returned','Disposed') NOT NULL DEFAULT 'Submitted',
    -- current location: see view v_evidence_current_location (from chain_of_custody)
    integrity_hash         CHAR(64) NOT NULL CHECK (integrity_hash REGEXP '^[0-9a-fA-F]{64}$'),  -- SHA-256 hex
    is_sensitive           TINYINT(1) NOT NULL DEFAULT 0 CHECK (is_sensitive IN (0,1)),
    is_active              TINYINT(1) NOT NULL DEFAULT 1 CHECK (is_active IN (0,1)),
    created_at             TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at             TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    CONSTRAINT fk_evidence_case FOREIGN KEY (case_id) REFERENCES legal_cases(case_id)
        ON DELETE RESTRICT ON UPDATE CASCADE,
    CONSTRAINT fk_evidence_user FOREIGN KEY (submitted_by_user_id) REFERENCES system_users(user_id)
        ON DELETE RESTRICT ON UPDATE CASCADE
) ENGINE=InnoDB;

CREATE TABLE chain_of_custody (
    custody_id       INT AUTO_INCREMENT PRIMARY KEY,
    evidence_id      INT NOT NULL,
    from_user_id     INT NULL,                        -- NULL for the first (intake) entry
    to_user_id       INT NOT NULL,
    transfer_date    DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    transfer_reason  VARCHAR(255) NOT NULL,
    location         VARCHAR(255) NOT NULL,
    remarks          TEXT,
    created_at       TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,   -- no updated_at: rows are append-only
    CONSTRAINT fk_coc_evidence FOREIGN KEY (evidence_id)  REFERENCES evidence(evidence_id)
        ON DELETE RESTRICT ON UPDATE CASCADE,
    CONSTRAINT fk_coc_from     FOREIGN KEY (from_user_id) REFERENCES system_users(user_id)
        ON DELETE RESTRICT ON UPDATE CASCADE,
    CONSTRAINT fk_coc_to       FOREIGN KEY (to_user_id)   REFERENCES system_users(user_id)
        ON DELETE RESTRICT ON UPDATE CASCADE,
    INDEX idx_coc_evidence_date (evidence_id, transfer_date)
) ENGINE=InnoDB;

CREATE TABLE evidence_witnesses (
    evidence_witness_id  INT AUTO_INCREMENT PRIMARY KEY,
    evidence_id          INT NOT NULL,
    witness_id           INT NOT NULL,
    relationship_type    ENUM('Identified','Collected','Examined','Testified About','Other') NOT NULL,
    notes                TEXT,
    created_at           TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at           TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    CONSTRAINT uq_evidence_witness UNIQUE (evidence_id, witness_id),
    CONSTRAINT fk_ew_evidence FOREIGN KEY (evidence_id) REFERENCES evidence(evidence_id)
        ON DELETE RESTRICT ON UPDATE CASCADE,
    CONSTRAINT fk_ew_witness  FOREIGN KEY (witness_id)  REFERENCES witnesses(witness_id)
        ON DELETE RESTRICT ON UPDATE CASCADE
) ENGINE=InnoDB;
