-- ============================================
-- NEED-BASED GOVERNMENT RESPONSE SYSTEM
-- FULL PostgreSQL SCHEMA (City Health focus)
-- UPDATED: 2025-11-17
-- ============================================

-- 0) DROP existing tables in safe order
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
-- 3) PROFESSIONALS TABLE (Service professionals)
-- ============================================
CREATE TABLE professionals (
    professional_id VARCHAR(50) PRIMARY KEY,
    full_name VARCHAR(255) NOT NULL,
    email VARCHAR(255) UNIQUE NOT NULL,
    password_hash VARCHAR(255) NOT NULL,
    phone VARCHAR(50),
    profession_type VARCHAR(100) NOT NULL,
    specialization VARCHAR(150),
    department VARCHAR(150),
    official_id VARCHAR(50) UNIQUE,
    license_number VARCHAR(50) UNIQUE,
    qualifications TEXT,
    years_of_experience INTEGER DEFAULT 0,
    status VARCHAR(50) DEFAULT 'active' CHECK (status IN ('active', 'inactive', 'on-leave')),
    availability_schedule JSONB,
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
-- ============================================
CREATE TABLE requests (
    request_id VARCHAR(50) PRIMARY KEY,
    citizen_name VARCHAR(255) NOT NULL,
    email VARCHAR(255) NOT NULL,
    phone VARCHAR(50),
    location_address TEXT,
    location_lat DECIMAL(10,8),
    location_lng DECIMAL(11,8),
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
    vulnerability_group JSONB,
    special_circumstances TEXT,
    has_evidence BOOLEAN DEFAULT FALSE,
    appointment_id VARCHAR(50),
    referral_status VARCHAR(50) DEFAULT 'none'
        CHECK (referral_status IN ('none','scheduling','waiting_confirmation','confirmed','completed')),
    status VARCHAR(50) DEFAULT 'pending'
        CHECK (status IN (
            'pending','reviewing','approved','scheduling','scheduled',
            'in-progress','completed','cancelled','rejected'
        )),
    submitted_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    completed_at TIMESTAMP,
    verification_count INTEGER DEFAULT 0,
    priority_score INTEGER DEFAULT 0,
    estimated_response_time VARCHAR(100),
    assigned_to VARCHAR(100),
    assigned_staff_id VARCHAR(50),
    FOREIGN KEY (assigned_staff_id) REFERENCES staff(staff_id) ON DELETE SET NULL
);

-- ============================================
-- 5) APPOINTMENTS TABLE
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
        'consultation','medical-checkup','dental-checkup','treatment',
        'therapy','counseling','procedure','follow-up','emergency'
    )),
    notes TEXT,
    status VARCHAR(50) DEFAULT 'pending' CHECK (status IN (
        'pending','confirmed','completed','cancelled','no-show','rescheduled'
    )),
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    confirmed_at TIMESTAMP,
    completed_at TIMESTAMP,
    cancellation_reason TEXT,
    FOREIGN KEY (request_id) REFERENCES requests(request_id) ON DELETE CASCADE,
    FOREIGN KEY (professional_id) REFERENCES professionals(professional_id) ON DELETE SET NULL,
    FOREIGN KEY (scheduled_by_staff_id) REFERENCES staff(staff_id) ON DELETE SET NULL
);


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
-- 7) AUDIT LOGS TABLE
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
-- 8) TRIGGER FOR UPDATED_AT
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
-- 9) INDEXES
-- ============================================

-- Citizens
CREATE INDEX idx_citizens_email ON citizens(email);
CREATE INDEX idx_citizens_active ON citizens(is_active);

-- Staff
CREATE INDEX idx_staff_email ON staff(email);
CREATE INDEX idx_staff_department ON staff(department);
CREATE INDEX idx_staff_role ON staff(role);
CREATE INDEX idx_staff_status ON staff(status);

-- Professionals
CREATE INDEX idx_professionals_email ON professionals(email);
CREATE INDEX idx_professionals_status ON professionals(status);
CREATE INDEX idx_professionals_profession_type ON professionals(profession_type);
CREATE INDEX idx_professionals_license ON professionals(license_number);

-- Requests
CREATE INDEX idx_requests_email ON requests(email);
CREATE INDEX idx_requests_status ON requests(status);
CREATE INDEX idx_requests_severity ON requests(severity);
CREATE INDEX idx_requests_priority ON requests(priority_score);  -- FIXED (removed DESC)
CREATE INDEX idx_requests_submitted ON requests(submitted_at DESC);
CREATE INDEX idx_requests_assigned_staff ON requests(assigned_staff_id);
CREATE INDEX idx_requests_need_type ON requests(need_type);

-- Appointments
CREATE INDEX idx_appointments_request ON appointments(request_id);
CREATE INDEX idx_appointments_professional ON appointments(professional_id);
CREATE INDEX idx_appointments_citizen ON appointments(citizen_email);
CREATE INDEX idx_appointments_date ON appointments(appointment_date);
CREATE INDEX idx_appointments_status ON appointments(status);
CREATE INDEX idx_appointments_scheduled_by ON appointments(scheduled_by_staff_id);

-- Notifications
CREATE INDEX idx_notifications_recipient ON notifications(recipient_email);
CREATE INDEX idx_notifications_type ON notifications(notification_type);
CREATE INDEX idx_notifications_read ON notifications(is_read);
CREATE INDEX idx_notifications_created ON notifications(created_at DESC);
CREATE INDEX idx_notifications_request ON notifications(related_request_id);
CREATE INDEX idx_notifications_appointment ON notifications(related_appointment_id);

-- Audit logs
CREATE INDEX idx_audit_timestamp ON audit_logs(timestamp DESC);
CREATE INDEX idx_audit_user ON audit_logs(user_email);
CREATE INDEX idx_audit_action_type ON audit_logs(action_type);
CREATE INDEX idx_audit_entity ON audit_logs(entity_type, entity_id);

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
-- 11) SAMPLE DATA
-- ============================================

-- Citizens
INSERT INTO citizens (email, password_hash, full_name, phone) VALUES
('john@example.com', '$2b$12$examplehashforpassword12345678abcdefg', 'John Doe', '+1-555-0001'),
('sarah@example.com', '$2b$12$examplehashforpassword12345678abcdefg', 'Sarah Smith', '+1-555-0002');

-- Staff
INSERT INTO staff (staff_id, full_name, email, password_hash, phone, official_id, department, role, employee_id, status, joined_date, requests_handled, permissions, added_by, added_date)
VALUES
('ADMIN-0001', 'John Administrator', 'john.administrator@gov.example.com', '$2b$12$examplehashforpassword', '+1-555-7716', 'GOV-10001', 'administration', 'admin', 'EMP-0001', 'active', '2020-01-01 08:00:00', 0, '{"viewRequests": true, "manageRequests": true}', 'system', CURRENT_TIMESTAMP);

-- Professionals (5 types)
INSERT INTO professionals 
(professional_id, full_name, email, password_hash, phone, profession_type, official_id, specialization, department, license_number, qualifications, years_of_experience, status)
VALUES
('PRO-0001', 'Dr. Alice Santos', 'alice.santos@cityhealth.gov', '$2b$12$examplehash', '+63-912-000001',
 'medical-doctor', 'GOV-3001', 'General Medicine', 'medical', 'LIC-MED-001', 'MD, General Medicine', 10, 'active'),

('PRO-0002', 'Dr. Ben Cruz', 'ben.cruz@cityhealth.gov', '$2b$12$examplehash', '+63-912-000002',
 'dentist', 'GOV-3002', 'General Dentistry', 'dental-services', 'LIC-DEN-001', 'DDS', 7, 'active'),

('PRO-0004', 'Dr. Carla Reyes', 'carla.reyes@cityhealth.gov', '$2b$12$examplehash', '+63-912-000003',
 'immunization-doctor', 'GOV-3003', 'Immunization & Public Health', 'immunization', 'LIC-IMMU-001', 'MD, Public Health', 6, 'active'),

('PRO-0003', 'Dr. Maria Angela Cruz', 'maria.cruz@cityhealth.gov', '$2b$12$examplehash', '+63-912-000004',
 'mental-health-doctor', 'GOV-3004', 'Psychiatry & Mental Wellness', 'mental-health', 'LIC-MENT-001', 'MD, Psychiatry', 8, 'active'),

('PRO-0006', 'MedTech John Flores', 'john.flores@cityhealth.gov', '$2b$12$examplehash', '+63-912-000005',
 'medical-technologist', 'GOV-3005', 'Diagnostics & Lab Testing', 'laboratory', 'LIC-LAB-001', 'RMT, Laboratory Medicine', 5, 'active');

-- Requests
INSERT INTO requests
(request_id, citizen_name, email, phone, location_address, need_type, severity, people_affected, description, vulnerability_group, has_evidence, status, assigned_to, assigned_staff_id, appointment_id)
VALUES
('REQ-0001', 'John Doe', 'john@example.com', '+1-555-0001', '123 Main St, City', 'mental-health', 'urgent', 1, 
 'Feeling stressed and anxious, needs counseling.', '{"senior": false, "pwd": false}', TRUE, 'scheduling', 
 'Dr. Maria Angela Cruz', 'ADMIN-0001', 'APP-0001');

-- Appointments
INSERT INTO appointments
(appointment_id, request_id, citizen_email, citizen_name, citizen_phone, professional_id, scheduled_by_staff_id, appointment_date, appointment_time, duration_minutes, appointment_type, notes, status, created_at)
VALUES
('APP-0001', 'REQ-0001', 'john@example.com', 'John Doe', '+1-555-0001', 'PRO-0003', 'ADMIN-0001', 
 '2025-11-20', '10:00:00', 60, 'counseling', 'Initial mental health consultation', 'confirmed', CURRENT_TIMESTAMP);

-- Notification
INSERT INTO notifications
(recipient_email, recipient_type, notification_type, title, message, related_request_id, related_appointment_id, is_read, created_at)
VALUES
('john@example.com', 'citizen', 'appointment_scheduled', 'Your Counseling Appointment is Confirmed', 
'Hello John Doe, your counseling appointment with Dr. Maria Angela Cruz is confirmed for 2025-11-20 at 10:00 AM.', 
'REQ-0001', 'APP-0001', FALSE, CURRENT_TIMESTAMP);

UPDATE requests SET referral_status = 'none' WHERE referral_status IS NULL;

-- ============================================
-- 12) VERIFICATION QUERY
-- ============================================
SELECT 'Database created successfully!' AS status,
       (SELECT COUNT(*) FROM citizens) AS total_citizens,
       (SELECT COUNT(*) FROM staff) AS total_staff,
       (SELECT COUNT(*) FROM requests) AS total_requests,
       (SELECT COUNT(*) FROM professionals) AS total_professionals,
       (SELECT COUNT(*) FROM appointments) AS total_appointments,
       (SELECT COUNT(*) FROM notifications) AS total_notifications;

select * from staff;

-- Add specification column to requests table
ALTER TABLE requests 
ADD COLUMN IF NOT EXISTS specification VARCHAR(100);

-- Add index for better performance
CREATE INDEX IF NOT EXISTS idx_requests_specification ON requests(specification);
