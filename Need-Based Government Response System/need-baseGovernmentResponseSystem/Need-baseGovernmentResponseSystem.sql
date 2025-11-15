-- ============================================
-- NEED-BASED GOVERNMENT RESPONSE SYSTEM
-- PostgreSQL Database Schema
-- ============================================

-- Drop existing tables (if needed for fresh start)
DROP TABLE IF EXISTS audit_logs CASCADE;
DROP TABLE IF EXISTS requests CASCADE;
DROP TABLE IF EXISTS staff CASCADE;
DROP TABLE IF EXISTS citizens CASCADE;

-- ============================================
-- CITIZENS TABLE
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
-- STAFF TABLE (Government Staff & Admins)
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
-- REQUESTS TABLE (Relief/Assistance Requests)
-- ============================================
CREATE TABLE requests (
    request_id VARCHAR(50) PRIMARY KEY,
    citizen_name VARCHAR(255) NOT NULL,
    email VARCHAR(255) NOT NULL,
    phone VARCHAR(50),
    location_address TEXT,
    location_lat DECIMAL(10, 8),
    location_lng DECIMAL(11, 8),
    need_type VARCHAR(50) NOT NULL CHECK (need_type IN ('medical', 'Sanitary Inspection', 'Dental Services', 'Immunization', 'Laboratory and Diagnostic')),
    severity VARCHAR(50) NOT NULL CHECK (severity IN ('critical', 'urgent', 'moderate', 'low')),
    people_affected INTEGER DEFAULT 1,
    description TEXT NOT NULL,
    vulnerability_group JSONB,
    special_circumstances TEXT,
    is_student BOOLEAN DEFAULT FALSE,
    educational_needs JSONB,
    has_evidence BOOLEAN DEFAULT FALSE,
    status VARCHAR(50) DEFAULT 'pending' CHECK (status IN ('pending', 'in-progress', 'completed', 'rejected', 'cancelled')),
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
-- AUDIT LOGS TABLE (System Activity Tracking)
-- ============================================
CREATE TABLE audit_logs (
    audit_id SERIAL PRIMARY KEY,
    audit_code VARCHAR(50) UNIQUE,
    timestamp TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    action_type VARCHAR(50) NOT NULL CHECK (action_type IN ('LOGIN', 'LOGOUT', 'CREATE', 'UPDATE', 'DELETE', 'STATUS_CHANGE', 'REGISTER', 'LOGIN_FAILED')),
    user_email VARCHAR(255) NOT NULL,
    user_role VARCHAR(50),
    entity_type VARCHAR(50),
    entity_id VARCHAR(50),
    details TEXT,
    ip_address VARCHAR(50)
);

-- ============================================
-- INDEXES for Performance
-- ============================================

-- Citizens indexes
CREATE INDEX idx_citizens_email ON citizens(email);
CREATE INDEX idx_citizens_active ON citizens(is_active);

-- Staff indexes
CREATE INDEX idx_staff_email ON staff(email);
CREATE INDEX idx_staff_department ON staff(department);
CREATE INDEX idx_staff_role ON staff(role);
CREATE INDEX idx_staff_status ON staff(status);
CREATE INDEX idx_staff_official_id ON staff(official_id);

-- Requests indexes
CREATE INDEX idx_requests_email ON requests(email);
CREATE INDEX idx_requests_status ON requests(status);
CREATE INDEX idx_requests_severity ON requests(severity);
CREATE INDEX idx_requests_priority ON requests(priority_score DESC);
CREATE INDEX idx_requests_submitted ON requests(submitted_at DESC);
CREATE INDEX idx_requests_assigned_staff ON requests(assigned_staff_id);

-- Audit logs indexes
CREATE INDEX idx_audit_timestamp ON audit_logs(timestamp DESC);
CREATE INDEX idx_audit_user ON audit_logs(user_email);
CREATE INDEX idx_audit_action_type ON audit_logs(action_type);
CREATE INDEX idx_audit_entity ON audit_logs(entity_type, entity_id);

-- ============================================
-- SAMPLE DATA
-- ============================================

-- Insert sample citizens - password: "password123"
INSERT INTO citizens (email, password_hash, full_name, phone) VALUES
('john@example.com', '$2b$12$LQv3c1yqBWVHxkd0LHAkCOYz6TtxMQJqhN8/LewY5GyYNJL6BQMKG', 'John Doe', '+1-555-0001'),
('sarah@example.com', '$2b$12$LQv3c1yqBWVHxkd0LHAkCOYz6TtxMQJqhN8/LewY5GyYNJL6BQMKG', 'Sarah Smith', '+1-555-0002'),
('maria@example.com', '$2b$12$LQv3c1yqBWVHxkd0LHAkCOYz6TtxMQJqhN8/LewY5GyYNJL6BQMKG', 'Maria Garcia', '+1-555-0003');

-- Insert sample staff (including admin) - password: "password123"
INSERT INTO staff (staff_id, full_name, email, password_hash, phone, official_id, department, role, employee_id, status, joined_date, requests_handled, permissions, added_by, added_date) VALUES
('ADMIN-0001', 'John Administrator', 'john.administrator@gov.example.com', '$2b$12$LQv3c1yqBWVHxkd0LHAkCOYz6TtxMQJqhN8/LewY5GyYNJL6BQMKG', '+1-555-7716', 'GOV-10001', 'Administration', 'admin', 'GOV-10001', 'active', '2020-01-01 08:00:00', 0, '{"viewRequests": true, "manageRequests": true, "assignRequests": true, "viewAnalytics": true, "manageStaff": true, "viewAuditLogs": true, "systemSettings": true}', 'admin@gov.example.com', '2025-09-05 10:00:00');


-- ============================================
-- TRIGGERS
-- ============================================

-- Update requests.updated_at on any update
CREATE OR REPLACE FUNCTION update_updated_at_column()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = CURRENT_TIMESTAMP;
    RETURN NEW;
END;
$$ language 'plpgsql';

CREATE TRIGGER update_requests_updated_at BEFORE UPDATE ON requests
FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

-- ============================================
-- VIEWS
-- ============================================

-- View for pending requests sorted by priority
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

-- View for staff performance
CREATE OR REPLACE VIEW staff_performance AS
SELECT 
    s.staff_id,
    s.full_name,
    s.email,
    s.department,
    s.role,
    s.status,
    s.requests_handled,
    COUNT(r.request_id) AS current_assigned_requests
FROM staff s
LEFT JOIN requests r ON s.staff_id = r.assigned_staff_id AND r.status != 'completed'
GROUP BY s.staff_id, s.full_name, s.email, s.department, s.role, s.status, s.requests_handled
ORDER BY s.requests_handled DESC;

-- View for dashboard statistics
CREATE OR REPLACE VIEW dashboard_stats AS
SELECT 
    COUNT(*) FILTER (WHERE status = 'pending') AS pending_requests,
    COUNT(*) FILTER (WHERE status = 'in-progress') AS in_progress_requests,
    COUNT(*) FILTER (WHERE status = 'completed') AS completed_requests,
    COUNT(*) FILTER (WHERE severity = 'critical') AS critical_requests,
    COUNT(*) FILTER (WHERE is_student = TRUE) AS student_requests,
    COUNT(*) AS total_requests
FROM requests;

-- ============================================
-- MENTAL HEALTH WORKFLOW EXTENSION
-- Professional Users, Appointments, and Notifications
-- ============================================

-- ============================================
-- PROFESSIONALS TABLE (Mental Health Doctors/Counselors)
-- ============================================
CREATE TABLE professionals (
    professional_id VARCHAR(50) PRIMARY KEY,
    full_name VARCHAR(255) NOT NULL,
    email VARCHAR(255) UNIQUE NOT NULL,
    password_hash VARCHAR(255) NOT NULL,
    phone VARCHAR(50),
    license_number VARCHAR(50) UNIQUE,
    specialization VARCHAR(100) NOT NULL, -- e.g., 
    department VARCHAR(100) DEFAULT 'Mental Health Services',
    qualifications TEXT,
    years_of_experience INTEGER DEFAULT 0,
    status VARCHAR(50) DEFAULT 'active' CHECK (status IN ('active', 'inactive', 'on-leave')),
    availability_schedule JSONB, -- {"monday": ["9:00-12:00", "2:00-5:00"], "tuesday": [...]}
    max_appointments_per_day INTEGER DEFAULT 8,
    joined_date TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    last_login TIMESTAMP,
    total_appointments INTEGER DEFAULT 0,
    rating DECIMAL(3, 2) DEFAULT 0.00,
    added_by VARCHAR(255),
    added_date TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- ============================================
-- APPOINTMENTS TABLE (Mental Health Appointments)
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
    duration_minutes INTEGER DEFAULT 60,
    appointment_type VARCHAR(50) DEFAULT 'consultation' CHECK (appointment_type IN ('consultation', 'therapy', 'counseling', 'follow-up', 'emergency')),
    notes TEXT,
    status VARCHAR(50) DEFAULT 'pending' CHECK (status IN ('pending', 'confirmed', 'completed', 'cancelled', 'no-show')),
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    confirmed_at TIMESTAMP,
    completed_at TIMESTAMP,
    cancellation_reason TEXT,
    FOREIGN KEY (request_id) REFERENCES requests(request_id) ON DELETE CASCADE,
    FOREIGN KEY (professional_id) REFERENCES professionals(professional_id) ON DELETE SET NULL,
    FOREIGN KEY (scheduled_by_staff_id) REFERENCES staff(staff_id) ON DELETE SET NULL
);

-- ============================================
-- NOTIFICATIONS TABLE (System Notifications)
-- ============================================
CREATE TABLE notifications (
    notification_id SERIAL PRIMARY KEY,
    recipient_email VARCHAR(255) NOT NULL,
    recipient_type VARCHAR(50) NOT NULL CHECK (recipient_type IN ('citizen', 'staff', 'professional')),
    notification_type VARCHAR(50) NOT NULL CHECK (notification_type IN ('appointment_scheduled', 'appointment_confirmed', 'appointment_cancelled', 'request_update', 'system_alert')),
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
-- MENTAL HEALTH WORKFLOW INDEXES
-- ============================================

-- Professionals indexes
CREATE INDEX idx_professionals_email ON professionals(email);
CREATE INDEX idx_professionals_status ON professionals(status);
CREATE INDEX idx_professionals_specialization ON professionals(specialization);
CREATE INDEX idx_professionals_license ON professionals(license_number);

-- Appointments indexes
CREATE INDEX idx_appointments_request ON appointments(request_id);
CREATE INDEX idx_appointments_professional ON appointments(professional_id);
CREATE INDEX idx_appointments_citizen ON appointments(citizen_email);
CREATE INDEX idx_appointments_date ON appointments(appointment_date);
CREATE INDEX idx_appointments_status ON appointments(status);
CREATE INDEX idx_appointments_scheduled_by ON appointments(scheduled_by_staff_id);

-- Notifications indexes
CREATE INDEX idx_notifications_recipient ON notifications(recipient_email);
CREATE INDEX idx_notifications_type ON notifications(notification_type);
CREATE INDEX idx_notifications_read ON notifications(is_read);
CREATE INDEX idx_notifications_created ON notifications(created_at DESC);
CREATE INDEX idx_notifications_request ON notifications(related_request_id);
CREATE INDEX idx_notifications_appointment ON notifications(related_appointment_id);

-- ============================================
-- UPDATE REQUESTS TABLE FOR MENTAL HEALTH
-- ============================================

-- Add new columns to requests table for mental health workflow
ALTER TABLE requests ADD COLUMN IF NOT EXISTS appointment_id VARCHAR(50);
ALTER TABLE requests ADD COLUMN IF NOT EXISTS referral_status VARCHAR(50) CHECK (referral_status IN ('none', 'scheduling', 'waiting_confirmation', 'confirmed', 'completed'));
ALTER TABLE requests ADD CONSTRAINT fk_requests_appointment FOREIGN KEY (appointment_id) REFERENCES appointments(appointment_id) ON DELETE SET NULL;

-- Set default referral_status for existing records
UPDATE requests SET referral_status = 'none' WHERE referral_status IS NULL;

-- ============================================
-- SAMPLE MENTAL HEALTH PROFESSIONALS
-- ============================================

-- Insert sample mental health professionals - password: "password123"
INSERT INTO professionals (professional_id, full_name, email, password_hash, phone, license_number, specialization, qualifications, years_of_experience, status, availability_schedule, max_appointments_per_day, total_appointments, rating) VALUES
('GOV-0011', 'Dr. Emily Rodriguez', 'emily.rodriguez@mentalhealth.gov', '$2b$12$LQv3c1yqBWVHxkd0LHAkCOYz6TtxMQJqhN8/LewY5GyYNJL6BQMKG', '+1-555-1001', 'PSY-2023-1001', 'Clinical Psychologist', 'PhD in Clinical Psychology, Licensed Psychologist, Cognitive Behavioral Therapy (CBT) Specialist', 12, 'active', '{"monday": ["9:00-12:00", "2:00- 5:00"], "tuesday": ["9:00-12:00", "14:00-5:00"], "wednesday": ["9:00-12:00", "2:00-5:00"], "thursday": ["9:00-12:00", "14:00-17:00"], "friday": ["9:00-12:00"]}', 8, 0, 4.85),
('GOV-0012', 'Dr. Michael Chen', 'michael.chen@mentalhealth.gov', '$2b$12$EixZaYVK1fsbw1ZfbX3OXePaWxn96p36WQoeG6Lruj3vjPGga31lW', '+1-555-1002', 'PSY-2023-1002', 'Psychiatrist', 'MD Psychiatry, Board Certified, Anxiety & Depression Specialist', 15, 'active', '{"monday": ["10:00-1:00", "3:00-6:00"], "tuesday": ["10:00- 1:00", "3:00-6:00"], "wednesday": ["10:00-1:00"], "thursday": ["10:00-1:00", "3:00-6:00"], "friday": ["10:00-1:00", "3:00-6:00"]}', 10, 0, 4.92),

('GOV-0013', 'Sarah Thompson', 'sarah.thompson@mentalhealth.gov', '$2b$12$4Zo0.j7VKmXm5.N3tN5kBed/R2l3g0dVJYJKq4vQxqkPxkfU1QCZS', '+1-555-1003', 'COUN-2023-1003', 'Licensed Counselor', 'MA in Counseling Psychology, LMHC, Trauma & PTSD Specialist, Student Mental Health Expert', 8, 'active', '{"monday": ["8:00-12:00", "1:00-5:00"], "tuesday": ["8:00-12:00", "1:00-5:00"], "wednesday": ["8:00-12:00", "1:00-4:00"], "thursday": ["8:00-12:00", "1:00-5:00"], "friday": ["8:00-12:00"]}', 8, 0, 4.78),

('GOV-0014', 'Dr. James Wilson', 'james.wilson@mentalhealth.gov', '$2b$12$kA/LwGLx3mZvv8TqXELVEOl5j0yHXqZqGN0WbZ3Jh4wGvLMQqpPBO', '+1-555-1004', 'PSY-2023-1004', 'Child Psychologist', 'PsyD in Child Psychology, Play Therapy Certified, Adolescent Mental Health Specialist', 10, 'active', '{"monday": ["9:00-12:00", "2:00-5:00"], "tuesday": ["9:00-12:00", "2:00-5:00"], "thursday": ["9:00-12:00", "2:00-5:00"], "friday": ["9:00-12:00", "2:00-5:00"]}', 6, 0, 4.95);

-- ============================================
-- VERIFICATION
-- ============================================
SELECT 'Database created successfully!' as status,
       (SELECT COUNT(*) FROM citizens) as total_citizens,
       (SELECT COUNT(*) FROM staff) as total_staff,
       (SELECT COUNT(*) FROM requests) as total_requests,
       (SELECT COUNT(*) FROM professionals) as total_professionals,
       (SELECT COUNT(*) FROM appointments) as total_appointments,
       (SELECT COUNT(*) FROM notifications) as total_notifications;






-------kaning sa ubos kay maoy modify na pa
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




CREATE TABLE requests (
    request_id VARCHAR(50) PRIMARY KEY,
    citizen_name VARCHAR(255) NOT NULL,
    email VARCHAR(255) NOT NULL,
    phone VARCHAR(50),
    location_address TEXT,
    location_lat DECIMAL(10, 8),
    location_lng DECIMAL(11, 8),
    need_type VARCHAR(50) NOT NULL CHECK (need_type IN ('medical', 'Sanitary Inspection', 'Dental Services', 'Immunization', 'Laboratory and Diagnostic')),
    severity VARCHAR(50) NOT NULL CHECK (severity IN ('critical', 'urgent', 'moderate', 'low')),
    people_affected INTEGER DEFAULT 1,
    description TEXT NOT NULL,
    vulnerability_group JSONB,
    special_circumstances TEXT,
    is_student BOOLEAN DEFAULT FALSE,
    educational_needs JSONB,
    has_evidence BOOLEAN DEFAULT FALSE,
    status VARCHAR(50) DEFAULT 'pending' CHECK (status IN ('pending', 'in-progress', 'completed', 'rejected', 'cancelled')),
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

CREATE TABLE audit_logs (
    audit_id SERIAL PRIMARY KEY,
    audit_code VARCHAR(50) UNIQUE,
    timestamp TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    action_type VARCHAR(50) NOT NULL CHECK (action_type IN ('LOGIN', 'LOGOUT', 'CREATE', 'UPDATE', 'DELETE', 'STATUS_CHANGE', 'REGISTER', 'LOGIN_FAILED')),
    user_email VARCHAR(255) NOT NULL,
    user_role VARCHAR(50),
    entity_type VARCHAR(50),
    entity_id VARCHAR(50),
    details TEXT,
    ip_address VARCHAR(50)
);

-- Audit logs indexes
CREATE INDEX idx_audit_timestamp ON audit_logs(timestamp DESC);
CREATE INDEX idx_audit_user ON audit_logs(user_email);
CREATE INDEX idx_audit_action_type ON audit_logs(action_type);
CREATE INDEX idx_audit_entity ON audit_logs(entity_type, entity_id);

-- ============================================
-- PROFESSIONALS TABLE (Mental Health Doctors/Counselors)
-- ============================================
CREATE TABLE professionals (
    professional_id VARCHAR(50) PRIMARY KEY,
    full_name VARCHAR(255) NOT NULL,
    email VARCHAR(255) UNIQUE NOT NULL,
    password_hash VARCHAR(255) NOT NULL,
    phone VARCHAR(50),
    license_number VARCHAR(50) UNIQUE,
    specialization VARCHAR(100) NOT NULL, -- e.g., 'Clinical Psychologist', 'Psychiatrist', 'Counselor'
    department VARCHAR(100) DEFAULT 'Mental Health Services',
    qualifications TEXT,
    years_of_experience INTEGER DEFAULT 0,
    status VARCHAR(50) DEFAULT 'active' CHECK (status IN ('active', 'inactive', 'on-leave')),
    availability_schedule JSONB, -- {"monday": ["9:00-12:00", "2:00-5:00"], "tuesday": [...]}
    max_appointments_per_day INTEGER DEFAULT 8,
    joined_date TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    last_login TIMESTAMP,
    total_appointments INTEGER DEFAULT 0,
    rating DECIMAL(3, 2) DEFAULT 0.00,
    added_by VARCHAR(255),
    added_date TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- ============================================
-- APPOINTMENTS TABLE (Mental Health Appointments)
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
    duration_minutes INTEGER DEFAULT 60,
    appointment_type VARCHAR(50) DEFAULT 'consultation' CHECK (appointment_type IN ('consultation', 'therapy', 'counseling', 'follow-up', 'emergency')),
    notes TEXT,
    status VARCHAR(50) DEFAULT 'pending' CHECK (status IN ('pending', 'confirmed', 'completed', 'cancelled', 'no-show')),
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    confirmed_at TIMESTAMP,
    completed_at TIMESTAMP,
    cancellation_reason TEXT,
    FOREIGN KEY (request_id) REFERENCES requests(request_id) ON DELETE CASCADE,
    FOREIGN KEY (professional_id) REFERENCES professionals(professional_id) ON DELETE SET NULL,
    FOREIGN KEY (scheduled_by_staff_id) REFERENCES staff(staff_id) ON DELETE SET NULL
);

-- ============================================
-- NOTIFICATIONS TABLE (System Notifications)
-- ============================================
CREATE TABLE notifications (
    notification_id SERIAL PRIMARY KEY,
    recipient_email VARCHAR(255) NOT NULL,
    recipient_type VARCHAR(50) NOT NULL CHECK (recipient_type IN ('citizen', 'staff', 'professional')),
    notification_type VARCHAR(50) NOT NULL CHECK (notification_type IN ('appointment_scheduled', 'appointment_confirmed', 'appointment_cancelled', 'request_update', 'system_alert')),
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
-- MENTAL HEALTH WORKFLOW INDEXES
-- ============================================

-- Professionals indexes
CREATE INDEX idx_professionals_email ON professionals(email);
CREATE INDEX idx_professionals_status ON professionals(status);
CREATE INDEX idx_professionals_specialization ON professionals(specialization);
CREATE INDEX idx_professionals_license ON professionals(license_number);

-- Appointments indexes
CREATE INDEX idx_appointments_request ON appointments(request_id);
CREATE INDEX idx_appointments_professional ON appointments(professional_id);
CREATE INDEX idx_appointments_citizen ON appointments(citizen_email);
CREATE INDEX idx_appointments_date ON appointments(appointment_date);
CREATE INDEX idx_appointments_status ON appointments(status);
CREATE INDEX idx_appointments_scheduled_by ON appointments(scheduled_by_staff_id);

-- Notifications indexes
CREATE INDEX idx_notifications_recipient ON notifications(recipient_email);
CREATE INDEX idx_notifications_type ON notifications(notification_type);
CREATE INDEX idx_notifications_read ON notifications(is_read);
CREATE INDEX idx_notifications_created ON notifications(created_at DESC);
CREATE INDEX idx_notifications_request ON notifications(related_request_id);
CREATE INDEX idx_notifications_appointment ON notifications(related_appointment_id);

-- ============================================
-- UPDATE REQUESTS TABLE FOR MENTAL HEALTH
-- ============================================

-- Add new columns to requests table for mental health workflow
ALTER TABLE requests ADD COLUMN IF NOT EXISTS appointment_id VARCHAR(50);
ALTER TABLE requests ADD COLUMN IF NOT EXISTS referral_status VARCHAR(50) CHECK (referral_status IN ('none', 'scheduling', 'waiting_confirmation', 'confirmed', 'completed'));
ALTER TABLE requests ADD CONSTRAINT fk_requests_appointment FOREIGN KEY (appointment_id) REFERENCES appointments(appointment_id) ON DELETE SET NULL;

-- Set default referral_status for existing records
UPDATE requests SET referral_status = 'none' WHERE referral_status IS NULL;

-- ============================================
-- SAMPLE MENTAL HEALTH PROFESSIONALS
-- ============================================


-- Insert sample mental health professionals - password: "password123"
INSERT INTO professionals (professional_id, full_name, email, password_hash, phone, license_number, specialization, qualifications, years_of_experience, status, availability_schedule, max_appointments_per_day, total_appointments, rating) VALUES
('GOV-0011', 'Dr. Emily Rodriguez', 'emily.rodriguez@mentalhealth.gov', '$2b$12$LQv3c1yqBWVHxkd0LHAkCOYz6TtxMQJqhN8/LewY5GyYNJL6BQMKG', '+1-555-1001', 'PSY-2023-1001', 'Clinical Psychologist', 'PhD in Clinical Psychology, Licensed Psychologist, Cognitive Behavioral Therapy (CBT) Specialist', 12, 'active', '{"monday": ["9:00-12:00", "2:00- 5:00"], "tuesday": ["9:00-12:00", "14:00-5:00"], "wednesday": ["9:00-12:00", "2:00-5:00"], "thursday": ["9:00-12:00", "14:00-17:00"], "friday": ["9:00-12:00"]}', 8, 0, 4.85);
('GOV-0012', 'Dr. Michael Chen', 'michael.chen@mentalhealth.gov', '$2b$12$EixZaYVK1fsbw1ZfbX3OXePaWxn96p36WQoeG6Lruj3vjPGga31lW', '+1-555-1002', 'PSY-2023-1002', 'Psychiatrist', 'MD Psychiatry, Board Certified, Anxiety & Depression Specialist', 15, 'active', '{"monday": ["10:00-1:00", "3:00-6:00"], "tuesday": ["10:00- 1:00", "3:00-6:00"], "wednesday": ["10:00-1:00"], "thursday": ["10:00-1:00", "3:00-6:00"], "friday": ["10:00-1:00", "3:00-6:00"]}', 10, 0, 4.92),

('GOV-0013', 'Sarah Thompson', 'sarah.thompson@mentalhealth.gov', '$2b$12$4Zo0.j7VKmXm5.N3tN5kBed/R2l3g0dVJYJKq4vQxqkPxkfU1QCZS', '+1-555-1003', 'COUN-2023-1003', 'Licensed Counselor', 'MA in Counseling Psychology, LMHC, Trauma & PTSD Specialist, Student Mental Health Expert', 8, 'active', '{"monday": ["8:00-12:00", "1:00-5:00"], "tuesday": ["8:00-12:00", "1:00-5:00"], "wednesday": ["8:00-12:00", "1:00-4:00"], "thursday": ["8:00-12:00", "1:00-5:00"], "friday": ["8:00-12:00"]}', 8, 0, 4.78),

('GOV-0014', 'Dr. James Wilson', 'james.wilson@mentalhealth.gov', '$2b$12$kA/LwGLx3mZvv8TqXELVEOl5j0yHXqZqGN0WbZ3Jh4wGvLMQqpPBO', '+1-555-1004', 'PSY-2023-1004', 'Child Psychologist', 'PsyD in Child Psychology, Play Therapy Certified, Adolescent Mental Health Specialist', 10, 'active', '{"monday": ["9:00-12:00", "2:00-5:00"], "tuesday": ["9:00-12:00", "2:00-5:00"], "thursday": ["9:00-12:00", "2:00-5:00"], "friday": ["9:00-12:00", "2:00-5:00"]}', 6, 0, 4.95);

-- ============================================
-- VERIFICATION
-- ============================================
SELECT 'Database created successfully!' as status,
       (SELECT COUNT(*) FROM citizens) as total_citizens,
       (SELECT COUNT(*) FROM staff) as total_staff,
       (SELECT COUNT(*) FROM requests) as total_requests,
       (SELECT COUNT(*) FROM professionals) as total_professionals,
       (SELECT COUNT(*) FROM appointments) as total_appointments,
       (SELECT COUNT(*) FROM notifications) as total_notifications;

Select * from staff;


ALTER TABLE requests DROP CONSTRAINT IF EXISTS requests_need_type_check;

ALTER TABLE requests ADD CONSTRAINT requests_need_type_check 
CHECK (need_type IN (
    'medical', 
    'dental-services',  -- Changed from 'Dental Services'
    'immunization',     -- Changed from 'Immunization'
    'laboratory',       -- Changed from 'Laboratory and Diagnostic'
    'mental-health',    -- Added
    'sanitary-inspection'  -- Changed from 'other'/'Sanitary Inspection'
));

-- Verify the change
SELECT constraint_name, check_clause 
FROM information_schema.check_constraints 
WHERE constraint_name = 'requests_need_type_check';