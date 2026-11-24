-- =====================================================================
--  Legal Case Management System  —  sample_data.sql   (file 4 of 7)
--  Run once, on a fresh database, after triggers.sql.
--  Every insert passes the trigger rules, so this file also shows the
--  correct ORDER in which an application must create records:
--    users -> courts -> judges/lawyers/parties/witnesses -> cases
--    -> assignments -> hearings/documents -> judgments -> deadlines
--    -> evidence (auto intake) -> custody transfers -> notes
--  password_hash values are placeholders, not real hashes.
-- =====================================================================

USE legal_case_db;

-- ---------------------------------------------------------------------
-- 1. system_users (13)  — user 13 is an inactive (former) account
-- ---------------------------------------------------------------------
INSERT INTO system_users (user_id, username, password_hash, full_name, email, user_role, organization, is_active) VALUES
 (1,  'admin',          '$2b$12$sampleHashAdmin000000000000000000000000000000000000', 'Rohit Bhalla',          'admin@lcms.in',          'Admin',     'LCMS IT Cell',            1),
 (2,  'registrar.pta',  '$2b$12$sampleHashRegistrar00000000000000000000000000000000', 'Manpreet Kaur',         'registrar.pta@lcms.in',  'Registrar', 'District Court Patiala',  1),
 (3,  'clerk.simran',   '$2b$12$sampleHashClerk1000000000000000000000000000000000000', 'Simran Kaur',           'simran.k@lcms.in',       'Clerk',     'District Court Patiala',  1),
 (4,  'clerk.aman',     '$2b$12$sampleHashClerk2000000000000000000000000000000000000', 'Aman Verma',            'aman.v@lcms.in',         'Clerk',     'District Court Patiala',  1),
 (5,  'j.mehta',        '$2b$12$sampleHashJudge1000000000000000000000000000000000000', 'Anil Mehta',            'anil.mehta@lcms.in',     'Judge',     'District Court Patiala',  1),
 (6,  'j.sandhu',       '$2b$12$sampleHashJudge2000000000000000000000000000000000000', 'Harpreet Sandhu',       'h.sandhu@lcms.in',       'Judge',     'District Court Patiala',  1),
 (7,  'j.rao',          '$2b$12$sampleHashJudge3000000000000000000000000000000000000', 'Kavita Rao',            'kavita.rao@lcms.in',     'Judge',     'P&H High Court',          1),
 (8,  'adv.sharma',     '$2b$12$sampleHashLawyer100000000000000000000000000000000000', 'Rajesh Sharma',         'rajesh@sharmalaw.in',    'Lawyer',    'Sharma & Associates',     1),
 (9,  'adv.gill',       '$2b$12$sampleHashLawyer200000000000000000000000000000000000', 'Gurpreet Gill',         'gurpreet@gilllegal.in',  'Lawyer',    'Gill Legal',              1),
 (10, 'adv.khanna',     '$2b$12$sampleHashLawyer300000000000000000000000000000000000', 'Meera Khanna',          'meera@khannalaw.in',     'Lawyer',    'Khanna Law Chambers',     1),
 (11, 'lab.officer',    '$2b$12$sampleHashLab0000000000000000000000000000000000000000', 'Dr. Ritu Saini',        'ritu.saini@fsl.gov.in',  'Clerk',     'State Forensic Lab',      1),
 (12, 'viewer.audit',   '$2b$12$sampleHashViewer000000000000000000000000000000000000', 'Nitin Arora',           'audit@lcms.in',          'Viewer',    'Internal Audit',          1),
 (13, 'clerk.old',      '$2b$12$sampleHashOld0000000000000000000000000000000000000000', 'Deepak Kumar',          'deepak.k@lcms.in',       'Clerk',     'District Court Patiala',  0);

UPDATE system_users SET last_login_at = '2026-11-23 09:15:00' WHERE user_id IN (3, 4, 8);
UPDATE system_users SET last_login_at = '2026-11-22 18:40:00' WHERE user_id IN (5, 9, 10);

-- ---------------------------------------------------------------------
-- 2. courts (3)
-- ---------------------------------------------------------------------
INSERT INTO courts (court_id, court_name, location, court_type, address, phone, email) VALUES
 (1, 'District & Sessions Court',        'Patiala',    'District Court', 'Judicial Complex, Lower Mall, Patiala 147001',  '0175-2212345', 'dsj.patiala@punjab.gov.in'),
 (2, 'High Court of Punjab and Haryana', 'Chandigarh', 'High Court',     'Sector 1, Chandigarh 160001',                   '0172-2740000', 'phhc@nic.in'),
 (3, 'District Court',                   'Ludhiana',   'District Court', 'Judicial Complex, Ferozepur Road, Ludhiana',    '0161-2401234', 'dc.ludhiana@punjab.gov.in');

-- ---------------------------------------------------------------------
-- 3. judges (5)  — logins only for those who use the system
-- ---------------------------------------------------------------------
INSERT INTO judges (judge_id, name, specialization, phone, email, court_id, user_id) VALUES
 (1, 'Justice Anil Mehta',      'Civil',          '98140-11111', 'anil.mehta@lcms.in', 1, 5),
 (2, 'Justice Harpreet Sandhu', 'Criminal',       '98140-22222', 'h.sandhu@lcms.in',   1, 6),
 (3, 'Justice Kavita Rao',      'Constitutional', '98140-33333', 'kavita.rao@lcms.in', 2, 7),
 (4, 'Justice Suresh Bansal',   'Corporate',      '98140-44444', NULL,                 2, NULL),
 (5, 'Justice Neha Arora',      'Family',         '98140-55555', NULL,                 3, NULL);

-- ---------------------------------------------------------------------
-- 4. lawyers (6)
-- ---------------------------------------------------------------------
INSERT INTO lawyers (lawyer_id, registration_number, name, specialization, phone, email, address, user_id) VALUES
 (1, 'P/1234/2008', 'Adv. Rajesh Sharma',  'Civil & Property',  '98760-10001', 'rajesh@sharmalaw.in',   'Chamber 12, Lawyers Complex, Patiala', 8),
 (2, 'P/2210/2012', 'Adv. Gurpreet Gill',  'Civil',             '98760-10002', 'gurpreet@gilllegal.in', 'Chamber 31, Lawyers Complex, Patiala', 9),
 (3, 'P/3105/2015', 'Adv. Meera Khanna',   'Criminal Defence',  '98760-10003', 'meera@khannalaw.in',    'SCO 22, Leela Bhawan, Patiala',        10),
 (4, 'P/0987/2005', 'Adv. Vikram Singh',   'Public Prosecutor', '98760-10004', 'vikram.pp@punjab.gov.in','Office of DA, Patiala',               NULL),
 (5, 'P/4420/2018', 'Adv. Pooja Malhotra', 'Family',            '98760-10005', 'pooja@malhotralaw.in',  'Civil Lines, Ludhiana',                NULL),
 (6, 'P/5012/2020', 'Adv. Arjun Bedi',     'Family',            '98760-10006', 'arjun@bedilaw.in',      'Model Town, Ludhiana',                 NULL);

-- ---------------------------------------------------------------------
-- 5. parties (8)
-- ---------------------------------------------------------------------
INSERT INTO parties (party_id, name, party_type, phone, email, address, organization_name) VALUES
 (1, 'Ramesh Kumar',           'Individual',   '94170-20001', 'ramesh.k@gmail.com',   'H.No. 45, Urban Estate Ph-2, Patiala', NULL),
 (2, 'Sunita Devi',            'Individual',   '94170-20002', NULL,                   'Village Bahadurgarh, Patiala',         NULL),
 (3, 'State of Punjab',        'Government',   '0172-2740100', NULL,                  'Civil Secretariat, Chandigarh',        'Government of Punjab'),
 (4, 'Karan Malhotra',         'Individual',   '94170-20004', 'karan.m@gmail.com',    'Tripuri Town, Patiala',                NULL),
 (5, 'Priya Sharma',           'Individual',   '94170-20005', 'priya.s@gmail.com',    'Sarabha Nagar, Ludhiana',              NULL),
 (6, 'Vikas Sharma',           'Individual',   '94170-20006', NULL,                   'BRS Nagar, Ludhiana',                  NULL),
 (7, 'GreenLeaf Agro Pvt Ltd', 'Organization', '0172-5001234', 'legal@greenleaf.in',  'Industrial Area Ph-1, Chandigarh',     'GreenLeaf Agro Pvt Ltd'),
 (8, 'Harjit Singh',           'Individual',   '94170-20008', NULL,                   'Model Town, Ludhiana',                 NULL);

-- ---------------------------------------------------------------------
-- 6. witnesses (6)
-- ---------------------------------------------------------------------
INSERT INTO witnesses (witness_id, name, phone, email, address, is_expert) VALUES
 (1, 'Mohan Lal',            '94630-30001', NULL,                    'Urban Estate Ph-2, Patiala',      0),
 (2, 'Dr. Anjali Verma',     '94630-30002', 'anjali.v@fsl.gov.in',   'State Forensic Lab, Mohali',      1),
 (3, 'Insp. Baldev Singh',   '94630-30003', 'baldev.s@punjabpolice.gov.in', 'PS Civil Lines, Patiala', 0),
 (4, 'Neeraj Gupta',         '94630-30004', NULL,                    'Leela Bhawan, Patiala',           0),
 (5, 'Dr. Sameer Joshi',     '94630-30005', 'sameer.joshi@qde.in',   'Handwriting Bureau, Chandigarh',  1),
 (6, 'Kamla Devi',           '94630-30006', NULL,                    'Sarabha Nagar, Ludhiana',         0);

-- ---------------------------------------------------------------------
-- 7. legal_cases (7)  — case 7 reuses case 1's number in another court (allowed)
-- ---------------------------------------------------------------------
INSERT INTO legal_cases (case_id, case_number, case_type, filing_date, status, priority, description, court_id) VALUES
 (1, 'CS/101/2026',   'Civil',          '2026-01-15', 'Under Trial', 'High',   'Suit for recovery of possession of agricultural land (4 kanal)',     1),
 (2, 'CR/45/2026',    'Criminal',       '2026-02-20', 'Under Trial', 'Urgent', 'Online banking fraud of Rs 8.4 lakh (FIR 112/2026)',               1),
 (3, 'FAM/12/2026',   'Family',         '2026-03-10', 'Pending',     'Medium', 'Petition for maintenance under Sec 125 CrPC',                      3),
 (4, 'CWP/2201/2026', 'Constitutional', '2026-04-05', 'Pending',     'High',   'Writ against cancellation of land allotment',                      2),
 (5, 'CS/88/2025',    'Civil',          '2025-06-01', 'Under Trial', 'Low',    'Boundary dispute between adjoining plot owners',                   1),
 (6, 'CORP/7/2026',   'Corporate',      '2026-06-15', 'Filed',       'Medium', 'Petition for recovery of unpaid supply invoices',                  2),
 (7, 'CS/101/2026',   'Civil',          '2026-07-01', 'Filed',       'Medium', 'Suit for specific performance of agreement to sell',              3);

-- ---------------------------------------------------------------------
-- 8. case_judges  — judge always from the case's own court
--    case 2 shows a transfer: Justice Mehta presided for 4 days, then Justice Sandhu
--    case 1 has a Substitute; case 4 is a two-judge bench
-- ---------------------------------------------------------------------
INSERT INTO case_judges (case_id, judge_id, assignment_date, end_date, assignment_role) VALUES
 (5, 1, '2025-06-05', '2026-09-30', 'Presiding'),
 (1, 1, '2026-01-20', NULL,         'Presiding'),
 (2, 1, '2026-02-21', '2026-02-24', 'Presiding'),
 (2, 2, '2026-02-25', NULL,         'Presiding'),
 (3, 5, '2026-03-15', NULL,         'Presiding'),
 (4, 3, '2026-04-10', NULL,         'Presiding'),
 (4, 4, '2026-04-10', NULL,         'Associate'),
 (6, 3, '2026-06-20', NULL,         'Presiding'),
 (7, 5, '2026-07-05', NULL,         'Presiding'),
 (1, 2, '2026-11-01', NULL,         'Substitute');

-- ---------------------------------------------------------------------
-- 9. case_parties
-- ---------------------------------------------------------------------
INSERT INTO case_parties (case_id, party_id, party_role, start_date, end_date) VALUES
 (1, 1, 'Plaintiff',   '2026-01-15', NULL),
 (1, 2, 'Defendant',   '2026-01-15', NULL),
 (2, 3, 'Complainant', '2026-02-20', NULL),
 (2, 4, 'Accused',     '2026-02-20', NULL),
 (3, 5, 'Petitioner',  '2026-03-10', NULL),
 (3, 6, 'Respondent',  '2026-03-10', NULL),
 (4, 7, 'Petitioner',  '2026-04-05', NULL),
 (4, 3, 'Respondent',  '2026-04-05', NULL),
 (5, 1, 'Plaintiff',   '2025-06-01', '2026-09-30'),
 (5, 8, 'Defendant',   '2025-06-01', '2026-09-30'),
 (6, 7, 'Petitioner',  '2026-06-15', NULL),
 (6, 2, 'Respondent',  '2026-06-15', NULL),
 (7, 8, 'Plaintiff',   '2026-07-01', NULL),
 (7, 5, 'Defendant',   '2026-07-01', NULL);

-- ---------------------------------------------------------------------
-- 10. case_lawyers
-- ---------------------------------------------------------------------
INSERT INTO case_lawyers (case_id, lawyer_id, representation_type, start_date, end_date) VALUES
 (1, 1, 'Counsel for Petitioner', '2026-01-15', NULL),
 (1, 2, 'Counsel for Respondent', '2026-01-25', NULL),
 (2, 4, 'Public Prosecutor',      '2026-02-20', NULL),
 (2, 3, 'Defence Counsel',        '2026-02-22', NULL),
 (3, 5, 'Counsel for Petitioner', '2026-03-10', NULL),
 (3, 6, 'Counsel for Respondent', '2026-03-20', NULL),
 (4, 1, 'Counsel for Petitioner', '2026-04-05', NULL),
 (4, 4, 'Counsel for Respondent', '2026-04-12', NULL),
 (5, 2, 'Counsel for Petitioner', '2025-06-01', '2026-09-30'),
 (5, 3, 'Counsel for Respondent', '2025-06-10', '2026-09-30'),
 (6, 3, 'Counsel for Petitioner', '2026-06-15', NULL),
 (7, 5, 'Counsel for Petitioner', '2026-07-01', NULL);

-- ---------------------------------------------------------------------
-- 11. case_witnesses  (statement details are per case)
-- ---------------------------------------------------------------------
INSERT INTO case_witnesses (case_id, witness_id, witness_role, statement_date, statement_reference, status, notes) VALUES
 (1, 1, 'Defence',     '2026-05-12', 'Examination-in-chief, CS/101/2026', 'Examined',       'Neighbour; confirms possession since 2010'),
 (1, 5, 'Court',       NULL,         NULL,                                'Summoned',       'Handwriting expert on disputed signature'),
 (2, 3, 'Prosecution', '2026-02-21', 'Statement u/s 161 CrPC, FIR 112',   'Examined',       'Investigating officer'),
 (2, 2, 'Prosecution', '2026-07-14', 'FSL report no. FSL/DG/2026/331',    'Cross-Examined', 'Forensic expert on phone extraction'),
 (2, 4, 'Defence',     NULL,         NULL,                                'Listed',         NULL),
 (3, 6, 'Court',       '2026-04-20', 'Statement before Family Court',     'Examined',       NULL),
 (5, 1, 'Court',       '2025-08-12', 'Local commissioner report',         'Discharged',     NULL);

-- ---------------------------------------------------------------------
-- 12. hearings  — judge assigned on that date, no double-booking
-- ---------------------------------------------------------------------
INSERT INTO hearings (case_id, judge_id, hearing_date, start_time, end_time, hearing_type, purpose, outcome, status, courtroom, notes) VALUES
 (5, 1, '2025-08-12', '10:00', '11:30', 'Evidence',    'Plaintiff evidence',               'Local commissioner appointed',  'Completed', 'Court Room 3', NULL),
 (1, 1, '2026-02-10', '10:00', '11:00', 'Preliminary', 'Framing of issues',                'Issues framed',                 'Completed', 'Court Room 3', NULL),
 (2, 2, '2026-03-05', '10:00', '10:45', 'Bail',        'Bail application of accused',      'Bail granted',                  'Completed', 'Court Room 1', NULL),
 (3, 5, '2026-04-20', '11:00', '12:00', 'Preliminary', 'Interim maintenance',              'Interim maintenance Rs 8,000/month', 'Completed', 'Court Room 2', NULL),
 (4, 3, '2026-05-05', '14:00', '14:30', 'Preliminary', 'Notice of motion',                 'Notice issued to State',        'Completed', 'Court Hall 1', NULL),
 (1, 1, '2026-05-12', '10:00', '11:30', 'Evidence',    'Plaintiff witnesses',              'PW-1 examined',                 'Completed', 'Court Room 3', NULL),
 (2, 2, '2026-07-14', '12:00', '13:00', 'Evidence',    'Prosecution evidence',             'FSL expert cross-examined',     'Completed', 'Court Room 1', NULL),
 (1, 1, '2026-08-18', '11:00', '12:00', 'Evidence',    'Defendant witnesses',              'Adjourned: witness absent',     'Adjourned', 'Court Room 3', 'Costs of Rs 2,000 imposed'),
 (5, 1, '2026-09-15', '10:00', '11:00', 'Final',       'Final arguments',                  'Judgment reserved',             'Completed', 'Court Room 3', NULL),
 (2, 2, '2026-10-20', '12:00', '13:00', 'Evidence',    'Defence evidence',                 NULL,                            'Cancelled', 'Court Room 1', 'Court holiday declared'),
 (2, 2, '2026-12-03', '12:00', NULL,    'Evidence',    'Defence evidence',                 NULL,                            'Scheduled', 'Court Room 1', NULL),
 (1, 1, '2026-12-08', '10:00', NULL,    'Arguments',   'Arguments on interim injunction',  NULL,                            'Scheduled', 'Court Room 3', NULL),
 (6, 3, '2026-12-10', '14:00', '14:30', 'Preliminary', 'Admission of petition',            NULL,                            'Scheduled', 'Court Hall 2', NULL),
 (3, 5, '2026-12-15', '11:00', NULL,    'Final',       'Final arguments',                  NULL,                            'Scheduled', 'Court Room 2', NULL),
 (4, 3, '2027-01-12', '14:00', NULL,    'Arguments',   'Final hearing',                    NULL,                            'Scheduled', 'Court Hall 1', NULL),
 (1, 2, '2027-01-19', '10:00', NULL,    'Arguments',   'Final arguments (substitute judge)', NULL,                          'Scheduled', 'Court Room 4', NULL),
 (7, 5, '2027-02-02', '10:00', NULL,    'Preliminary', 'Appearance of defendant',          NULL,                            'Scheduled', 'Court Room 2', NULL);

-- ---------------------------------------------------------------------
-- 13. documents
-- ---------------------------------------------------------------------
INSERT INTO documents (document_id, case_id, uploaded_by_user_id, document_type, title, uploaded_date, file_reference, status) VALUES
 (1,  1, 8,  'Petition',       'Plaint — recovery of possession',     '2026-01-15 10:30:00', 'docs/CS-101-2026/plaint_v1.pdf',          'Filed'),
 (2,  1, 8,  'Affidavit',      'Affidavit of plaintiff',              '2026-01-15 10:35:00', 'docs/CS-101-2026/affidavit.pdf',          'Accepted'),
 (3,  1, 3,  'Notice',         'Summons to defendant',                '2026-01-22 12:00:00', 'docs/CS-101-2026/summons.pdf',            'Filed'),
 (4,  1, 9,  'Evidence',       'Certified copy of sale deed',         '2026-02-05 11:20:00', 'docs/CS-101-2026/sale_deed.pdf',          'Filed'),
 (5,  2, 3,  'Other',          'Copy of FIR No. 112/2026',            '2026-02-20 16:00:00', 'docs/CR-45-2026/fir_112.pdf',             'Accepted'),
 (6,  2, 2,  'Order',          'Bail order',                          '2026-03-05 15:30:00', 'docs/CR-45-2026/bail_order.pdf',          'Filed'),
 (7,  2, 4,  'Evidence',       'Bank account statements',             '2026-03-03 11:00:00', 'docs/CR-45-2026/bank_statements.pdf',     'Filed'),
 (8,  3, 4,  'Petition',       'Petition for maintenance',            '2026-03-10 10:00:00', 'docs/FAM-12-2026/petition.pdf',           'Filed'),
 (9,  4, 8,  'Petition',       'Writ petition',                       '2026-04-05 10:15:00', 'docs/CWP-2201-2026/writ.pdf',             'Filed'),
 (10, 5, 2,  'Judgment',       'Final judgment and decree',           '2026-09-30 17:00:00', 'docs/CS-88-2025/judgment_signed.pdf',     'Filed'),
 (11, 6, 10, 'Petition',       'Company petition (draft)',            '2026-06-15 09:45:00', 'docs/CORP-7-2026/petition_v1.docx',       'Draft'),
 (12, 1, 8,  'Correspondence', 'Letter to client re: next hearing',   '2026-11-10 18:20:00', 'docs/CS-101-2026/client_letter.pdf',      'Filed');

-- new files for two documents: version goes to 2 and the old file is kept in document_versions
UPDATE documents SET file_reference = 'docs/CS-101-2026/plaint_v2_amended.pdf' WHERE document_id = 1;
UPDATE documents SET file_reference = 'docs/CORP-7-2026/petition_v2.docx'       WHERE document_id = 11;

-- ---------------------------------------------------------------------
-- 14. judgments
-- ---------------------------------------------------------------------
INSERT INTO judgments (judgment_id, case_id, judge_id, document_id, judgment_type, judgment_date, decision, penalties, status, notes) VALUES
 (1, 2, 2, 6,    'Order',   '2026-03-05', 'Bail granted on furnishing personal bond of Rs 50,000 with one surety', NULL, 'Pronounced', 'Accused to appear on every date'),
 (2, 5, 1, 10,   'Decree',  '2026-09-30', 'Suit decreed; boundary fixed as per local commissioner report',         'Costs of Rs 15,000 to plaintiff', 'Pronounced', NULL),
 (3, 1, 1, NULL, 'Interim', '2026-11-20', 'Interim injunction restraining transfer of the suit land (draft)',     NULL, 'Draft', 'To be pronounced on next date');

-- defendant appealed the decree in case 5
UPDATE judgments SET status = 'Appealed', notes = 'RSA filed in High Court on 2026-10-25' WHERE judgment_id = 2;

-- ---------------------------------------------------------------------
-- 15. deadlines
-- ---------------------------------------------------------------------
INSERT INTO deadlines (case_id, deadline_type, due_date, responsible_user_id, status, reminder_date, completed_at, description) VALUES
 (1, 'Filing',       '2026-03-15 17:00:00', 9,  'Completed', '2026-03-12 09:00:00', '2026-03-10 16:30:00', 'Written statement of defendant'),
 (1, 'Hearing Prep', '2026-12-05 17:00:00', 8,  'Pending',   '2026-12-02 09:00:00', NULL,                  'Prepare arguments on interim injunction'),
 (2, 'Response',     '2026-11-30 17:00:00', 10, 'Pending',   '2026-11-27 09:00:00', NULL,                  'Reply to prosecution application'),
 (3, 'Filing',       '2026-11-10 17:00:00', 4,  'Missed',    NULL,                  NULL,                  'Respondent income affidavit'),
 (4, 'Compliance',   '2027-01-05 17:00:00', 8,  'Pending',   '2026-12-29 09:00:00', NULL,                  'File rejoinder to State reply'),
 (5, 'Appeal',       '2026-10-30 17:00:00', 9,  'Completed', '2026-10-20 09:00:00', '2026-10-25 12:00:00', 'Regular second appeal'),
 (6, 'Filing',       '2026-12-20 17:00:00', 10, 'Extended',  '2026-12-15 09:00:00', NULL,                  'Statement of accounts');

-- ---------------------------------------------------------------------
-- 16. evidence  — each insert automatically creates the intake custody record
-- ---------------------------------------------------------------------
INSERT INTO evidence (evidence_id, case_id, submitted_by_user_id, evidence_type, description, submission_date, status, integrity_hash, is_sensitive) VALUES
 (1, 2, 3, 'Digital',     'Mobile phone data extraction on sealed pen drive', '2026-03-02 10:00:00', 'Admitted',     SHA2('CR-45-2026/pen-drive/IMEI-356789104512345', 256), 1),
 (2, 2, 4, 'Documentary', 'Bank account statements (certified copies)',       '2026-03-03 11:00:00', 'Admitted',     SHA2('CR-45-2026/bank-statements', 256),                0),
 (3, 1, 3, 'Documentary', 'Original registered sale deed no. 4521',           '2026-02-05 11:00:00', 'Under Review', SHA2('CS-101-2026/sale-deed-4521', 256),                0),
 (4, 5, 4, 'Physical',    'Boundary survey map signed by local commissioner', '2025-07-01 12:00:00', 'Admitted',     SHA2('CS-88-2025/survey-map', 256),                     0);

-- ---------------------------------------------------------------------
-- 17. chain_of_custody transfers  (from = current holder, in date order)
-- ---------------------------------------------------------------------
INSERT INTO chain_of_custody (evidence_id, from_user_id, to_user_id, transfer_date, transfer_reason, location, remarks) VALUES
 (1, 3, 4,  '2026-03-02 15:00:00', 'Deposit in evidence room',    'Evidence room (Malkhana), Locker 12',   'Seal intact'),
 (1, 4, 11, '2026-03-10 11:00:00', 'Forensic examination',        'State Forensic Science Lab, Mohali',    'Sent with docket FSL/331'),
 (1, 11, 4, '2026-04-20 16:00:00', 'Returned after examination',  'Evidence room (Malkhana), Locker 12',   'Re-sealed by FSL'),
 (3, 3, 2,  '2026-02-06 10:00:00', 'Safe custody of original',    'Court record room, Almirah 4',          NULL),
 (4, 4, 2,  '2025-07-02 10:00:00', 'Safe custody',                'Court record room, Almirah 2',          NULL);

-- ---------------------------------------------------------------------
-- 18. evidence_witnesses  (witness must be registered on the same case)
-- ---------------------------------------------------------------------
INSERT INTO evidence_witnesses (evidence_id, witness_id, relationship_type, notes) VALUES
 (1, 3, 'Collected',  'Seized phone from accused'),
 (1, 2, 'Examined',   'Prepared FSL report'),
 (3, 5, 'Examined',   'Compared signatures on sale deed');

-- ---------------------------------------------------------------------
-- 19. case_notes  (private notes are shown only to their author by the app)
-- ---------------------------------------------------------------------
INSERT INTO case_notes (case_id, user_id, note_title, note_content, is_private) VALUES
 (1, 8,  'Client meeting 10 Nov',   'Client confirms tenant vacated in 2019; collect electricity bills as proof.', 1),
 (1, 9,  'Defence strategy',        'Rely on 2010 family settlement; summon patwari with jamabandi records.',      1),
 (2, 10, 'Bail conditions',         'Accused must not leave Punjab; remind client before every date.',             1),
 (4, 8,  'Hearing summary 05 May',  'Notice issued; State to file reply in 4 weeks.',                              0);

-- ---------------------------------------------------------------------
-- 20. close the disposed case (it stays active, so an appeal can still add records)
-- ---------------------------------------------------------------------
CALL sp_close_case(5, 'Disposed', '2026-09-30');
