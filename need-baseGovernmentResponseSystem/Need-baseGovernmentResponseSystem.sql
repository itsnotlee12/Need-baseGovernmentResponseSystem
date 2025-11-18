-- ============================================
-- NEED-BASED GOVERNMENT RESPONSE SYSTEM
-- COMPLETE CORRECTED PostgreSQL SCHEMA
-- City Health Focus with Proper Relationships
-- UPDATED: 2025-11-17
-- ============================================

-- 0) DROP existing tables in safe order
DROP TABLE IF EXISTS notifications CASCADE;
DROP TABLE IF EXISTS appointments CASCADE;
DROP TABLE IF EXISTS audit_logs CASCADE;
DROP TABLE IF EXISTS requests CASCADE;
DROP TABLE IF EXISTS professionals CASCADE;
DROP TABLE IF EXISTS staff CASCADE;
DROP TABLE IF EXISTS citizens CASCADE;
DROP TABLE IF EXISTS departments CASCADE;
DROP TABLE IF EXISTS role_permissions CASCADE;

-- ============================================
-- 1) ROLE PERMISSIONS TABLE (Referenced by staff/professionals)
-- ============================================
CREATE TABLE role_permissions (
    role_id SERIAL PRIMARY KEY,
    role_name VARCHAR(50) UNIQUE NOT NULL,
    has_full_access BOOLEAN DEFAULT FALSE,
    allowed_need_types TEXT[], -- Array of allowed need types
    description TEXT,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

INSERT INTO role_permissions (role_name, has_full_access, allowed_need_types, description) VALUES
('admin', TRUE, NULL, 'Full system access to all health services'),
('officer', FALSE, ARRAY['medical', 'dental-services', 'immunization', 'laboratory', 'mental-health', 'sanitary-inspection'], 'General officer role'),
('officer_sanitary', FALSE, ARRAY['sanitary-inspection'], 'Sanitary inspection only'),
('officer_health', FALSE, ARRAY['medical', 'dental-services', 'immunization', 'laboratory', 'mental-health'], 'All health services except sanitary'),
('medical_doctor', FALSE, ARRAY['medical'], 'Medical services only'),
('dentist', FALSE, ARRAY['dental-services'], 'Dental services only'),
('immunization_doctor', FALSE, ARRAY['immunization'], 'Immunization services only'),
('mental_health_doctor', FALSE, ARRAY['mental-health'], 'Mental health services only'),
('medical_technologist', FALSE, ARRAY['laboratory'], 'Laboratory and diagnostics only'),
('citizen', FALSE, NULL, 'Own requests only');

-- ============================================
-- 2) DEPARTMENTS TABLE
-- ============================================
CREATE TABLE departments (
    department_id SERIAL PRIMARY KEY,
    department_name VARCHAR(150) UNIQUE NOT NULL,
    description TEXT,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

INSERT INTO departments (department_name, description) VALUES
('Administration', 'Administrative department'),
('Health and Medical Services', 'Comprehensive health and medical services'),
('Mental Health', 'Mental health and counseling services'),
('Dental Services', 'Dental care services'),
('Immunization', 'Vaccination and immunization services'),
('Laboratory and Diagnostics', 'Laboratory testing and diagnostics'),
('Sanitary Inspection', 'Sanitary inspection services');

-- ============================================
-- 3) CITIZENS TABLE
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
-- 4) STAFF TABLE
-- ============================================
CREATE TABLE staff (
    staff_id VARCHAR(50) PRIMARY KEY,
    full_name VARCHAR(255) NOT NULL,
    email VARCHAR(255) UNIQUE NOT NULL,
    password_hash VARCHAR(255),
    phone VARCHAR(50),
    official_id VARCHAR(50) UNIQUE,
    role VARCHAR(50) NOT NULL CHECK (role IN ('admin', 'officer')),
    user_role VARCHAR(50),
	department_id INTEGER,
    employee_id VARCHAR(50) UNIQUE,
    status VARCHAR(50) DEFAULT 'active' CHECK (status IN ('active', 'inactive')),
    joined_date TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    last_login TIMESTAMP,
    requests_handled INTEGER DEFAULT 0,
    permissions JSONB,
    added_by VARCHAR(255),
    added_date TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    deactivated_date TIMESTAMP,
    FOREIGN KEY (department_id) REFERENCES departments(department_id) ON DELETE SET NULL,
    FOREIGN KEY (user_role) REFERENCES role_permissions(role_name) ON DELETE SET NULL
);

-- ============================================
-- 5) PROFESSIONALS TABLE
-- ============================================
CREATE TABLE professionals (
    professional_id VARCHAR(50) PRIMARY KEY,
    full_name VARCHAR(255) NOT NULL,
    email VARCHAR(255) UNIQUE NOT NULL,
    password_hash VARCHAR(255) NOT NULL,
    phone VARCHAR(50),
    profession_type VARCHAR(100) NOT NULL,
    specialization VARCHAR(150),
    department_id INTEGER,
    user_role VARCHAR(50),
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
    added_date TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    FOREIGN KEY (department_id) REFERENCES departments(department_id) ON DELETE SET NULL,
    FOREIGN KEY (user_role) REFERENCES role_permissions(role_name) ON DELETE SET NULL
);

-- ============================================
-- 6) REQUESTS TABLE
-- ============================================
CREATE TABLE requests (
    request_id VARCHAR(50) PRIMARY KEY,
    citizen_id INTEGER,
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
    specification VARCHAR(100),
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
    FOREIGN KEY (citizen_id) REFERENCES citizens(citizen_id) ON DELETE SET NULL,
    FOREIGN KEY (assigned_staff_id) REFERENCES staff(staff_id) ON DELETE SET NULL
);

-- ============================================
-- 7) APPOINTMENTS TABLE
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
-- 8) NOTIFICATIONS TABLE
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
-- 9) AUDIT LOGS TABLE (No FK constraints - intentional)
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
-- 10) TRIGGERS
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
-- 11) INDEXES
-- ============================================

-- Citizens
CREATE INDEX idx_citizens_email ON citizens(email);
CREATE INDEX idx_citizens_active ON citizens(is_active);

-- Staff
CREATE INDEX idx_staff_email ON staff(email);
CREATE INDEX idx_staff_department ON staff(department_id);
CREATE INDEX idx_staff_role ON staff(role);
CREATE INDEX idx_staff_status ON staff(status);
CREATE INDEX idx_staff_user_role ON staff(user_role);

-- Professionals
CREATE INDEX idx_professionals_email ON professionals(email);
CREATE INDEX idx_professionals_status ON professionals(status);
CREATE INDEX idx_professionals_profession_type ON professionals(profession_type);
CREATE INDEX idx_professionals_license ON professionals(license_number);
CREATE INDEX idx_professionals_department ON professionals(department_id);
CREATE INDEX idx_professionals_user_role ON professionals(user_role);

-- Requests
CREATE INDEX idx_requests_citizen ON requests(citizen_id);
CREATE INDEX idx_requests_email ON requests(email);
CREATE INDEX idx_requests_status ON requests(status);
CREATE INDEX idx_requests_severity ON requests(severity);
CREATE INDEX idx_requests_priority ON requests(priority_score);
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
-- 12) VIEWS
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
    d.department_name,
    s.role,
    s.status,
    s.requests_handled,
    COUNT(r.request_id) FILTER (WHERE r.status NOT IN ('completed', 'cancelled', 'rejected')) AS current_assigned_requests
FROM staff s
LEFT JOIN departments d ON s.department_id = d.department_id
LEFT JOIN requests r ON s.staff_id = r.assigned_staff_id
GROUP BY s.staff_id, s.full_name, s.email, d.department_name, s.role, s.status, s.requests_handled
ORDER BY s.requests_handled DESC;

CREATE OR REPLACE VIEW dashboard_stats AS
SELECT 
    COUNT(*) FILTER (WHERE status = 'pending') AS pending_requests,
    COUNT(*) FILTER (WHERE status = 'in-progress') AS in_progress_requests,
    COUNT(*) FILTER (WHERE status = 'completed') AS completed_requests,
    COUNT(*) FILTER (WHERE severity = 'critical') AS critical_requests,
    COUNT(*) AS total_requests
FROM requests;

-- Admin Dashboard View (Full Access)
CREATE OR REPLACE VIEW admin_dashboard_view AS
SELECT 
    r.request_id,
    r.citizen_name,
    r.email,
    r.phone,
    r.location_address,
    r.need_type,
    r.specification,
    r.severity,
    r.people_affected,
    r.description,
    r.vulnerability_group,
    r.status,
    r.submitted_at,
    r.priority_score,
    r.assigned_to,
    r.referral_status,
    r.appointment_id,
    s.full_name as assigned_staff_name,
    d.department_name as assigned_department
FROM requests r
LEFT JOIN staff s ON r.assigned_staff_id = s.staff_id
LEFT JOIN departments d ON s.department_id = d.department_id
ORDER BY r.priority_score DESC, r.submitted_at DESC;

-- Officer Sanitary View
CREATE OR REPLACE VIEW officer_sanitary_dashboard_view AS
SELECT 
    r.request_id,
    r.citizen_name,
    r.email,
    r.phone,
    r.location_address,
    r.need_type,
    r.specification,
    r.severity,
    r.people_affected,
    r.description,
    r.status,
    r.submitted_at,
    r.priority_score,
    r.assigned_to
FROM requests r
WHERE r.need_type = 'sanitary-inspection'
ORDER BY r.priority_score DESC, r.submitted_at DESC;

-- Officer Health View
CREATE OR REPLACE VIEW officer_health_dashboard_view AS
SELECT 
    r.request_id,
    r.citizen_name,
    r.email,
    r.phone,
    r.location_address,
    r.need_type,
    r.specification,
    r.severity,
    r.people_affected,
    r.description,
    r.status,
    r.submitted_at,
    r.priority_score,
    r.assigned_to,
    r.referral_status,
    r.appointment_id
FROM requests r
WHERE r.need_type IN ('medical', 'dental-services', 'immunization', 'laboratory', 'mental-health')
ORDER BY r.priority_score DESC, r.submitted_at DESC;

-- Medical Doctor View
CREATE OR REPLACE VIEW medical_doctor_dashboard_view AS
SELECT 
    r.request_id,
    r.citizen_name,
    r.email,
    r.phone,
    r.location_address,
    r.specification,
    r.severity,
    r.description,
    r.status,
    r.submitted_at,
    r.referral_status,
    a.appointment_id,
    a.appointment_date,
    a.appointment_time,
    a.status as appointment_status
FROM requests r
LEFT JOIN appointments a ON r.appointment_id = a.appointment_id
WHERE r.need_type = 'medical'
ORDER BY r.submitted_at DESC;

-- Dentist View
CREATE OR REPLACE VIEW dentist_dashboard_view AS
SELECT 
    r.request_id,
    r.citizen_name,
    r.email,
    r.phone,
    r.specification,
    r.description,
    r.status,
    r.submitted_at,
    a.appointment_id,
    a.appointment_date,
    a.appointment_time,
    a.status as appointment_status
FROM requests r
LEFT JOIN appointments a ON r.appointment_id = a.appointment_id
WHERE r.need_type = 'dental-services'
ORDER BY r.submitted_at DESC;

-- Immunization Doctor View
CREATE OR REPLACE VIEW immunization_doctor_dashboard_view AS
SELECT 
    r.request_id,
    r.citizen_name,
    r.email,
    r.phone,
    r.specification,
    r.description,
    r.status,
    r.submitted_at,
    a.appointment_id,
    a.appointment_date,
    a.appointment_time
FROM requests r
LEFT JOIN appointments a ON r.appointment_id = a.appointment_id
WHERE r.need_type = 'immunization'
ORDER BY r.submitted_at DESC;

-- Mental Health Doctor View
CREATE OR REPLACE VIEW mental_health_doctor_dashboard_view AS
SELECT 
    r.request_id,
    r.citizen_name,
    r.email,
    r.phone,
    r.description,
    r.status,
    r.submitted_at,
    r.referral_status,
    a.appointment_id,
    a.appointment_date,
    a.appointment_time,
    a.status as appointment_status,
    a.notes
FROM requests r
LEFT JOIN appointments a ON r.appointment_id = a.appointment_id
WHERE r.need_type = 'mental-health'
ORDER BY r.submitted_at DESC;

-- Medical Technologist View
CREATE OR REPLACE VIEW medical_technologist_dashboard_view AS
SELECT 
    r.request_id,
    r.citizen_name,
    r.email,
    r.phone,
    r.specification,
    r.description,
    r.status,
    r.submitted_at,
    a.appointment_id,
    a.appointment_date,
    a.appointment_time
FROM requests r
LEFT JOIN appointments a ON r.appointment_id = a.appointment_id
WHERE r.need_type = 'laboratory'
ORDER BY r.submitted_at DESC;

-- Citizen View (Own Requests Only)
CREATE OR REPLACE VIEW citizen_dashboard_view AS
SELECT 
    r.request_id,
    r.need_type,
    r.specification,
    r.severity,
    r.description,
    r.status,
    r.submitted_at,
    r.priority_score,
    r.estimated_response_time,
    r.assigned_to,
    r.referral_status,
    a.appointment_date,
    a.appointment_time,
    a.status as appointment_status
FROM requests r
LEFT JOIN appointments a ON r.appointment_id = a.appointment_id
WHERE r.email = current_user
ORDER BY r.submitted_at DESC;

-- ============================================
-- 13) SAMPLE DATA
-- ============================================

-- Staff (with proper department_id and user_role)
INSERT INTO staff (staff_id, full_name, email, password_hash, phone, official_id, department_id, role, user_role, employee_id, status, joined_date, requests_handled, permissions, added_by, added_date)
VALUES
('ADMIN-0001', 'John Administrator', 'john.administrator@gov.example.com', '$2b$12$examplehashforpassword', '+1-555-7716', 'GOV-10001', 1, 'admin', 'admin', 'EMP-0001', 'active', '2020-01-01 08:00:00', 0, '{"viewRequests": true, "manageRequests": true}', 'system', CURRENT_TIMESTAMP);

-- ============================================
-- 14) HELPER FUNCTIONS
-- ============================================

CREATE OR REPLACE FUNCTION get_user_role(user_email TEXT)
RETURNS TEXT AS $$
DECLARE
    user_role TEXT;
BEGIN
    -- Check if user is admin
    SELECT 'admin' INTO user_role
    FROM staff
    WHERE email = user_email AND role = 'admin' AND status = 'active';
    
    IF user_role IS NOT NULL THEN
        RETURN user_role;
    END IF;
    
    -- Check if user is staff officer
    SELECT staff.user_role INTO user_role
    FROM staff
    WHERE email = user_email AND role = 'officer' AND status = 'active';
    
    IF user_role IS NOT NULL THEN
        RETURN user_role;
    END IF;
    
    -- Check if user is professional
    SELECT professionals.user_role INTO user_role
    FROM professionals
    WHERE email = user_email AND status = 'active';
    
    IF user_role IS NOT NULL THEN
        RETURN user_role;
    END IF;
    
    -- Default to citizen
    RETURN 'citizen';
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- ============================================
-- 15) AUDIT FUNCTION
-- ============================================

CREATE OR REPLACE FUNCTION log_data_access()
RETURNS TRIGGER AS $$
BEGIN
    INSERT INTO audit_logs (
        audit_code,
        action_type,
        user_email,
        entity_type,
        entity_id,
        details
    ) VALUES (
        'AUDIT-' || to_char(NOW(), 'YYYYMMDDHH24MISS') || '-' || floor(random() * 1000)::text,
        TG_OP,
        current_user,
        TG_TABLE_NAME,
        COALESCE(NEW.request_id, OLD.request_id),
        'Database-level ' || TG_OP || ' operation'
    );
    
    IF TG_OP = 'DELETE' THEN
        RETURN OLD;
    ELSE
        RETURN NEW;
    END IF;
END;
$$ LANGUAGE plpgsql;

-- Apply audit trigger to requests table
DROP TRIGGER IF EXISTS audit_requests_trigger ON requests;
CREATE TRIGGER audit_requests_trigger
    AFTER INSERT OR UPDATE OR DELETE ON requests
    FOR EACH ROW EXECUTE FUNCTION log_data_access();

-- ============================================
-- 16) VERIFICATION QUERY
-- ============================================
SELECT 'Database created successfully!' AS status,
       (SELECT COUNT(*) FROM citizens) AS total_citizens,
       (SELECT COUNT(*) FROM staff) AS total_staff,
       (SELECT COUNT(*) FROM requests) AS total_requests,
       (SELECT COUNT(*) FROM professionals) AS total_professionals,
       (SELECT COUNT(*) FROM appointments) AS total_appointments,
       (SELECT COUNT(*) FROM notifications) AS total_notifications,
       (SELECT COUNT(*) FROM departments) AS total_departments,
       (SELECT COUNT(*) FROM role_permissions) AS total_roles;

-- ============================================
-- 17) DATABASE ROLE-BASED ACCESS CONTROL (RBAC)
-- ============================================

-- Revoke all existing privileges before dropping roles
-- Revoke all existing privileges before dropping roles 
DO $$
DECLARE
    r RECORD;
BEGIN
    -- Revoke database privileges
    FOR r IN 
        SELECT rolname 
        FROM pg_roles 
        WHERE rolname LIKE 'app_%'
    LOOP
        EXECUTE format('REVOKE ALL ON DATABASE "Need-baseGovernmentResponseSystem" FROM %I', r.rolname);
        EXECUTE format('REVOKE ALL ON ALL TABLES IN SCHEMA public FROM %I', r.rolname);
        EXECUTE format('REVOKE ALL ON ALL SEQUENCES IN SCHEMA public FROM %I', r.rolname);
    END LOOP;
END;
$$;

-- Now safely drop existing roles if they exist
DO $$
BEGIN
    DROP ROLE IF EXISTS app_admin;
    DROP ROLE IF EXISTS app_officer_sanitary;
    DROP ROLE IF EXISTS app_officer_health;
    DROP ROLE IF EXISTS app_medical_doctor;
    DROP ROLE IF EXISTS app_dentist;
    DROP ROLE IF EXISTS app_immunization_doctor;
    DROP ROLE IF EXISTS app_mental_health_doctor;
    DROP ROLE IF EXISTS app_medical_technologist;
    DROP ROLE IF EXISTS app_citizen;
EXCEPTION
    WHEN OTHERS THEN
        RAISE NOTICE 'Some roles could not be dropped, they may not exist yet';
END;
$$;

-- Create roles for each user type
CREATE ROLE app_admin LOGIN PASSWORD 'change_this_admin_password';
CREATE ROLE app_officer_sanitary LOGIN PASSWORD 'change_this_officer_san_password';
CREATE ROLE app_officer_health LOGIN PASSWORD 'change_this_officer_health_password';
CREATE ROLE app_medical_doctor LOGIN PASSWORD 'change_this_medical_doc_password';
CREATE ROLE app_dentist LOGIN PASSWORD 'change_this_dentist_password';
CREATE ROLE app_immunization_doctor LOGIN PASSWORD 'change_this_immun_doc_password';
CREATE ROLE app_mental_health_doctor LOGIN PASSWORD 'change_this_mental_doc_password';
CREATE ROLE app_medical_technologist LOGIN PASSWORD 'change_this_medtech_password';
CREATE ROLE app_citizen LOGIN PASSWORD 'change_this_citizen_password';

-- Grant basic database connection
GRANT CONNECT ON DATABASE "Need-baseGovernmentResponseSystem" TO app_admin;
GRANT CONNECT ON DATABASE "Need-baseGovernmentResponseSystem" TO app_officer_sanitary;
GRANT CONNECT ON DATABASE "Need-baseGovernmentResponseSystem" TO app_officer_health;
GRANT CONNECT ON DATABASE "Need-baseGovernmentResponseSystem" TO app_medical_doctor;
GRANT CONNECT ON DATABASE "Need-baseGovernmentResponseSystem" TO app_dentist;
GRANT CONNECT ON DATABASE "Need-baseGovernmentResponseSystem" TO app_immunization_doctor;
GRANT CONNECT ON DATABASE "Need-baseGovernmentResponseSystem" TO app_mental_health_doctor;
GRANT CONNECT ON DATABASE "Need-baseGovernmentResponseSystem" TO app_medical_technologist;
GRANT CONNECT ON DATABASE "Need-baseGovernmentResponseSystem" TO app_citizen;

-- ============================================
-- 18) ENABLE ROW LEVEL SECURITY (RLS)
-- ============================================

ALTER TABLE requests ENABLE ROW LEVEL SECURITY;
ALTER TABLE appointments ENABLE ROW LEVEL SECURITY;
ALTER TABLE notifications ENABLE ROW LEVEL SECURITY;
ALTER TABLE staff ENABLE ROW LEVEL SECURITY;
ALTER TABLE professionals ENABLE ROW LEVEL SECURITY;

-- ============================================
-- 19) CREATE RLS POLICIES FOR REQUESTS
-- ============================================

-- Admin: Full access to all requests
CREATE POLICY admin_requests_policy ON requests
    FOR ALL
    TO app_admin
    USING (true)
    WITH CHECK (true);

-- Officer Sanitary: Only sanitary-inspection requests
CREATE POLICY officer_sanitary_requests_policy ON requests
    FOR ALL
    TO app_officer_sanitary
    USING (need_type = 'sanitary-inspection')
    WITH CHECK (need_type = 'sanitary-inspection');

-- Officer Health: All health services except sanitary
CREATE POLICY officer_health_requests_policy ON requests
    FOR ALL
    TO app_officer_health
    USING (need_type IN ('medical', 'dental-services', 'immunization', 'laboratory', 'mental-health'))
    WITH CHECK (need_type IN ('medical', 'dental-services', 'immunization', 'laboratory', 'mental-health'));

-- Medical Doctor: Only medical requests
CREATE POLICY medical_doctor_requests_policy ON requests
    FOR SELECT
    TO app_medical_doctor
    USING (need_type = 'medical');

-- Dentist: Only dental-services requests
CREATE POLICY dentist_requests_policy ON requests
    FOR SELECT
    TO app_dentist
    USING (need_type = 'dental-services');

-- Immunization Doctor: Only immunization requests
CREATE POLICY immunization_doctor_requests_policy ON requests
    FOR SELECT
    TO app_immunization_doctor
    USING (need_type = 'immunization');

-- Mental Health Doctor: Only mental-health requests
CREATE POLICY mental_health_doctor_requests_policy ON requests
    FOR SELECT
    TO app_mental_health_doctor
    USING (need_type = 'mental-health');

-- Medical Technologist: Only laboratory requests
CREATE POLICY medical_technologist_requests_policy ON requests
    FOR SELECT
    TO app_medical_technologist
    USING (need_type = 'laboratory');

-- Citizens: Only their own requests
CREATE POLICY citizen_requests_policy ON requests
    FOR ALL
    TO app_citizen
    USING (email = current_user)
    WITH CHECK (email = current_user);

-- ============================================
-- 20) CREATE RLS POLICIES FOR APPOINTMENTS
-- ============================================

-- Admin: Full access
CREATE POLICY admin_appointments_policy ON appointments
    FOR ALL
    TO app_admin
    USING (true)
    WITH CHECK (true);

-- Officers: Based on request need_type
CREATE POLICY officer_sanitary_appointments_policy ON appointments
    FOR ALL
    TO app_officer_sanitary
    USING (
        EXISTS (
            SELECT 1 FROM requests r 
            WHERE r.request_id = appointments.request_id 
            AND r.need_type = 'sanitary-inspection'
        )
    );

CREATE POLICY officer_health_appointments_policy ON appointments
    FOR ALL
    TO app_officer_health
    USING (
        EXISTS (
            SELECT 1 FROM requests r 
            WHERE r.request_id = appointments.request_id 
            AND r.need_type IN ('medical', 'dental-services', 'immunization', 'laboratory', 'mental-health')
        )
    );

-- Professionals: Only their own appointments
CREATE POLICY professionals_appointments_policy ON appointments
    FOR ALL
    TO app_medical_doctor, app_dentist, app_immunization_doctor, 
        app_mental_health_doctor, app_medical_technologist
    USING (
        professional_id IN (
            SELECT professional_id FROM professionals 
            WHERE email = current_user
        )
    );

-- Citizens: Only their own appointments
CREATE POLICY citizen_appointments_policy ON appointments
    FOR SELECT
    TO app_citizen
    USING (citizen_email = current_user);

-- ============================================
-- 21) CREATE RLS POLICIES FOR NOTIFICATIONS
-- ============================================

-- Everyone can see their own notifications
CREATE POLICY user_notifications_policy ON notifications
    FOR ALL
    USING (recipient_email = current_user)
    WITH CHECK (recipient_email = current_user);

-- ============================================
-- 22) GRANT TABLE PERMISSIONS
-- ============================================

-- Admin: Full access to all tables
GRANT ALL ON ALL TABLES IN SCHEMA public TO app_admin;
GRANT ALL ON ALL SEQUENCES IN SCHEMA public TO app_admin;

-- Officers: Read/Write on requests, appointments, notifications
GRANT SELECT, INSERT, UPDATE ON requests TO app_officer_sanitary, app_officer_health;
GRANT SELECT, INSERT, UPDATE ON appointments TO app_officer_sanitary, app_officer_health;
GRANT SELECT, INSERT ON notifications TO app_officer_sanitary, app_officer_health;
GRANT SELECT ON professionals TO app_officer_sanitary, app_officer_health;
GRANT SELECT ON staff TO app_officer_sanitary, app_officer_health;
GRANT SELECT ON departments TO app_officer_sanitary, app_officer_health;
GRANT USAGE ON ALL SEQUENCES IN SCHEMA public TO app_officer_sanitary, app_officer_health;

-- Professionals: Read requests/appointments, Update appointments
GRANT SELECT ON requests TO app_medical_doctor, app_dentist, app_immunization_doctor, 
    app_mental_health_doctor, app_medical_technologist;
GRANT SELECT, UPDATE ON appointments TO app_medical_doctor, app_dentist, app_immunization_doctor, 
    app_mental_health_doctor, app_medical_technologist;
GRANT SELECT, INSERT ON notifications TO app_medical_doctor, app_dentist, app_immunization_doctor, 
    app_mental_health_doctor, app_medical_technologist;
GRANT SELECT ON professionals TO app_medical_doctor, app_dentist, app_immunization_doctor, 
    app_mental_health_doctor, app_medical_technologist;
GRANT SELECT ON staff TO app_medical_doctor, app_dentist, app_immunization_doctor, 
    app_mental_health_doctor, app_medical_technologist;
GRANT SELECT ON departments TO app_medical_doctor, app_dentist, app_immunization_doctor, 
    app_mental_health_doctor, app_medical_technologist;

-- Citizens: Read own requests, Insert new requests
GRANT SELECT, INSERT ON requests TO app_citizen;
GRANT SELECT ON appointments TO app_citizen;
GRANT SELECT ON notifications TO app_citizen;
GRANT USAGE ON ALL SEQUENCES IN SCHEMA public TO app_citizen;

-- Grant view permissions
GRANT SELECT ON admin_dashboard_view TO app_admin;
GRANT SELECT ON officer_sanitary_dashboard_view TO app_officer_sanitary;
GRANT SELECT ON officer_health_dashboard_view TO app_officer_health;
GRANT SELECT ON medical_doctor_dashboard_view TO app_medical_doctor;
GRANT SELECT ON dentist_dashboard_view TO app_dentist;
GRANT SELECT ON immunization_doctor_dashboard_view TO app_immunization_doctor;
GRANT SELECT ON mental_health_doctor_dashboard_view TO app_mental_health_doctor;
GRANT SELECT ON medical_technologist_dashboard_view TO app_medical_technologist;
GRANT SELECT ON citizen_dashboard_view TO app_citizen;

-- ============================================
-- 23) VERIFICATION QUERIES FOR RBAC
-- ============================================

-- Check created roles
SELECT rolname, rolcanlogin 
FROM pg_roles 
WHERE rolname LIKE 'app_%'
ORDER BY rolname;

-- Check RLS policies
SELECT schemaname, tablename, policyname, permissive, roles, cmd
FROM pg_policies
WHERE tablename IN ('requests', 'appointments', 'notifications', 'staff', 'professionals')
ORDER BY tablename, policyname;

-- Check view permissions
SELECT table_name, grantee, privilege_type
FROM information_schema.table_privileges
WHERE table_name LIKE '%_dashboard_view'
ORDER BY table_name, grantee;

-- ============================================
-- SUMMARY OF RELATIONSHIPS:
-- ============================================
-- role_permissions (1) ──< (M) staff.user_role
-- role_permissions (1) ──< (M) professionals.user_role
-- departments (1) ──< (M) staff.department_id
-- departments (1) ──< (M) professionals.department_id
-- citizens (1) ──< (M) requests.citizen_id
-- staff (1) ──< (M) requests.assigned_staff_id
-- professionals (1) ──< (M) appointments.professional_id
-- staff (1) ──< (M) appointments.scheduled_by_staff_id
-- requests (1) ──< (M) appointments.request_id
-- requests (1) ──< (M) notifications.related_request_id
-- appointments (1) ──< (M) notifications.related_appointment_id
-- ============================================

-- ============================================
-- RBAC SUMMARY:
-- ============================================
-- Database Roles Created:
-- - app_admin: Full system access
-- - app_officer_sanitary: Sanitary inspection only
-- - app_officer_health: All health services
-- - app_medical_doctor: Medical requests only
-- - app_dentist: Dental requests only
-- - app_immunization_doctor: Immunization requests only
-- - app_mental_health_doctor: Mental health requests only
-- - app_medical_technologist: Laboratory requests only
-- - app_citizen: Own requests only
--
-- Row-Level Security: ENABLED on all sensitive tables
-- Access Control: Role-based with need_type filtering
-- ============================================


select * from staff;

select * from Professionals;


SELECT * FROM citizens;

select * from requests;