-- ============================================
-- NEED-BASED GOVERNMENT RESPONSE SYSTEM
-- CLEANED PostgreSQL SCHEMA (City Health focus)
-- Created: 2025-11-17
-- ============================================

-- 0) DROP existing tables in safe order (CASCADE to remove dependent objects)
DROP TABLE IF EXISTS notifications CASCADE;
DROP TABLE IF EXISTS appointments CASCADE;
DROP TABLE IF EXISTS professionals CASCADE;
DROP TABLE IF EXISTS audit_logs CASCADE;
DROP TABLE IF EXISTS requests CASCADE;
DROP TABLE IF EXISTS staff CASCADE;
DROP TABLE IF EXISTS citizens CASCADE;

-- ============================================
-- 1) CITIZENS TABLE
-- ============================================
CREATE TABLE citizens (
    citizen_id SERIAL PRIMARY KEY,
    email VARCHAR(255) UNIQUE NOT NULL,
    password_hash VARCHAR(255) NOT NULL,
    full_name VARCHAR(255) NOT NULL,
    phone VARCHAR(50),
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    is_active BOOLEAN DEFAULT TRUE
);

-- ============================================
-- 2) STAFF TABLE (Government Staff & Admins)
-- ============================================
CREATE TABLE staff (
    staff_id VARCHAR(50) PRIMARY KEY,
    full_name VARCHAR(255) NOT NULL,
    email VARCHAR(255) UNIQUE NOT NULL,
    password_hash VARCHAR(255),
    phone VARCHAR(50),
    official_id VARCHAR(50) UNIQUE,
    department VARCHAR(100) NOT NULL,
    role VARCHAR(50) NOT NULL CHECK (role IN ('admin', 'officer')),
    employee_id VARCHAR(50) UNIQUE,
    status VARCHAR(50) DEFAULT 'active' CHECK (status IN ('active', 'inactive')),
    joined_date TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    last_login TIMESTAMP,
    requests_handled INTEGER DEFAULT 0,
    permissions JSONB,
    added_by VARCHAR(255),
    added_date TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    deactivated_date TIMESTAMP
);

-- ============================================
-- 3) PROFESSIONALS TABLE (All service professionals)
-- ============================================
CREATE TABLE professionals (
    professional_id VARCHAR(50) PRIMARY KEY,
    full_name VARCHAR(255) NOT NULL,
    email VARCHAR(255) UNIQUE NOT NULL,
    password_hash VARCHAR(255) NOT NULL,
    phone VARCHAR(50),
    profession_type VARCHAR(100) NOT NULL, -- e.g., 'medical-doctor', 'dentist', 'psychiatrist', 'nurse'
    specialization VARCHAR(150),             -- e.g., 'pediatrics', 'orthodontics'
    department VARCHAR(150),                 -- e.g., 'medical', 'dental', 'mental-health'
    license_number VARCHAR(50) UNIQUE,
    qualifications TEXT,
    years_of_experience INTEGER DEFAULT 0,
    status VARCHAR(50) DEFAULT 'active' CHECK (status IN ('active', 'inactive', 'on-leave')),
    availability_schedule JSONB, -- {"monday": ["09:00-12:00", "13:00-17:00"], ...}
    max_appointments_per_day INTEGER DEFAULT 8,
    joined_date TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    last_login TIMESTAMP,
    total_appointments INTEGER DEFAULT 0,
    rating DECIMAL(3,2) DEFAULT 0.00,
    added_by VARCHAR(255),
    added_date TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- ============================================
-- 4) REQUESTS TABLE (City Health requests)
-- Single definitive definition — used by appointments and notifications
-- ============================================
CREATE TABLE requests (
    request_id VARCHAR(50) PRIMARY KEY,

    -- Citizen info (snapshot at time of request)
    citizen_name VARCHAR(255) NOT NULL,
    email VARCHAR(255) NOT NULL,
    phone VARCHAR(50),

    -- Location
    location_address TEXT,
    location_lat DECIMAL(10,8),
    location_lng DECIMAL(11,8),

    -- Type of need (consistent normalized values)
    need_type VARCHAR(50) NOT NULL CHECK (need_type IN (
        'medical',
        'sanitary-inspection',
        'dental-services',
        'immunization',
        'laboratory',
        'mental-health'
    )),

    severity VARCHAR(50) NOT NULL CHECK (severity IN ('critical','urgent','moderate','low')),
    people_affected INTEGER DEFAULT 1,

    description TEXT NOT NULL,

    -- Vulnerability flags, e.g. {"senior": true, "pwd": false}
    vulnerability_group JSONB,
    special_circumstances TEXT,

    -- Evidence (images/docs stored elsewhere, boolean flag)
    has_evidence BOOLEAN DEFAULT FALSE,

    -- Link to scheduled appointment (if any)
    appointment_id VARCHAR(50),

    -- Referral/status workflow for cases that need specialist referral (optional)
    referral_status VARCHAR(50) DEFAULT 'none'
        CHECK (referral_status IN ('none','scheduling','waiting_confirmation','confirmed','completed')),

    -- Processing status for the request
    status VARCHAR(50) DEFAULT 'pending'
        CHECK (status IN (
            'pending',
            'reviewing',
            'approved',
            'scheduling',
            'scheduled',
            'in-progress',
            'completed',
            'cancelled',
            'rejected'
        )),

    submitted_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    completed_at TIMESTAMP,

    verification_count INTEGER DEFAULT 0,
    priority_score INTEGER DEFAULT 0,
    estimated_response_time VARCHAR(100),

    -- Assignment
    assigned_to VARCHAR(100),
    assigned_staff_id VARCHAR(50),

    FOREIGN KEY (assigned_staff_id) REFERENCES staff(staff_id) ON DELETE SET NULL
);

-- Add foreign key for appointment link (requests.appointment_id -> appointments later)
-- This will be added after appointments table is created (see below).

-- ============================================
-- 5) APPOINTMENTS TABLE (Generalized across services)
-- References requests, professionals, staff
-- ============================================
CREATE TABLE appointments (
    appointment_id VARCHAR(50) PRIMARY KEY,
    request_id VARCHAR(50) NOT NULL,
    citizen_email VARCHAR(255) NOT NULL,
    citizen_name VARCHAR(255) NOT NULL,
    citizen_phone VARCHAR(50),
    professional_id VARCHAR(50),
    scheduled_by_staff_id VARCHAR(50),
    appointment_date DATE NOT NULL,
    appointment_time TIME NOT NULL,
    duration_minutes INTEGER DEFAULT 30,
    appointment_type VARCHAR(50) DEFAULT 'consultation' CHECK (appointment_type IN (
        'consultation',
        'medical-checkup',
        'dental-checkup',
        'treatment',
        'therapy',
        'counseling',
        'procedure',
        'follow-up',
        'emergency'
    )),
    notes TEXT,
    status VARCHAR(50) DEFAULT 'pending' CHECK (status IN (
        'pending','confirmed','completed','cancelled','no-show','rescheduled')),
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    confirmed_at TIMESTAMP,
    completed_at TIMESTAMP,
    cancellation_reason TEXT,

    FOREIGN KEY (request_id) REFERENCES requests(request_id) ON DELETE CASCADE,
    FOREIGN KEY (professional_id) REFERENCES professionals(professional_id) ON DELETE SET NULL,
    FOREIGN KEY (scheduled_by_staff_id) REFERENCES staff(staff_id) ON DELETE SET NULL
);

-- Now add FK from requests.appointment_id -> appointments
ALTER TABLE requests
    ADD CONSTRAINT fk_requests_appointment
    FOREIGN KEY (appointment_id) REFERENCES appointments(appointment_id) ON DELETE SET NULL;

-- ============================================
-- 6) NOTIFICATIONS TABLE
-- ============================================
CREATE TABLE notifications (
    notification_id SERIAL PRIMARY KEY,
    recipient_email VARCHAR(255) NOT NULL,
    recipient_type VARCHAR(50) NOT NULL CHECK (recipient_type IN ('citizen','staff','professional')),
    notification_type VARCHAR(50) NOT NULL CHECK (notification_type IN (
        'appointment_scheduled','appointment_confirmed','appointment_cancelled','request_update','system_alert'
    )),
    title VARCHAR(255) NOT NULL,
    message TEXT NOT NULL,
    related_request_id VARCHAR(50),
    related_appointment_id VARCHAR(50),
    is_read BOOLEAN DEFAULT FALSE,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    read_at TIMESTAMP,

    FOREIGN KEY (related_request_id) REFERENCES requests(request_id) ON DELETE CASCADE,
    FOREIGN KEY (related_appointment_id) REFERENCES appointments(appointment_id) ON DELETE CASCADE
);

-- ============================================
-- 7) AUDIT LOGS TABLE (System Activity)
-- ============================================
CREATE TABLE audit_logs (
    audit_id SERIAL PRIMARY KEY,
    audit_code VARCHAR(50) UNIQUE,
    timestamp TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    action_type VARCHAR(50) NOT NULL CHECK (action_type IN ('LOGIN','LOGOUT','CREATE','UPDATE','DELETE','STATUS_CHANGE','REGISTER','LOGIN_FAILED')),
    user_email VARCHAR(255) NOT NULL,
    user_role VARCHAR(50),
    entity_type VARCHAR(50),
    entity_id VARCHAR(50),
    details TEXT,
    ip_address VARCHAR(50)
);

-- ============================================
-- 8) TRIGGERS
-- Update requests.updated_at on any UPDATE
-- ============================================
CREATE OR REPLACE FUNCTION update_updated_at_column()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = CURRENT_TIMESTAMP;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS trg_requests_update_at ON requests;
CREATE TRIGGER trg_requests_update_at
BEFORE UPDATE ON requests
FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

-- ============================================
-- 9) INDEXES for Performance
-- ============================================
-- Citizens
CREATE INDEX IF NOT EXISTS idx_citizens_email ON citizens(email);
CREATE INDEX IF NOT EXISTS idx_citizens_active ON citizens(is_active);

-- Staff
CREATE INDEX IF NOT EXISTS idx_staff_email ON staff(email);
CREATE INDEX IF NOT EXISTS idx_staff_department ON staff(department);
CREATE INDEX IF NOT EXISTS idx_staff_role ON staff(role);
CREATE INDEX IF NOT EXISTS idx_staff_status ON staff(status);

-- Professionals
CREATE INDEX IF NOT EXISTS idx_professionals_email ON professionals(email);
CREATE INDEX IF NOT EXISTS idx_professionals_status ON professionals(status);
CREATE INDEX IF NOT EXISTS idx_professionals_profession_type ON professionals(profession_type);
CREATE INDEX IF NOT EXISTS idx_professionals_license ON professionals(license_number);

-- Requests
CREATE INDEX IF NOT EXISTS idx_requests_email ON requests(email);
CREATE INDEX IF NOT EXISTS idx_requests_status ON requests(status);
CREATE INDEX IF NOT EXISTS idx_requests_severity ON requests(severity);
CREATE INDEX IF NOT EXISTS idx_requests_priority ON requests(priority_score DESC);
CREATE INDEX IF NOT EXISTS idx_requests_submitted ON requests(submitted_at DESC);
CREATE INDEX IF NOT EXISTS idx_requests_assigned_staff ON requests(assigned_staff_id);
CREATE INDEX IF NOT EXISTS idx_requests_need_type ON requests(need_type);

-- Appointments
CREATE INDEX IF NOT EXISTS idx_appointments_request ON appointments(request_id);
CREATE INDEX IF NOT EXISTS idx_appointments_professional ON appointments(professional_id);
CREATE INDEX IF NOT EXISTS idx_appointments_citizen ON appointments(citizen_email);
CREATE INDEX IF NOT EXISTS idx_appointments_date ON appointments(appointment_date);
CREATE INDEX IF NOT EXISTS idx_appointments_status ON appointments(status);
CREATE INDEX IF NOT EXISTS idx_appointments_scheduled_by ON appointments(scheduled_by_staff_id);

-- Notifications
CREATE INDEX IF NOT EXISTS idx_notifications_recipient ON notifications(recipient_email);
CREATE INDEX IF NOT EXISTS idx_notifications_type ON notifications(notification_type);
CREATE INDEX IF NOT EXISTS idx_notifications_read ON notifications(is_read);
CREATE INDEX IF NOT EXISTS idx_notifications_created ON notifications(created_at DESC);
CREATE INDEX IF NOT EXISTS idx_notifications_request ON notifications(related_request_id);
CREATE INDEX IF NOT EXISTS idx_notifications_appointment ON notifications(related_appointment_id);

-- Audit logs
CREATE INDEX IF NOT EXISTS idx_audit_timestamp ON audit_logs(timestamp DESC);
CREATE INDEX IF NOT EXISTS idx_audit_user ON audit_logs(user_email);
CREATE INDEX IF NOT EXISTS idx_audit_action_type ON audit_logs(action_type);
CREATE INDEX IF NOT EXISTS idx_audit_entity ON audit_logs(entity_type, entity_id);

-- ============================================
-- 10) VIEWS (useful for dashboard)
-- ============================================
CREATE OR REPLACE VIEW pending_requests_by_priority AS
SELECT 
    request_id,
    citizen_name,
    email,
    phone,
    need_type,
    severity,
    priority_score,
    estimated_response_time,
    submitted_at
FROM requests
WHERE status = 'pending'
ORDER BY priority_score DESC, submitted_at ASC;

CREATE OR REPLACE VIEW staff_performance AS
SELECT 
    s.staff_id,
    s.full_name,
    s.email,
    s.department,
    s.role,
    s.status,
    s.requests_handled,
    COUNT(r.request_id) FILTER (WHERE r.status IS DISTINCT FROM 'completed') AS current_assigned_requests
FROM staff s
LEFT JOIN requests r ON s.staff_id = r.assigned_staff_id
GROUP BY s.staff_id, s.full_name, s.email, s.department, s.role, s.status, s.requests_handled
ORDER BY s.requests_handled DESC;

CREATE OR REPLACE VIEW dashboard_stats AS
SELECT 
    COUNT(*) FILTER (WHERE status = 'pending') AS pending_requests,
    COUNT(*) FILTER (WHERE status = 'in-progress') AS in_progress_requests,
    COUNT(*) FILTER (WHERE status = 'completed') AS completed_requests,
    COUNT(*) FILTER (WHERE severity = 'critical') AS critical_requests,
    COUNT(*) AS total_requests
FROM requests;

-- ============================================
-- 11) SAMPLE DATA (small seeds)
-- ============================================
-- Sample citizens (password hashes are example bcrypt strings)
INSERT INTO citizens (email, password_hash, full_name, phone)
VALUES
('john@example.com', '$2b$12$examplehashforpassword12345678abcdefg', 'John Doe', '+1-555-0001'),
('sarah@example.com', '$2b$12$examplehashforpassword12345678abcdefg', 'Sarah Smith', '+1-555-0002');

-- Sample staff
INSERT INTO staff (staff_id, full_name, email, password_hash, phone, official_id, department, role, employee_id, status, joined_date, requests_handled, permissions, added_by, added_date)
VALUES
('ADMIN-0001', 'John Administrator', 'john.administrator@gov.example.com', '$2b$12$examplehashforpassword', '+1-555-7716', 'GOV-10001', 'administration', 'admin', 'EMP-0001', 'active', '2020-01-01 08:00:00', 0, '{"viewRequests": true, "manageRequests": true}', 'system', CURRENT_TIMESTAMP);

-- Sample professionals (medical and dental)
INSERT INTO professionals (professional_id, full_name, email, password_hash, phone, profession_type, specialization, department, license_number, qualifications, years_of_experience, status)
VALUES
('PRO-0001', 'Dr. Alice Santos', 'alice.santos@cityhealth.gov', '$2b$12$examplehash', '+63-912-000001', 'medical-doctor', 'general-medicine', 'medical', 'LIC-1001', 'MD', 8, 'active'),
('PRO-0002', 'Dr. Ben Cruz', 'ben.cruz@cityhealth.gov', '$2b$12$examplehash', '+63-912-000002', 'dentist', 'general-dentistry', 'dental-services', 'LIC-2001', 'DDS', 5, 'active');

-- ============================================
-- 12) OPTIONAL: initialize referral_status default for existing rows (if any)
-- (safe no-op if column already has defaults)
UPDATE requests SET referral_status = 'none' WHERE referral_status IS NULL;

-- ============================================
-- 13) VERIFICATION SUMMARY
-- ============================================
SELECT 'Database created successfully!' AS status,
       (SELECT COUNT(*) FROM citizens) AS total_citizens,
       (SELECT COUNT(*) FROM staff) AS total_staff,
       (SELECT COUNT(*) FROM requests) AS total_requests,
       (SELECT COUNT(*) FROM professionals) AS total_professionals,
       (SELECT COUNT(*) FROM appointments) AS total_appointments,
       (SELECT COUNT(*) FROM notifications) AS total_notifications;
