# Mental Health Professional Workflow - Implementation Guide

## Overview
A comprehensive mental health appointment system has been integrated into the Need-Based Government Response System. This workflow enables staff to schedule appointments with mental health professionals for student mental health requests, with a two-stage notification system to keep citizens informed.

## Database Schema

### 1. Professionals Table
Stores mental health professional information:
```sql
CREATE TABLE professionals (
    professional_id VARCHAR(50) PRIMARY KEY,
    email VARCHAR(255) UNIQUE NOT NULL,
    password_hash VARCHAR(255) NOT NULL,
    name VARCHAR(255) NOT NULL,
    specialization VARCHAR(100) NOT NULL,
    phone VARCHAR(20),
    license_number VARCHAR(100) UNIQUE,
    availability_schedule JSONB,
    rating DECIMAL(2,1) DEFAULT 5.0,
    status VARCHAR(20) DEFAULT 'active',
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);
```

**Sample Professionals (Password: `password123`):**
- sarah.thompson@mentalhealth.gov - Clinical Psychologist
- dr.michael.chen@mentalhealth.gov - Psychiatrist
- emily.rodriguez@mentalhealth.gov - Licensed Counselor
- dr.james.wilson@mentalhealth.gov - Child Psychologist

### 2. Appointments Table
Tracks appointment scheduling and status:
```sql
CREATE TABLE appointments (
    appointment_id VARCHAR(50) PRIMARY KEY,
    request_id VARCHAR(50) REFERENCES requests(request_id),
    professional_id VARCHAR(50) REFERENCES professionals(professional_id),
    scheduled_by_staff_id VARCHAR(50) REFERENCES staff(staff_id),
    citizen_name VARCHAR(255) NOT NULL,
    citizen_email VARCHAR(255) NOT NULL,
    citizen_phone VARCHAR(20) NOT NULL,
    appointment_date DATE NOT NULL,
    appointment_time TIME NOT NULL,
    appointment_type VARCHAR(100),
    notes TEXT,
    status VARCHAR(50) DEFAULT 'pending',
    confirmed_at TIMESTAMP,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);
```

**Status Values:**
- `pending` - Scheduled by staff, awaiting professional confirmation
- `confirmed` - Professional confirmed appointment
- `completed` - Appointment session completed
- `cancelled` - Appointment cancelled

### 3. Notifications Table
Manages multi-stage notifications to citizens:
```sql
CREATE TABLE notifications (
    notification_id VARCHAR(50) PRIMARY KEY,
    recipient_email VARCHAR(255) NOT NULL,
    recipient_type VARCHAR(50) NOT NULL,
    notification_type VARCHAR(100) NOT NULL,
    title VARCHAR(255) NOT NULL,
    message TEXT NOT NULL,
    related_request_id VARCHAR(50) REFERENCES requests(request_id),
    related_appointment_id VARCHAR(50) REFERENCES appointments(appointment_id),
    is_read BOOLEAN DEFAULT FALSE,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);
```

**Notification Types:**
- `appointment_scheduled` - Initial notification when staff schedules
- `appointment_confirmed` - Notification when professional confirms with details

### 4. Updated Requests Table
Added columns for mental health workflow tracking:
```sql
ALTER TABLE requests ADD COLUMN appointment_id VARCHAR(50) REFERENCES appointments(appointment_id);
ALTER TABLE requests ADD COLUMN referral_status VARCHAR(50) CHECK (referral_status IN ('none', 'scheduling', 'waiting_confirmation', 'confirmed', 'completed'));
```

## Workflow Process

### Stage 1: Staff Scheduling
1. **Trigger:** Staff member clicks "Start Process" on an in-progress mental health request from a student
2. **Action:** Modal opens showing:
   - Patient information (name, email)
   - Professional selection dropdown
   - Date/time picker
   - Appointment type selection
   - Notes field
3. **Backend Process:**
   - Creates appointment record with status `pending`
   - Updates request `referral_status` to `waiting_confirmation`
   - Creates notification to citizen: "Your mental health appointment has been scheduled and is waiting for confirmation from the professional."
4. **User Experience:**
   - Staff sees "Waiting for Confirmation" badge on request
   - Citizen receives notification but doesn't have doctor details yet

### Stage 2: Professional Confirmation
1. **Login:** Professional logs in at `/professional/login`
2. **Dashboard:** Shows appointments in tabs:
   - Pending Confirmation (requires action)
   - Confirmed (upcoming appointments)
   - Completed (historical)
3. **Action:** Professional clicks "Confirm Appointment" on pending appointment
4. **Backend Process:**
   - Updates appointment status to `confirmed`
   - Records `confirmed_at` timestamp
   - Creates detailed notification to citizen with:
     - Doctor name and specialization
     - Doctor phone number
     - Appointment date and time
     - Request ID for reference
5. **User Experience:**
   - Citizen receives notification with all appointment details
   - Staff can now "Mark Complete" the request
   - Professional sees appointment in "Confirmed" tab

### Stage 3: Completion
1. **After Appointment:** Professional marks appointment as `completed`
2. **Staff Action:** Staff clicks "Mark Complete" on request
3. **Final Status:** Request status becomes `completed`

## API Endpoints

### Professional Authentication
- **POST** `/api/login` (with role='professional')
  - Login for mental health professionals
  - Returns session with professional details

### Professional Dashboard
- **GET** `/professional/dashboard`
  - Renders professional dashboard with appointments
  - Shows pending, confirmed, and completed appointments
  - Displays unread notifications

### Appointment Management
- **POST** `/api/staff/schedule_appointment`
  - Schedules appointment (staff only)
  - Required: request_id, professional_id, appointment_date, appointment_time, appointment_type
  - Optional: notes
  - Creates appointment and sends first notification

- **POST** `/api/professional/confirm_appointment`
  - Confirms appointment (professional only)
  - Required: appointment_id
  - Updates status and sends detailed notification

- **GET** `/api/professionals/list`
  - Returns all active mental health professionals
  - Used in staff scheduling modal

### Notifications
- **GET** `/api/notifications/list`
  - Returns notifications for logged-in user
  - Filtered by recipient_email

- **POST** `/api/notifications/mark_read`
  - Marks notification as read
  - Required: notification_id

## Frontend Components

### 1. Government Dashboard Updates
**File:** `templates/government_dashboard.html`

**New Features:**
- "Start Process" button for student mental health requests (only when status is `in-progress`)
- Status badges showing referral workflow state:
  - No badge → "Start Process" available
  - "Waiting for Confirmation" → Appointment scheduled, awaiting professional
  - After confirmation → "Mark Complete" available
- Schedule appointment modal with form fields

**Key Functions:**
- `openScheduleModal(requestId, citizenName, citizenEmail)` - Opens scheduling modal
- `scheduleAppointment(event)` - Submits appointment to API
- `loadProfessionals()` - Populates professional dropdown

### 2. Professional Login Page
**File:** `templates/professional_login.html`

**Features:**
- Email/password authentication
- Role automatically set to 'professional'
- Test credentials display
- Error handling

### 3. Professional Dashboard
**File:** `templates/professional_dashboard.html`

**Features:**
- Statistics cards (pending, confirmed, completed counts)
- Tabbed interface for different appointment statuses
- Appointment cards with patient details
- "Confirm Appointment" buttons for pending appointments
- Notifications bell with badge
- Responsive design

**Key Functions:**
- `renderAppointments()` - Displays appointments in respective tabs
- `confirmAppointment(appointmentId)` - Confirms appointment via API
- Tab switching for viewing different appointment statuses

### 4. Citizen Dashboard Updates
**File:** `templates/citizen_dashboard.html`

**New Features:**
- Notifications section at top of dashboard
- Auto-refresh notifications every 30 seconds
- Two types of notification displays:
  - Orange border: Appointment scheduled (waiting for confirmation)
  - Green border: Appointment confirmed (includes doctor details)
- "Mark Read" button for each notification

**Key Functions:**
- `loadNotifications()` - Fetches and displays notifications
- `markNotificationRead(notificationId)` - Marks notification as read

## Installation & Setup

### 1. Database Migration
Run the migration SQL file:
```bash
psql -U postgres -d your_database -f mental_health_workflow_migration.sql
```

This will:
- Create 3 new tables (professionals, appointments, notifications)
- Add 4 sample mental health professionals
- Update requests table with new columns
- Create 15+ indexes for performance

### 2. Backend Routes
The following routes have been added to `app.py`:
- Professional login routes
- Professional dashboard routes
- Appointment scheduling APIs
- Notification management APIs

### 3. Test the Workflow

**Step 1: Submit Student Mental Health Request**
- Login as citizen (student)
- Submit request with need type "Mental Health"
- Check "I am a student" option

**Step 2: Start Process as Staff**
- Login as government staff (Health & Medical department)
- Find the student mental health request
- Click "Start Processing" to change status to in-progress
- Click "Start Process" button
- Select a professional from dropdown
- Set appointment date/time
- Select appointment type
- Add optional notes
- Submit

**Step 3: Confirm as Professional**
- Logout and go to `/professional/login`
- Login with professional credentials (e.g., sarah.thompson@mentalhealth.gov / password123)
- View pending appointments
- Click "Confirm Appointment"

**Step 4: Check Citizen Notifications**
- Login as the original citizen
- View dashboard - should see 2 notifications:
  1. Initial "waiting for confirmation" notification
  2. Detailed notification with doctor name, phone, date, time

**Step 5: Complete Request**
- Login as staff again
- Click "Mark Complete" on the request

## Security Considerations

1. **Authentication:**
   - Professionals have separate login credentials
   - Session-based authentication
   - Role-based access control

2. **Data Privacy:**
   - Citizen contact information only shared with assigned professional
   - Notifications contain only necessary information
   - Appointment notes visible only to professional and staff

3. **Authorization:**
   - Only staff can schedule appointments
   - Only assigned professionals can confirm their appointments
   - Only citizens can mark their own notifications as read

## Performance Optimizations

**Indexes Created:**
- Professionals: email, status, specialization
- Appointments: request_id, professional_id, status, appointment_date, citizen_email
- Notifications: recipient_email, is_read, notification_type, created_at
- Combined indexes for common query patterns

## Future Enhancements

1. **Calendar Integration:**
   - Professional availability calendar view
   - Conflict detection for double-booking
   - Recurring appointments

2. **Reminders:**
   - Automated email/SMS reminders 24 hours before appointment
   - Follow-up appointment scheduling

3. **Reporting:**
   - Professional performance metrics
   - Appointment completion rates
   - Average wait times

4. **Video Conferencing:**
   - Integration with telehealth platforms
   - Virtual appointment options

5. **Prescription Management:**
   - Allow psychiatrists to manage prescriptions
   - Track medication adherence

## Troubleshooting

### Issue: "Start Process" button not showing
- Verify request is `in-progress` status
- Check that `needType` is `mental-health`
- Confirm `isStudent` is `true`

### Issue: Professionals not loading in dropdown
- Check database connection
- Verify professionals table has active records
- Check browser console for API errors

### Issue: Notifications not appearing
- Verify notification was created in database
- Check `is_read` status
- Confirm recipient email matches logged-in user

### Issue: Cannot confirm appointment
- Verify professional is logged in
- Check appointment belongs to this professional
- Ensure appointment status is `pending`

## Contact & Support

For issues or questions about the mental health workflow:
1. Check database logs for error messages
2. Verify all migration scripts ran successfully
3. Test with sample professional accounts first
4. Review browser console for frontend errors
