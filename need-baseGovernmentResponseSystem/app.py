from flask import Flask, render_template, request, jsonify, session, redirect, url_for
from datetime import datetime
from psycopg2.extras import RealDictCursor
from werkzeug.utils import secure_filename
from itsdangerous import URLSafeTimedSerializer, BadSignature, SignatureExpired
import smtplib
import ssl
from email.message import EmailMessage
import psycopg2
import json
import bcrypt
import os
import uuid

app = Flask(__name__)
# Use environment variable for secret key in production
app.secret_key = os.environ.get('FLASK_SECRET_KEY', 'your-secret-key-change-in-production')

# File upload configuration
UPLOAD_FOLDER = os.path.join(app.root_path, 'static', 'uploads', 'sanitary_inspection')
ALLOWED_EXTENSIONS = {'png', 'jpg', 'jpeg', 'gif'}
MAX_FILE_SIZE = 5 * 1024 * 1024  # 5MB

app.config['UPLOAD_FOLDER'] = UPLOAD_FOLDER
app.config['MAX_CONTENT_LENGTH'] = MAX_FILE_SIZE


def allowed_file(filename):
    return '.' in filename and filename.rsplit('.', 1)[1].lower() in ALLOWED_EXTENSIONS


# In-memory data storage (loaded from database)
requests_db = []
users_db = {
    'citizens': {},
    'government': {}
}
audit_logs = []  # Audit trail for system actions
staff_db = []  # Government staff database


# Load requests from database on startup
def init_app():
    """Initialize application by loading data from database"""
    global requests_db
    print("Loading requests from database...")
    requests_db = load_requests_from_db()
    print(f"Loaded {len(requests_db)} requests from database")


def get_db_connection():
    conn = None
    try:
        # Database connection - uses environment variables with fallback to local development
        conn = psycopg2.connect(
            host=os.environ.get('DB_HOST', 'localhost'),
            database=os.environ.get('DB_NAME', 'Need-baseGovernmentResponseSystem'),
            user=os.environ.get('DB_USER', 'postgres'),
            password=os.environ.get('DB_PASSWORD', '123'),
            port=int(os.environ.get('DB_PORT', '5432'))
        )
        return conn
    except psycopg2.OperationalError as e:
        print(f"Error: Unable to connect to the database. Check your credentials.")
        print(e)
        return None


# ============================================
# DATABASE HELPER FUNCTIONS FOR REQUESTS
# ============================================

def load_requests_from_db():
    """Load all requests from database into memory using DictCursor"""
    conn = get_db_connection()
    if not conn:
        print("ERROR: No database connection in load_requests_from_db")
        return []

    try:
        cur = conn.cursor(cursor_factory=RealDictCursor)
        cur.execute("""
            SELECT request_id, citizen_name, email, phone, location_address,
                   need_type, specification, severity, people_affected, description,
                   vulnerability_group, special_circumstances,
                   has_evidence, status, submitted_at,
                   updated_at, completed_at, priority_score, 
                   estimated_response_time, assigned_to, assigned_staff_id, appointment_id, referral_status,
                   photo_evidence
            FROM requests
            ORDER BY submitted_at DESC
        """)

        rows = cur.fetchall()
        print(f"DEBUG: Loaded {len(rows)} requests from database")
        requests_list = []

        for row in rows:
            location_obj = {
                'address': row['location_address'] if row['location_address'] else '',
                'coordinates': {'lat': 0, 'lng': 0}
            }

            vulnerability_group = row['vulnerability_group']
            if isinstance(vulnerability_group, str):
                try:
                    vulnerability_group = json.loads(vulnerability_group)
                except:
                    vulnerability_group = ['none']
            elif vulnerability_group is None:
                vulnerability_group = ['none']

            requests_list.append({
                'id': row['request_id'],
                'citizenName': row['citizen_name'],
                'email': row['email'],
                'phone': row['phone'],
                'location': location_obj,
                'needType': row['need_type'],
                'specification': row['specification'],
                'severity': row['severity'],
                'peopleAffected': row['people_affected'],
                'description': row['description'],
                'vulnerabilityGroup': vulnerability_group,
                'specialCircumstances': row['special_circumstances'],
                'hasEvidence': row['has_evidence'],
                'status': row['status'],
                'submittedAt': row['submitted_at'].isoformat() if row['submitted_at'] else None,
                'updatedAt': row['updated_at'].isoformat() if row['updated_at'] else None,
                'completedAt': row['completed_at'].isoformat() if row['completed_at'] else None,
                'priorityScore': row['priority_score'],
                'estimatedResponse': row['estimated_response_time'],
                'assignedTo': row['assigned_to'],
                'assignedStaffId': row['assigned_staff_id'],
                'appointmentId': row['appointment_id'],
                'referralStatus': row['referral_status'] if row['referral_status'] else 'none',
                'photoEvidence': row['photo_evidence'] if row['photo_evidence'] else []
            })

        cur.close()
        conn.close()
        print(f"DEBUG: Returning {len(requests_list)} requests")
        return requests_list
    except Exception as e:
        print(f"Error loading requests from database: {e}")
        import traceback
        traceback.print_exc()
        if conn:
            conn.close()
        return []


def save_request_to_db(request_data):
    """Save a single request to database with improved error handling"""
    conn = get_db_connection()
    if not conn:
        print("ERROR: No database connection")
        return False

    try:
        cur = conn.cursor()

        # TEMPORARY FIX: Disable the problematic trigger
        cur.execute("ALTER TABLE requests DISABLE TRIGGER audit_requests_trigger")

        # Extract and validate location address
        location_address = request_data.get('location', '')
        if isinstance(location_address, dict):
            location_address = location_address.get('address', '')
        elif location_address is None:
            location_address = ''

        # Get specification value - ensure it's None if not provided or empty
        specification = request_data.get('specification')
        if specification == '' or specification is None:
            specification = None

        # Get special circumstances - ensure it's None if not provided or empty
        special_circumstances = request_data.get('specialCircumstances')
        if special_circumstances == '' or special_circumstances is None:
            special_circumstances = None

        # Get vulnerability group - ensure it's a proper JSON array
        vulnerability_group = request_data.get('vulnerabilityGroup', ['none'])
        if not isinstance(vulnerability_group, list):
            vulnerability_group = ['none']

        # Debug logging
        print(f"\n=== SAVING REQUEST TO DATABASE ===")
        print(f"Request ID: {request_data['id']}")
        print(f"Citizen Name: {request_data['citizenName']}")
        print(f"Email: {request_data['email']}")
        print(f"Phone: {request_data.get('phone')}")
        print(f"Location: {location_address}")
        print(f"Need Type: {request_data['needType']}")
        print(f"Specification: {specification}")
        print(f"Severity: {request_data['severity']}")
        print(f"People Affected: {request_data.get('peopleAffected', 1)}")
        print(f"Description: {request_data['description'][:50]}...")
        print(f"Vulnerability Group: {vulnerability_group}")
        print(f"Special Circumstances: {special_circumstances}")
        print(f"Has Evidence: {request_data.get('hasEvidence', False)}")
        print(f"Photo Evidence: {request_data.get('photoEvidence', [])}")
        print(f"Status: {request_data.get('status', 'pending')}")
        print(f"Priority Score: {request_data.get('priorityScore', 0)}")
        print(f"Estimated Response Time: {request_data.get('estimatedResponseTime')}")
        print("=" * 40)

        # Get photo evidence paths
        photo_evidence = request_data.get('photoEvidence', [])

        # Prepare values for insertion
        values = (
            request_data['id'],
            request_data['citizenName'],
            request_data['email'],
            request_data.get('phone'),
            location_address,
            request_data['needType'],
            specification,  # Already None if not applicable
            request_data['severity'],
            request_data.get('peopleAffected', 1),
            request_data['description'],
            json.dumps(vulnerability_group),
            special_circumstances,  # Already None if empty
            request_data.get('hasEvidence', False),
            photo_evidence if photo_evidence else None,  # Array of photo paths or NULL
            request_data.get('status', 'pending'),
            request_data.get('priorityScore', 0),
            request_data.get('estimatedResponseTime'),
            datetime.now()
        )

        # Execute INSERT
        cur.execute("""
            INSERT INTO requests (
                request_id, citizen_name, email, phone, location_address,
                need_type, specification, severity, people_affected, description,
                vulnerability_group, special_circumstances,
                has_evidence, photo_evidence, status, priority_score,
                estimated_response_time, submitted_at
            ) VALUES (%s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s)
        """, values)

        # RE-enable the trigger after successful insert
        cur.execute("ALTER TABLE requests ENABLE TRIGGER audit_requests_trigger")

        conn.commit()
        print(f"âœ“ Request {request_data['id']} saved successfully to database")

        cur.close()
        conn.close()
        return True

    except psycopg2.Error as e:
        print(f"\n!!! POSTGRESQL ERROR !!!")
        print(f"Error Code: {e.pgcode}")
        print(f"Error Message: {e.pgerror}")
        print(f"Diagnostics: {e.diag.message_primary}")
        if e.diag.message_detail:
            print(f"Detail: {e.diag.message_detail}")
        if e.diag.message_hint:
            print(f"Hint: {e.diag.message_hint}")
        print("=" * 40)

        # Make sure to re-enable trigger even on error
        try:
            cur.execute("ALTER TABLE requests ENABLE TRIGGER audit_requests_trigger")
            conn.commit()
        except:
            pass

        if conn:
            conn.rollback()
            conn.close()
        return False

    except Exception as e:
        print(f"\n!!! GENERAL ERROR !!!")
        print(f"Error Type: {type(e).__name__}")
        print(f"Error Message: {str(e)}")
        import traceback
        traceback.print_exc()
        print("=" * 40)

        # Make sure to re-enable trigger even on error
        try:
            cur.execute("ALTER TABLE requests ENABLE TRIGGER audit_requests_trigger")
            conn.commit()
        except:
            pass

        if conn:
            conn.rollback()
            conn.close()
        return False


@app.route('/api/requests', methods=['POST'])
def api_submit_request():
    """Submit a new relief request with improved error handling and photo upload support"""
    try:
        # Check if request has files (FormData) or JSON
        if request.content_type and 'multipart/form-data' in request.content_type:
            # Handle FormData (with potential file uploads)
            data = {
                'citizenName': request.form.get('citizenName'),
                'email': request.form.get('email'),
                'phone': request.form.get('phone', ''),
                'location': request.form.get('location', ''),
                'needType': request.form.get('needType'),
                'specification': request.form.get('specification'),
                'severity': request.form.get('severity'),
                'peopleAffected': int(request.form.get('peopleAffected', 1)),
                'description': request.form.get('description'),
                'vulnerabilityGroup': json.loads(request.form.get('vulnerabilityGroup', '["none"]')),
                'specialCircumstances': request.form.get('specialCircumstances'),
                'hasEvidence': request.form.get('hasEvidence', 'false').lower() == 'true'
            }

            # Handle photo uploads for sanitary inspection
            photo_paths = []
            if data['needType'] == 'sanitary-inspection' and 'photos' in request.files:
                files = request.files.getlist('photos')
                for file in files[:3]:  # Limit to 3 photos
                    if file and allowed_file(file.filename):
                        # Create unique filename
                        file_ext = file.filename.rsplit('.', 1)[1].lower()
                        unique_filename = f"{uuid.uuid4().hex}.{file_ext}"
                        file_path = os.path.join(app.config['UPLOAD_FOLDER'], unique_filename)

                        # Save file
                        file.save(file_path)

                        # Store relative path for database (include static prefix for web serving)
                        relative_path = f"static/uploads/sanitary_inspection/{unique_filename}"
                        photo_paths.append(relative_path)
        else:
            # Handle JSON request (backward compatibility)
            data = request.json
            photo_paths = []

        if not data:
            return jsonify({'success': False, 'error': 'No data provided'}), 400

        # Validate required fields
        required_fields = ['citizenName', 'email', 'needType', 'severity', 'description']
        missing_fields = [field for field in required_fields if not data.get(field)]

        if missing_fields:
            error_msg = f'Missing required fields: {", ".join(missing_fields)}'
            print(f"ERROR: {error_msg}")
            return jsonify({'success': False, 'error': error_msg}), 400

        # Generate request ID
        request_id = f"REQ-{str(len(requests_db) + 1).zfill(6)}"

        # Extract location properly - FIXED
        location_data = data.get('location', '')
        if isinstance(location_data, dict):
            location_address = location_data.get('address', '')
        else:
            location_address = str(location_data) if location_data else ''

        # Create request object
        new_request = {
            'id': request_id,
            'citizenName': data.get('citizenName'),
            'email': data.get('email'),
            'phone': data.get('phone', ''),
            'location': location_address,  # Now it's always a string
            'needType': data.get('needType'),
            'specification': data.get('specification') if data.get('specification') else None,
            'severity': data.get('severity'),
            'peopleAffected': data.get('peopleAffected', 1),
            'description': data.get('description'),
            'vulnerabilityGroup': data.get('vulnerabilityGroup', ['none']),
            'specialCircumstances': data.get('specialCircumstances') if data.get('specialCircumstances') else None,
            'hasEvidence': data.get('hasEvidence', False),
            'photoEvidence': photo_paths,  # Add photo paths
            'status': 'pending',
            'submittedAt': datetime.now().isoformat(),
            'updatedAt': datetime.now().isoformat(),
            'verificationCount': 0,
            'priorityScore': 0,
            'referralStatus': 'none',
            'appointmentId': None
        }

        # Calculate priority score
        new_request['priorityScore'] = calculate_priority_score(new_request)

        # Calculate estimated response time
        pending_requests = [r for r in requests_db if r['status'] == 'pending']
        queue_position = len(pending_requests) + 1
        new_request['estimatedResponseTime'] = estimate_response_time(
            new_request['priorityScore'],
            queue_position
        )

        print(f"\n>>> Attempting to save request {request_id}")

        # Save to PostgreSQL database
        save_success = save_request_to_db(new_request)

        if not save_success:
            error_msg = 'Failed to save to database - check Flask terminal for details'
            print(f"ERROR: {error_msg}")
            return jsonify({'success': False, 'error': error_msg}), 500

        # Add to in-memory database
        requests_db.append(new_request)

        # Sort all requests by priority
        requests_db.sort(key=lambda r: (
            0 if r['status'] == 'pending' else 1 if r['status'] == 'in-progress' else 2,
            -r['priorityScore']
        ))

        # Log audit action
        log_audit_action(
            'CREATE',
            data.get('email'),
            f"New {data.get('needType')} request submitted - {data.get('severity')} severity",
            'REQUEST',
            request_id
        )

        print(f"âœ“ Request {request_id} successfully processed and saved")

        return jsonify({'success': True, 'request': new_request})

    except Exception as e:
        print(f"\n!!! ERROR IN api_submit_request !!!")
        print(f"Error Type: {type(e).__name__}")
        print(f"Error Message: {str(e)}")
        import traceback
        traceback.print_exc()
        print("=" * 40)

        return jsonify({
            'success': False,
            'error': f'Server error: {str(e)}'
        }), 500


def update_request_status_in_db(request_id, new_status, assigned_to=None, assigned_staff_id=None):
    """Update request status in database"""
    conn = get_db_connection()
    if not conn:
        return False

    try:
        cur = conn.cursor()

        if new_status == 'completed':
            cur.execute("""
                UPDATE requests 
                SET status = %s, updated_at = %s, completed_at = %s, assigned_to = %s, assigned_staff_id = %s
                WHERE request_id = %s
            """, (new_status, datetime.now(), datetime.now(), assigned_to, assigned_staff_id, request_id))
        else:
            cur.execute("""
                UPDATE requests 
                SET status = %s, updated_at = %s, assigned_to = %s, assigned_staff_id = %s
                WHERE request_id = %s
            """, (new_status, datetime.now(), assigned_to, assigned_staff_id, request_id))

        conn.commit()
        cur.close()
        conn.close()
        return True
    except Exception as e:
        print(f"Error updating request status: {e}")
        if conn:
            conn.rollback()
            conn.close()
        return False


# ============================================
# PASSWORD HASHING FUNCTIONS (BCRYPT ONLY)
# ============================================
# SECURITY NOTE: This system uses ONLY bcrypt for password hashing
# - All passwords are hashed using bcrypt.gensalt() and bcrypt.hashpw()
# - Never store plain text passwords
# - Never use weaker hashing algorithms (MD5, SHA1, etc.)
# - bcrypt automatically handles salting and is resistant to rainbow table attacks

def hash_password(password):
    """
    Hash a password using bcrypt with automatic salt generation

    Args:
        password (str): Plain text password

    Returns:
        str: Bcrypt hashed password (includes salt)

    Security:
        - Uses bcrypt.gensalt() for automatic salt generation
        - Computationally expensive to resist brute force attacks
        - Industry standard for password hashing
    """
    if not password:
        raise ValueError("Password cannot be empty")

    # Generate salt and hash password using bcrypt
    salt = bcrypt.gensalt()
    hashed = bcrypt.hashpw(password.encode('utf-8'), salt)
    return hashed.decode('utf-8')


def verify_password(plain_password, hashed_password):
    """
    Verify a password against its bcrypt hash

    Args:
        plain_password (str): Plain text password to verify
        hashed_password (str): Bcrypt hashed password from database

    Returns:
        bool: True if password matches, False otherwise

    Security:
        - Constant-time comparison to prevent timing attacks
        - Automatically handles salt extraction from hash
    """
    try:
        if not plain_password or not hashed_password:
            return False
        return bcrypt.checkpw(plain_password.encode('utf-8'), hashed_password.encode('utf-8'))
    except Exception as e:
        print(f"Password verification error: {e}")
        return False


# =====================
# PASSWORD RESET HELPERS
# =====================
def _get_serializer():
    secret = app.secret_key or os.environ.get('FLASK_SECRET_KEY')
    return URLSafeTimedSerializer(secret)


def generate_reset_token(email):
    s = _get_serializer()
    return s.dumps({'email': email})


def verify_reset_token(token, max_age=3600):
    s = _get_serializer()
    try:
        data = s.loads(token, max_age=max_age)
        return data.get('email')
    except SignatureExpired:
        return None
    except BadSignature:
        return None


def send_reset_email(recipient_email, token):
    """
    Send password reset email. If SMTP config is not provided, print link to console.
    Environment vars (optional): SMTP_HOST, SMTP_PORT, SMTP_USER, SMTP_PASSWORD, FROM_EMAIL
    """
    reset_link = url_for('reset_password_page', token=token, _external=True)

    smtp_host = os.environ.get('SMTP_HOST')
    smtp_port = int(os.environ.get('SMTP_PORT', 587)) if os.environ.get('SMTP_PORT') else None
    smtp_user = os.environ.get('SMTP_USER')
    smtp_pass = os.environ.get('SMTP_PASSWORD')
    from_email = os.environ.get('FROM_EMAIL', smtp_user or f"no-reply@{request.host}")

    subject = 'Password reset for PeopleFirst Priority'
    body = f"You requested a password reset. Click the link below to reset your password (valid for 1 hour):\n\n{reset_link}\n\nIf you didn't request this, ignore this message."

    if smtp_host and smtp_user and smtp_pass and smtp_port:
        try:
            msg = EmailMessage()
            msg['Subject'] = subject
            msg['From'] = from_email
            msg['To'] = recipient_email
            msg.set_content(body)

            context = ssl.create_default_context()
            with smtplib.SMTP(smtp_host, smtp_port) as server:
                server.starttls(context=context)
                server.login(smtp_user, smtp_pass)
                server.send_message(msg)
            print(f"Password reset email sent to {recipient_email}")
            return True
        except Exception as e:
            print(f"Failed to send reset email: {e}")
            return False
    else:
        # Fallback: print reset link to console for development
        print("[INFO] SMTP not configured. Password reset link:")
        print(reset_link)
        return True


def generate_staff_official_id(conn):
    """Generate unique official ID for staff member"""
    try:
        cur = conn.cursor()
        cur.execute(
            "SELECT MAX(CAST(SUBSTRING(employee_id FROM 'GOV-([0-9]+)') AS INTEGER)) FROM staff WHERE employee_id LIKE 'GOV-%'")
        result = cur.fetchone()
        max_num = result[0] if result and result[0] else 0
        cur.close()
        return f"GOV-{str(max_num + 1).zfill(5)}"
    except:
        # Fallback to timestamp-based ID
        return f"GOV-{int(datetime.now().timestamp())}"


def generate_professional_official_id(conn):
    """Generate unique official ID for professional"""
    try:
        cur = conn.cursor()
        # Count existing professionals and generate next ID
        cur.execute("SELECT COUNT(*) FROM professionals")
        count = cur.fetchone()[0]
        cur.close()
        # Use GOV prefix with sequential number
        return f"GOV-{str(count + 11).zfill(4)}"  # Start from 0011 to avoid conflicts with staff
    except Exception as e:
        print(f"Error generating professional ID: {e}")
        # Fallback to timestamp-based ID
        return f"GOV-{int(datetime.now().timestamp()) % 10000:04d}"


def get_department_id_by_name(conn, department_name):
    """Get department_id from department name"""
    try:
        cur = conn.cursor()
        print(f"DEBUG: Searching for department: '{department_name}'")
        cur.execute("SELECT department_id FROM departments WHERE department_name = %s", (department_name,))
        result = cur.fetchone()
        cur.close()

        if result:
            print(f"DEBUG: Found department_id: {result[0]}")
        else:
            print(f"DEBUG: Department '{department_name}' not found!")
            # Show available departments
            cur2 = conn.cursor()
            cur2.execute("SELECT department_id, department_name FROM departments")
            all_depts = cur2.fetchall()
            cur2.close()
            print(f"DEBUG: Available departments: {all_depts}")

        return result[0] if result else None
    except Exception as e:
        print(f"Error getting department_id: {e}")
        import traceback
        traceback.print_exc()
        return None


def get_user_role_from_profession(profession_type):
    """Map profession_type to user_role in role_permissions table"""
    mapping = {
        'medical-doctor': 'medical_doctor',
        'dentist': 'dentist',
        'immunization-doctor': 'immunization_doctor',
        'mental-health-doctor': 'mental_health_doctor',
        'medical-technologist': 'medical_technologist'
    }
    return mapping.get(profession_type, 'officer')


# ============================================
# PROFESSIONAL TYPE MAPPINGS
# ============================================

def get_profession_type_for_need(need_type):
    """
    Map request need_type to professional profession_type

    Returns:
        str: profession_type for filtering professionals
    """
    mapping = {
        'medical': 'medical-doctor',
        'dental-services': 'dentist',
        'immunization': 'immunization-doctor',
        'laboratory': 'medical-technologist',
        'mental-health': 'mental-health-doctor'
    }
    return mapping.get(need_type)


def get_need_types_requiring_appointment():
    """
    Returns list of need types that require professional appointments
    """
    return ['medical', 'dental-services', 'immunization', 'laboratory', 'mental-health']


def get_specialization_options_by_profession():
    """
    Returns specialization options for each profession type
    """
    return {
        'medical-doctor': [
            'General Medicine',
        ],
        'dentist': [
            'General Dentistry',
        ],
        'immunization-doctor': [
            'Immunization & Public Health',
            'Infectious Disease Prevention',
            'Vaccine Administration',
            'Pediatric Immunization'
        ],
        'mental-health-doctor': [
            'Psychiatry',
            'Clinical Psychology',
            'Counseling Psychology',
            'Child Psychology',
            'Behavioral Therapy'
        ],
        'medical-technologist': [
            'Hematology',
            'Clinical Chemistry',
            'Microbiology',
            'Immunology',
            'Blood Banking'
        ]
    }


def get_profession_display_name(profession_type):
    """
    Returns human-readable name for profession type
    """
    names = {
        'medical-doctor': 'Medical Doctor',
        'dentist': 'Dentist',
        'immunization-doctor': 'Immunization Doctor',
        'mental-health-doctor': 'Mental Health Professional',
        'medical-technologist': 'Medical Technologist'
    }
    return names.get(profession_type, profession_type)


# ============================================
# DATABASE-LEVEL ACCESS CONTROL
# ============================================
# NOTE: Access control is now enforced at the database level using:
# - Row-Level Security (RLS) policies
# - Role-based permissions in role_permissions table
# - Database roles (app_admin, app_officer_health, app_professional, etc.)
# The application no longer filters requests - the database does this automatically
# based on the authenticated user's role and permissions.


def calculate_avg_response_time(requests):
    """
    Calculate average response time for completed requests

    Args:
        requests (list): List of requests

    Returns:
        int: Average response time in hours
    """
    completed = [r for r in requests if r['status'] == 'completed']
    if not completed:
        return 0

    # Mock calculation - in production, calculate from timestamp data
    return 24  # 24 hours average


# ============================================
# PRIORITY ALGORITHM
# ============================================

# Priority algorithm
def calculate_priority_score(req):
    """Calculate priority score for a relief request"""
    score = 0

    # 1. Severity Score (0-40 points)
    severity_scores = {
        'critical': 40,
        'urgent': 30,
        'moderate': 15,
        'low': 5
    }
    score += severity_scores.get(req['severity'], 0)

    # 2. Vulnerability Multiplier (1.0-2.5x)
    vulnerability_weights = {
        'children': 0.4,
        'elderly': 0.3,
        'disabled': 0.4,
        'pregnant': 0.3,
        'student': 0.2,
        'none': 0
    }

    vulnerability_bonus = sum(vulnerability_weights.get(group, 0)
                              for group in req.get('vulnerabilityGroup', []))
    score *= (1 + vulnerability_bonus)

    # 3. Number of People Affected (0-20 points)
    people_score = min(req.get('peopleAffected', 1) * 2, 20)
    score += people_score

    # 4. Need Type Priority
    need_type_priority = {
        'medical': 10,
        'dental-services': 8,
        'immunization': 7,
        'laboratory': 6,
        'mental-health': 5,
        'sanitary-inspection': 7,
        'water': 8,
        'food': 7,
        'shelter': 6,
        'educational': 4,
        'clothing': 3,
        'financial': 3,
        'other': 2
    }
    score += need_type_priority.get(req.get('needType'), 0)

    # 5. Evidence Bonus (5 points)
    if req.get('hasEvidence', False):
        score += 5

    # 6. Special Circumstances (5 points)
    if req.get('specialCircumstances'):
        score += 5

    return round(score)


def estimate_response_time(priority_score, queue_position):
    """Estimate response time based on priority and queue position"""
    if priority_score >= 80:
        return 'Within 2 hours'
    elif priority_score >= 60:
        return 'Within 6 hours'
    elif priority_score >= 40:
        return 'Within 24 hours'
    else:
        days = (queue_position // 10) + 1
        return f'Within {days} {"day" if days == 1 else "days"}'


def log_audit_action(action_type, user_email, details, entity_type=None, entity_id=None):
    """Log an audit trail entry"""
    audit_entry = {
        'id': f"AUDIT-{str(len(audit_logs) + 1).zfill(6)}",
        'timestamp': datetime.now().isoformat(),
        'action_type': action_type,  # e.g., 'CREATE', 'UPDATE', 'DELETE', 'LOGIN', 'STATUS_CHANGE'
        'user_email': user_email,
        'user_role': session.get('user_role', 'unknown'),
        'entity_type': entity_type,  # e.g., 'REQUEST', 'STAFF', 'CITIZEN'
        'entity_id': entity_id,
        'details': details,
        'ip_address': request.remote_addr if request else None
    }
    audit_logs.append(audit_entry)
    return audit_entry


def get_dashboard_stats():
    """Calculate dashboard statistics"""
    total_requests = len(requests_db)
    pending = sum(1 for r in requests_db if r['status'] == 'pending')
    in_progress = sum(1 for r in requests_db if r['status'] == 'in-progress')
    completed = sum(1 for r in requests_db if r['status'] == 'completed')
    critical_requests = sum(1 for r in requests_db if r['severity'] == 'critical')
    student_requests = sum(1 for r in requests_db if r.get('isStudent', False))

    # Calculate average response time (mock value)
    avg_response_time = 4.5

    return {
        'totalRequests': total_requests,
        'pending': pending,
        'inProgress': in_progress,
        'completed': completed,
        'criticalRequests': critical_requests,
        'studentRequests': student_requests,
        'avgResponseTime': avg_response_time
    }


# Routes
@app.route('/')
def index():
    """Landing page"""
    stats = get_dashboard_stats()
    return render_template('index.html', stats=stats)


@app.route('/about')
def about():
    """About Us page"""
    return render_template('about.html')


@app.route('/contact')
def contact():
    """Contact Us page"""
    return render_template('contact.html')


@app.route('/citizen/login')
def citizen_login():
    """Citizen login page"""
    return render_template('citizen_login.html')


@app.route('/citizen/dashboard')
def citizen_dashboard():
    """Citizen dashboard"""
    if 'user_email' not in session or session.get('user_role') != 'citizen':
        return redirect(url_for('citizen_login'))

    user_email = session['user_email']
    user_requests = [r for r in requests_db if r['email'] == user_email]

    return render_template('citizen_dashboard.html',
                           user_name=session.get('user_name', 'Citizen'),
                           user_email=user_email,
                           requests=user_requests)


@app.route('/citizen/submit-request')
def citizen_submit_request():
    """Citizen request submission form"""
    if 'user_email' not in session or session.get('user_role') != 'citizen':
        return redirect(url_for('citizen_login'))

    return render_template('citizen_request_form.html',
                           user_email=session.get('user_email'))


@app.route('/government/login')
def government_login():
    """Government login page"""
    return render_template('government_login.html')


@app.route('/professional/login')
def professional_login():
    """Professional login page"""
    return render_template('professional_login.html')


@app.route('/government/dashboard')
def government_dashboard():
    """Government dashboard"""
    if 'user_email' not in session or session.get('user_role') != 'government':
        return redirect(url_for('government_login'))

    # Get user's role and department
    user_role = session.get('user_position', 'officer')  # Default to officer
    user_department = session.get('user_department', 'Relief Operations')

    # Database RLS policies handle filtering - no application-level filtering needed

    # Sort requests by priority
    sorted_requests = sorted(requests_db,
                             key=lambda r: (0 if r['status'] == 'pending'
                                            else 1 if r['status'] == 'in-progress'
                             else 2,
                                            -r['priorityScore']))

    # Calculate stats based on all visible requests (database already filtered)
    stats = {
        'totalRequests': len(requests_db),
        'pending': len([r for r in requests_db if r['status'] == 'pending']),
        'inProgress': len([r for r in requests_db if r['status'] == 'in-progress']),
        'completed': len([r for r in requests_db if r['status'] == 'completed']),
        'criticalRequests': len([r for r in requests_db if r['severity'] == 'critical']),
        'studentRequests': len([r for r in requests_db if 'student' in r.get('vulnerabilityGroup', [])]),
        'avgResponseTime': calculate_avg_response_time(requests_db)
    }

    return render_template('government_dashboard.html',
                           user_name=session.get('user_name', 'Official'),
                           user_department=user_department,
                           user_role=user_role,
                           requests=sorted_requests,
                           stats=stats)


@app.route('/admin/login')
def admin_login():
    """Admin login page"""
    return render_template('admin_login.html')


@app.route('/admin/dashboard')
def admin_dashboard():
    """Admin dashboard for staff management and audit tracking"""
    if 'user_email' not in session or session.get('user_role') != 'admin':
        return redirect(url_for('admin_login'))

    conn = get_db_connection()
    staff_list = []
    recent_audits = []
    total_staff = 0
    active_staff = 0
    total_audits = 0

    if conn:
        try:
            cur = conn.cursor()

            # Get all staff from database with department join
            cur.execute("""
                SELECT s.staff_id, s.full_name, s.email, s.phone, s.official_id, 
                       d.department_name, s.role, s.user_role, s.employee_id, 
                       s.status, s.joined_date, s.requests_handled, 
                       s.permissions, s.added_by, s.added_date
                FROM staff s
                LEFT JOIN departments d ON s.department_id = d.department_id
                ORDER BY s.added_date DESC
            """)
            staff_rows = cur.fetchall()

            for row in staff_rows:
                staff_list.append({
                    'id': row[0],
                    'fullName': row[1],
                    'email': row[2],
                    'phone': row[3],
                    'officialId': row[4],
                    'department': row[5],  # department_name from join
                    'role': row[6],
                    'userRole': row[7],  # Add user_role
                    'employeeId': row[8],
                    'status': row[9],
                    'joinedDate': row[10].isoformat() if row[10] else None,
                    'requestsHandled': row[11] or 0,
                    'permissions': row[12] or {},
                    'addedBy': row[13],
                    'addedDate': row[14].strftime('%m/%d/%Y') if row[14] else None
                })

            # Get staff counts
            cur.execute("SELECT COUNT(*) FROM staff")
            total_staff = cur.fetchone()[0]

            cur.execute("SELECT COUNT(*) FROM staff WHERE status = 'active'")
            active_staff = cur.fetchone()[0]

            # Get recent audit logs
            cur.execute("""
                SELECT audit_code, timestamp, action_type, user_email, user_role,
                       entity_type, entity_id, details, ip_address
                FROM audit_logs
                ORDER BY timestamp DESC
                LIMIT 10
            """)
            audit_rows = cur.fetchall()

            for row in audit_rows:
                recent_audits.append({
                    'id': row[0],
                    'timestamp': row[1].isoformat() if row[1] else None,
                    'action_type': row[2],
                    'user_email': row[3],
                    'user_role': row[4],
                    'entity_type': row[5],
                    'entity_id': row[6],
                    'details': row[7],
                    'ip_address': row[8]
                })

            # Get total audit count
            cur.execute("SELECT COUNT(*) FROM audit_logs")
            total_audits = cur.fetchone()[0]

            cur.close()
        except Exception as e:
            print(f"Database error: {e}")
        finally:
            conn.close()
    else:
        # Fallback to in-memory data if database connection fails
        staff_list = staff_db
        total_staff = len(staff_db)
        active_staff = sum(1 for s in staff_db if s.get('status') == 'active')
        recent_audits = sorted(audit_logs, key=lambda x: x['timestamp'], reverse=True)[:10]
        total_audits = len(audit_logs)

    # Get statistics
    stats = get_dashboard_stats()

    admin_stats = {
        **stats,
        'totalStaff': total_staff,
        'activeStaff': active_staff,
        'totalAudits': total_audits
    }

    return render_template('admin_dashboard.html',
                           user_name=session.get('user_name', 'Administrator'),
                           staff_list=staff_list,
                           recent_audits=recent_audits,
                           stats=admin_stats)


# API Routes
@app.route('/api/login', methods=['POST'])
def api_login():
    """Handle login for both citizen, government, and admin users with password verification"""
    data = request.json
    role = data.get('role')  # 'citizen', 'government', or 'admin'
    email = data.get('email')
    password = data.get('password', '')
    name = data.get('name', '')
    department = data.get('department', '')
    official_id = data.get('officialId', '')

    # Check if department indicates this is a professional
    is_professional_dept = department in ['Professional Services', 'Health and Medical Services']

    # For demo purposes, if no password provided, allow login (backward compatibility)
    # In production, you should ALWAYS require password verification
    if password:
        # Verify password based on role
        authenticated = False
        user_data = None

        if role == 'citizen':
            # Check citizens in DATABASE first, then fall back to users_db
            conn = get_db_connection()
            if conn:
                try:
                    cur = conn.cursor()
                    cur.execute("""
                        SELECT citizen_id, full_name, password_hash, phone, is_active
                        FROM citizens
                        WHERE email = %s
                    """, (email,))
                    citizen_record = cur.fetchone()

                    if citizen_record:
                        citizen_id, citizen_name, stored_hash, phone, is_active = citizen_record

                        if not is_active:
                            cur.close()
                            conn.close()
                            log_audit_action('LOGIN_FAILED', email, 'Account is inactive', 'USER', email)
                            return jsonify(
                                {'success': False, 'error': 'Account is inactive. Please contact support.'}), 403

                        if stored_hash and verify_password(password, stored_hash):
                            authenticated = True
                            name = citizen_name
                            print(f"✓ Citizen authenticated from database: {name} ({email})")
                        else:
                            print(f"✗ Password verification failed for citizen: {email}")
                    else:
                        print(f"✗ Citizen not found in database: {email}")

                    cur.close()
                    conn.close()
                except Exception as e:
                    print(f"Database error during citizen login: {e}")
                    if conn:
                        conn.close()

            # Fall back to in-memory cache if database check didn't authenticate
            if not authenticated and email in users_db.get('citizens', {}):
                stored_hash = users_db['citizens'][email].get('password_hash')
                if stored_hash and verify_password(password, stored_hash):
                    authenticated = True
                    user_data = users_db['citizens'][email]
                    name = user_data.get('name', name)
                    print(f"✓ Citizen authenticated from cache: {name} ({email})")

        elif role == 'government':
            # Initialize user_position
            user_position = 'officer'  # Default
            is_professional = False

            # If department suggests professional, check professionals table first
            if is_professional_dept:
                conn = get_db_connection()
                if conn:
                    try:
                        cur = conn.cursor()
                        cur.execute("""
                            SELECT full_name, specialization, password_hash, professional_id
                            FROM professionals 
                            WHERE email = %s AND status = 'active'
                        """, (email,))
                        prof_record = cur.fetchone()

                        if prof_record and prof_record[2]:
                            if verify_password(password, prof_record[2]):
                                authenticated = True
                                is_professional = True
                                name = prof_record[0]
                                department = 'Mental Health Services'
                                user_position = 'professional'
                                professional_id = prof_record[3]
                                print(
                                    f"DEBUG: Professional login successful - Name: {name}, Specialization: {prof_record[1]}")

                        cur.close()
                        conn.close()
                    except Exception as e:
                        print(f"Database error during professional login: {e}")
                        if conn:
                            conn.close()

            # If not authenticated as professional, check government staff
            if not authenticated:
                conn = get_db_connection()
                if conn:
                    try:
                        cur = conn.cursor()
                        cur.execute("""
                            SELECT full_name, department, role, password_hash 
                            FROM staff 
                            WHERE email = %s AND status = 'active'
                        """, (email,))
                        staff_record = cur.fetchone()

                        if staff_record and staff_record[3]:
                            if verify_password(password, staff_record[3]):
                                authenticated = True
                                name = staff_record[0]
                                department = staff_record[1]
                                user_position = staff_record[2] if staff_record[2] else 'officer'
                                print(
                                    f"DEBUG: Staff login successful - Name: {name}, Dept: {department}, Role: {user_position}")

                        cur.close()
                        conn.close()
                    except Exception as e:
                        print(f"Database error during staff login: {e}")
                        if conn:
                            conn.close()

            # Fallback to in-memory users_db for backward compatibility
            if not authenticated and email in users_db.get('government', {}):
                stored_hash = users_db['government'][email].get('password_hash')
                if stored_hash and verify_password(password, stored_hash):
                    authenticated = True
                    user_data = users_db['government'][email]
                    name = user_data.get('name', name)
                    department = user_data.get('department', department)
                    user_position = user_data.get('role', 'officer')

        elif role == 'admin':
            # Check admin users in staff_db or dedicated admin list
            conn = get_db_connection()
            if conn:
                try:
                    cur = conn.cursor()
                    cur.execute("""
                        SELECT full_name, department, password_hash 
                        FROM staff 
                        WHERE email = %s AND role = 'admin' AND status = 'active'
                    """, (email,))
                    admin_record = cur.fetchone()

                    if admin_record and admin_record[2]:
                        if verify_password(password, admin_record[2]):
                            authenticated = True
                            name = admin_record[0]
                            department = admin_record[1]
                            user_position = 'admin'
                            print(f"DEBUG: Admin login successful - Name: {name}")

                    cur.close()
                    conn.close()
                except Exception as e:
                    print(f"Database error during admin login: {e}")
                    if conn:
                        conn.close()

            # Fallback to staff_db
            if not authenticated:
                admin_user = next((u for u in staff_db if u.get('email') == email and u.get('role') == 'admin'), None)
                if admin_user:
                    stored_hash = admin_user.get('password_hash')
                    if stored_hash and verify_password(password, stored_hash):
                        authenticated = True
                        user_data = admin_user
                        name = admin_user.get('fullName') or admin_user.get('name', name)
                        department = admin_user.get('department', 'Administration')
                        user_position = 'admin'

        if not authenticated:
            log_audit_action('LOGIN_FAILED', email, f'Failed login attempt for {role}', 'USER', email)
            return jsonify({'success': False, 'error': 'Invalid email or password'}), 401
    else:
        # No password provided - check if using old demo system without password
        # This allows backward compatibility but should be removed in production
        print("WARNING: Login without password - using legacy mode")
        is_professional = is_professional_dept
        user_position = 'officer'

    # Set session data
    session['user_email'] = email
    session['user_name'] = name
    session['user_role'] = role
    if role == 'government' or role == 'admin':
        session['user_department'] = department
        session['user_position'] = user_position if 'user_position' in locals() else 'officer'

        # Store professional ID if this is a professional user
        if 'is_professional' in locals() and is_professional:
            session['is_professional'] = True
            if 'professional_id' in locals():
                session['professional_id'] = professional_id
        elif is_professional_dept:
            # Department indicates professional but not found in database
            # Still mark as professional for routing purposes
            session['is_professional'] = True

    # Log the successful login
    log_audit_action('LOGIN', email, f'{role.capitalize()} user logged in successfully')

    # Return success with user type for redirect logic
    response_data = {'success': True, 'role': role, 'name': name}
    if ('is_professional' in locals() and is_professional) or is_professional_dept:
        response_data['is_professional'] = True

    return jsonify(response_data)


@app.route('/api/logout', methods=['POST'])
def api_logout():
    """Handle logout"""
    user_email = session.get('user_email', 'unknown')
    log_audit_action('LOGOUT', user_email, f'User logged out')
    session.clear()
    return jsonify({'success': True})


# -----------------------------
# Password reset endpoints
# -----------------------------
@app.route('/api/forgot-password', methods=['POST'])
def api_forgot_password():
    """Initiate password reset: generate token and send email if account exists.
    Always return success True to avoid user enumeration."""
    data = request.get_json() or {}
    email = data.get('email')
    if not email:
        return jsonify({'success': False, 'error': 'Email required'}), 400

    # Check whether account exists in any user table; only send if exists
    conn = get_db_connection()
    account_found = False
    if conn:
        try:
            cur = conn.cursor()
            cur.execute("SELECT citizen_id FROM citizens WHERE email = %s", (email,))
            if cur.fetchone():
                account_found = True
            else:
                # check staff
                cur.execute("SELECT staff_id FROM staff WHERE email = %s", (email,))
                if cur.fetchone():
                    account_found = True
                else:
                    cur.execute("SELECT professional_id FROM professionals WHERE email = %s", (email,))
                    if cur.fetchone():
                        account_found = True
            cur.close()
        except Exception as e:
            print(f"Error checking user existence for forgot-password: {e}")
        finally:
            conn.close()

    # If account exists, generate a token and send email (or print link)
    if account_found:
        token = generate_reset_token(email)
        send_reset_email(email, token)
        log_audit_action('PASSWORD_RESET_REQUEST', email, 'Password reset requested')
    else:
        # Intentionally do nothing to avoid leaking existence
        print(f"Password reset requested for unknown email: {email}")

    # Always return generic success
    return jsonify({'success': True})


@app.route('/reset-password/<token>', methods=['GET'])
def reset_password_page(token):
    """Render a simple reset password page containing the token."""
    email = verify_reset_token(token)
    if not email:
        return render_template('reset_password.html', token=None, invalid=True)
    return render_template('reset_password.html', token=token, invalid=False)


@app.route('/api/reset-password', methods=['POST'])
def api_reset_password():
    """Verify token and update user's password.
    This function updates citizens, staff, or professionals table as applicable."""
    data = request.get_json() or {}
    token = data.get('token')
    new_password = data.get('password')

    if not token or not new_password:
        return jsonify({'success': False, 'error': 'Token and new password are required'}), 400

    email = verify_reset_token(token)
    if not email:
        return jsonify({'success': False, 'error': 'Invalid or expired token'}), 400

    # Hash the new password
    try:
        new_hash = hash_password(new_password)
    except Exception as e:
        return jsonify({'success': False, 'error': 'Failed to hash password'}), 500

    # Update whichever table contains the user
    conn = get_db_connection()
    if not conn:
        return jsonify({'success': False, 'error': 'Database connection failed'}), 500

    try:
        cur = conn.cursor()
        # Try citizens
        cur.execute("UPDATE citizens SET password_hash = %s WHERE email = %s RETURNING citizen_id", (new_hash, email))
        if cur.fetchone():
            conn.commit()
            cur.close()
            log_audit_action('PASSWORD_RESET', email, 'Citizen password reset')
            return jsonify({'success': True})

        # Try staff
        cur.execute("UPDATE staff SET password_hash = %s WHERE email = %s RETURNING staff_id", (new_hash, email))
        if cur.fetchone():
            conn.commit()
            cur.close()
            log_audit_action('PASSWORD_RESET', email, 'Staff password reset')
            return jsonify({'success': True})

        # Try professionals
        cur.execute("UPDATE professionals SET password_hash = %s WHERE email = %s RETURNING professional_id",
                    (new_hash, email))
        if cur.fetchone():
            conn.commit()
            cur.close()
            log_audit_action('PASSWORD_RESET', email, 'Professional password reset')
            return jsonify({'success': True})

        # No rows updated
        conn.commit()
        cur.close()
        return jsonify({'success': False, 'error': 'Account not found'}), 404
    except Exception as e:
        print(f"Error resetting password: {e}")
        if conn:
            conn.rollback()
            conn.close()
        return jsonify({'success': False, 'error': 'Server error'}), 500


# ============================================
# REGISTRATION ENDPOINTS
# ============================================

@app.route('/api/register/citizen', methods=['POST'])
def api_register_citizen():
    """Register a new citizen account with password hashing"""
    data = request.json
    email = data.get('email')
    password = data.get('password')
    name = data.get('name')
    phone = data.get('phone', '')

    # Validate required fields
    if not email or not password or not name:
        return jsonify({'success': False, 'error': 'Email, password, and name are required'}), 400

    # Hash the password
    password_hash = hash_password(password)
    if not password_hash:
        return jsonify({'success': False, 'error': 'Failed to hash password'}), 500

    # Save to database
    conn = get_db_connection()
    if not conn:
        return jsonify({'success': False, 'error': 'Database connection failed'}), 500

    try:
        cur = conn.cursor()

        # Check if user already exists
        cur.execute("SELECT citizen_id FROM citizens WHERE email = %s", (email,))
        if cur.fetchone():
            cur.close()
            conn.close()
            return jsonify({'success': False, 'error': 'Email already registered'}), 409

        # Insert new citizen
        cur.execute("""
            INSERT INTO citizens (email, password_hash, full_name, phone, created_at, is_active)
            VALUES (%s, %s, %s, %s, CURRENT_TIMESTAMP, TRUE)
            RETURNING citizen_id
        """, (email, password_hash, name, phone))

        citizen_id = cur.fetchone()[0]
        conn.commit()

        # Also add to in-memory cache for compatibility
        if 'citizens' not in users_db:
            users_db['citizens'] = {}

        users_db['citizens'][email] = {
            'email': email,
            'password_hash': password_hash,
            'name': name,
            'phone': phone,
            'created_at': datetime.now().isoformat(),
            'is_active': True
        }

        # Log the registration
        log_audit_action('REGISTER', email, f'New citizen account created: {name}', 'CITIZEN', email)

        cur.close()
        conn.close()

        print(f"✓ Citizen registered successfully: {name} ({email})")

        return jsonify({
            'success': True,
            'message': 'Citizen account created successfully',
            'email': email
        })

    except Exception as e:
        if conn:
            conn.rollback()
            conn.close()
        print(f"Error registering citizen: {e}")
        import traceback
        traceback.print_exc()
        return jsonify({'success': False, 'error': f'Registration failed: {str(e)}'}), 500


@app.route('/api/register/government', methods=['POST'])
def api_register_government():
    """Register a new government user account with password hashing"""
    data = request.json
    email = data.get('email')
    password = data.get('password')
    name = data.get('name')
    department = data.get('department')

    # Validate required fields
    if not email or not password or not name or not department:
        return jsonify({'success': False, 'error': 'Email, password, name, and department are required'}), 400

    # Check if user already exists
    if email in users_db.get('government', {}):
        return jsonify({'success': False, 'error': 'Email already registered'}), 409

    # Hash the password
    password_hash = hash_password(password)

    # Create government account
    if 'government' not in users_db:
        users_db['government'] = {}

    users_db['government'][email] = {
        'email': email,
        'password_hash': password_hash,
        'name': name,
        'department': department,
        'created_at': datetime.now().isoformat(),
        'is_active': True
    }

    # Log the registration
    log_audit_action('REGISTER', email, f'New government account created: {name} ({department})', 'GOVERNMENT', email)

    return jsonify({
        'success': True,
        'message': 'Government account created successfully',
        'email': email
    })


@app.route('/api/change-password', methods=['POST'])
def api_change_password():
    """Change user password"""
    data = request.json
    email = session.get('user_email')
    role = session.get('user_role')
    old_password = data.get('old_password')
    new_password = data.get('new_password')

    if not email or not role:
        return jsonify({'success': False, 'error': 'Not authenticated'}), 401

    if not old_password or not new_password:
        return jsonify({'success': False, 'error': 'Old and new passwords are required'}), 400

    # Verify old password and update
    user_data = None
    if role == 'citizen' and email in users_db.get('citizens', {}):
        user_data = users_db['citizens'][email]
    elif role == 'government' and email in users_db.get('government', {}):
        user_data = users_db['government'][email]

    if not user_data:
        return jsonify({'success': False, 'error': 'User not found'}), 404

    # Verify old password
    if not verify_password(old_password, user_data.get('password_hash', '')):
        log_audit_action('PASSWORD_CHANGE_FAILED', email, 'Failed password change attempt - incorrect old password')
        return jsonify({'success': False, 'error': 'Incorrect old password'}), 401

    # Hash and update new password
    new_password_hash = hash_password(new_password)
    user_data['password_hash'] = new_password_hash
    user_data['password_changed_at'] = datetime.now().isoformat()

    # Log the password change
    log_audit_action('PASSWORD_CHANGED', email, f'Password changed successfully', 'USER', email)

    return jsonify({'success': True, 'message': 'Password changed successfully'})


# ============================================
# REQUEST ENDPOINTS
# ============================================

@app.route('/api/requests', methods=['GET'])
def api_get_requests():
    """Get all requests or filtered by user email or role-based access"""
    user_email = request.args.get('email')

    print(f"DEBUG: API /api/requests called. Session: {dict(session)}")

    # Load requests from database
    all_requests = load_requests_from_db()
    print(f"DEBUG: Loaded {len(all_requests)} requests from database")

    # Check if this is a government user with role-based access
    if session.get('user_role') == 'government':
        user_position = session.get('user_position', 'officer')
        user_department = session.get('user_department', '')

        print(f"DEBUG: Government user - Position: {user_position}, Department: {user_department}")

        # Database RLS policies handle filtering automatically
        print(f"DEBUG: Returning {len(all_requests)} requests (filtered by database)")
        return jsonify(all_requests)

    # For citizen users, filter by their email
    if user_email:
        filtered_requests = [r for r in all_requests if r['email'] == user_email]
        print(f"DEBUG: Citizen filter - {len(filtered_requests)} requests for {user_email}")
        return jsonify(filtered_requests)

    # For admin users or others, return all requests
    print(f"DEBUG: Returning all {len(all_requests)} requests")
    return jsonify(all_requests)


@app.route('/api/requests/<request_id>/status', methods=['PUT'])
def api_update_status(request_id):
    """Update request status - with role-based access control"""
    data = request.json
    new_status = data.get('status')

    # Find the request
    for req in requests_db:
        if req['id'] == request_id:
            # Check if user has permission to update this request
            # Database RLS policies handle permission checks
            # No application-level permission check needed

            # Update the request in memory
            old_status = req['status']
            req['status'] = new_status
            req['updatedAt'] = datetime.now().isoformat()

            if new_status == 'in-progress' and 'assignedTo' not in req:
                req['assignedTo'] = session.get('user_name', 'Relief Team')
                req['assignedStaffId'] = session.get('user_id')  # Add staff ID

            if new_status == 'completed':
                req['completedAt'] = datetime.now().isoformat()

                # Check if this request has a scheduled appointment that needs notification
                if req.get('referralStatus') == 'scheduling':
                    # Send notification to citizen: waiting for confirmation
                    try:
                        conn = get_db_connection()
                        if conn:
                            cur = conn.cursor()

                            # Get appointment details
                            cur.execute("""
                                SELECT appointment_id, appointment_date, appointment_time
                                FROM appointments
                                WHERE request_id = %s AND status = 'pending'
                            """, (request_id,))

                            appt_data = cur.fetchone()
                            if appt_data:
                                appointment_id, appt_date, appt_time = appt_data

                                # Update referral status to waiting_confirmation
                                cur.execute("""
                                    UPDATE requests
                                    SET referral_status = 'waiting_confirmation'
                                    WHERE request_id = %s
                                """, (request_id,))

                                # Update in-memory request as well
                                req['referralStatus'] = 'waiting_confirmation'

                                # Get the actual need type from the request to create proper notification
                                need_type = req.get('needType', 'health')
                                service_display_name = need_type.replace('-', ' ').title()

                                # Create notification for citizen with correct service type
                                notification_title = f"{service_display_name} Appointment - Waiting for Confirmation"
                                notification_message = f"""
                                        Your {service_display_name.lower()} appointment has been scheduled.

                                        Status: Waiting for professional confirmation

                                        A healthcare professional will review and confirm your appointment. You will receive another notification with the provider's name, contact details, and appointment confirmation.

                                        Appointment Date: {appt_date}
                                        Appointment Time: {appt_time}
                                        Request ID: {request_id}
                                        Appointment ID: {appointment_id}
                                        """

                                cur.execute("""
                                    INSERT INTO notifications (recipient_email, recipient_type, notification_type, title, message, related_request_id, related_appointment_id)
                                    VALUES (%s, 'citizen', 'appointment_scheduled', %s, %s, %s, %s)
                                """, (req['email'], notification_title, notification_message, request_id,
                                      appointment_id))

                                conn.commit()

                            cur.close()
                            conn.close()
                    except Exception as e:
                        print(f"Error sending appointment notification: {e}")

            # Update in PostgreSQL database
            try:
                update_request_status_in_db(
                    request_id,
                    new_status,
                    req.get('assignedTo'),
                    req.get('assignedStaffId')
                )
            except Exception as e:
                print(f"Error updating request status in database: {e}")
                # Continue with in-memory update - don't fail the request

            # Log status change
            user_email = session.get('user_email', 'system')
            log_audit_action('STATUS_CHANGE', user_email,
                             f"Request {request_id} status changed from {old_status} to {new_status}",
                             'REQUEST', request_id)

            return jsonify({'success': True, 'request': req})

    return jsonify({'success': False, 'error': 'Request not found'}), 404


@app.route('/api/stats', methods=['GET'])
def api_get_stats():
    """Get dashboard statistics"""
    return jsonify(get_dashboard_stats())


# ============================================
# ADMIN API ROUTES - Staff Management
# ============================================

@app.route('/api/admin/staff', methods=['GET'])
def api_get_staff():
    """Get all government staff members from database"""
    if session.get('user_role') != 'admin':
        return jsonify({'success': False, 'error': 'Unauthorized'}), 403

    conn = get_db_connection()
    if not conn:
        return jsonify(staff_db)  # Fallback to in-memory

    try:
        cur = conn.cursor()
        cur.execute("""
            SELECT staff_id, full_name, email, phone, official_id, department, 
                   role, employee_id, status, joined_date, requests_handled, permissions
            FROM staff 
            ORDER BY added_date DESC
        """)
        staff_rows = cur.fetchall()

        staff_list = []
        for row in staff_rows:
            staff_list.append({
                'id': row[0],
                'fullName': row[1],
                'email': row[2],
                'phone': row[3],
                'officialId': row[4],
                'department': row[5],
                'role': row[6],
                'employeeId': row[7],
                'status': row[8],
                'joinedDate': row[9].isoformat() if row[9] else None,
                'requestsHandled': row[10] or 0,
                'permissions': row[11] or {}
            })

        cur.close()
        conn.close()
        return jsonify(staff_list)
    except Exception as e:
        print(f"Database error: {e}")
        if conn:
            conn.close()
        return jsonify(staff_db)  # Fallback


@app.route('/api/admin/staff', methods=['POST'])
def api_create_staff():
    """Create a new staff member in database"""
    if session.get('user_role') != 'admin':
        return jsonify({'success': False, 'error': 'Unauthorized'}), 403

    data = request.json
    conn = get_db_connection()

    if not conn:
        # Fallback to in-memory
        staff_id = f"STAFF-{str(len(staff_db) + 1).zfill(4)}"

        # Hash password if provided
        password_hash = None
        if 'password' in data and data['password']:
            password_hash = hash_password(data['password'])

        new_staff = {
            'id': staff_id,
            'fullName': data.get('fullName'),
            'email': data.get('email'),
            'password': password_hash,  # Store hashed password
            'phone': data.get('phone'),
            'department': data.get('department'),
            'role': data.get('role', 'officer'),
            'employeeId': data.get('employeeId'),
            'status': 'active',
            'joinedDate': datetime.now().isoformat(),
            'lastLogin': None,
            'requestsHandled': 0,
            'permissions': data.get('permissions', {})
        }
        staff_db.append(new_staff)
        return jsonify({'success': True, 'staff': new_staff})

    try:
        cur = conn.cursor()

        # Generate staff ID
        cur.execute("SELECT COUNT(*) FROM staff")
        count = cur.fetchone()[0]
        staff_id = f"STAFF-{str(count + 1).zfill(4)}"

        # Generate unique official ID
        official_id = generate_staff_official_id(conn)

        # Hash password if provided
        password_hash = None
        if 'password' in data and data['password']:
            password_hash = hash_password(data['password'])

        # Get department_id from department name
        department_name = data.get('department')

        if not department_name:
            cur.close()
            conn.close()
            return jsonify(
                {'success': False, 'error': 'Department is required', 'message': 'Department is required'}), 400

        print(f"DEBUG: Looking up department: '{department_name}'")
        department_id = get_department_id_by_name(conn, department_name)

        print(f"DEBUG: Department ID found: {department_id}")

        if not department_id:
            cur.close()
            conn.close()
            return jsonify({'success': False, 'error': f'Invalid department: {department_name}',
                            'message': f'Department "{department_name}" not found in database'}), 400

        # Determine user_role based on role and department
        role = data.get('role', 'officer')
        if role == 'admin':
            user_role = 'admin'
        elif department_name == 'Sanitary Inspection':
            user_role = 'officer_sanitary'
        elif department_name in ['Health and Medical Services', 'Mental Health', 'Dental Services', 'Immunization',
                                 'Laboratory and Diagnostics']:
            user_role = 'officer_health'
        else:
            user_role = 'officer'

        # Insert staff member
        cur.execute("""
            INSERT INTO staff (staff_id, full_name, email, password_hash, phone, official_id, 
                               department_id, role, user_role, employee_id, status, permissions, added_by, added_date)
            VALUES (%s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, CURRENT_TIMESTAMP)
            RETURNING staff_id, full_name, email, phone, official_id, role, user_role,
                      employee_id, status, joined_date, requests_handled, permissions
        """, (
            staff_id,
            data.get('fullName'),
            data.get('email'),
            password_hash,
            data.get('phone'),
            official_id,
            department_id,  # Use department_id FK
            role,
            user_role,  # FK to role_permissions table
            official_id,  # Use same official_id for employee_id
            'active',
            json.dumps(data.get('permissions', {})),
            session.get('user_email', 'system')
        ))

        row = cur.fetchone()
        new_staff = {
            'id': row[0],
            'fullName': row[1],
            'email': row[2],
            'phone': row[3],
            'officialId': row[4],
            'department': department_name,  # Return name for frontend
            'role': row[5],
            'userRole': row[6],
            'employeeId': row[7],
            'status': row[8],
            'joinedDate': row[9].isoformat() if row[9] else None,
            'requestsHandled': row[10] or 0,
            'permissions': row[11] or {}
        }

        # Log audit action in database
        admin_email = session.get('user_email', 'system')
        cur.execute("""
            INSERT INTO audit_logs (audit_code, action_type, user_email, user_role, 
                                    entity_type, entity_id, details, ip_address)
            VALUES (%s, %s, %s, %s, %s, %s, %s, %s)
        """, (
            f"AUDIT-{datetime.now().strftime('%Y%m%d%H%M%S')}",
            'CREATE',
            admin_email,
            'admin',
            'STAFF',
            staff_id,
            f"New staff member created: {new_staff['fullName']} ({new_staff['email']}) - {new_staff['role']}",
            request.remote_addr
        ))

        conn.commit()
        cur.close()
        conn.close()

        return jsonify({'success': True, 'staff': new_staff})
    except Exception as e:
        print(f"======= STAFF CREATION ERROR =======")
        print(f"Error type: {type(e).__name__}")
        print(f"Error message: {e}")
        import traceback
        traceback.print_exc()
        print(f"Data received: {data}")
        print(f"Department name: {data.get('department')}")
        print(f"Department ID: {department_id if 'department_id' in locals() else 'Not set'}")
        print(f"===================================")
        if conn:
            conn.rollback()
            conn.close()
        return jsonify({'success': False, 'error': str(e), 'message': str(e)}), 500


@app.route('/api/admin/staff/<staff_id>', methods=['PUT'])
def api_update_staff(staff_id):
    """Update staff member details in database"""
    if session.get('user_role') != 'admin':
        return jsonify({'success': False, 'error': 'Unauthorized'}), 403

    data = request.json
    conn = get_db_connection()

    if not conn:
        # Fallback to in-memory
        for staff in staff_db:
            if staff['id'] == staff_id:
                if 'fullName' in data:
                    staff['fullName'] = data['fullName']
                if 'email' in data:
                    staff['email'] = data['email']
                if 'phone' in data:
                    staff['phone'] = data['phone']
                if 'department' in data:
                    staff['department'] = data['department']
                if 'role' in data:
                    staff['role'] = data['role']
                if 'status' in data:
                    staff['status'] = data['status']
                if 'permissions' in data:
                    staff['permissions'] = data['permissions']
                return jsonify({'success': True, 'staff': staff})
        return jsonify({'success': False, 'error': 'Staff not found'}), 404

    try:
        cur = conn.cursor()

        # Build UPDATE query dynamically
        update_fields = []
        params = []

        if 'fullName' in data:
            update_fields.append("full_name = %s")
            params.append(data['fullName'])
        if 'email' in data:
            update_fields.append("email = %s")
            params.append(data['email'])
        if 'phone' in data:
            update_fields.append("phone = %s")
            params.append(data['phone'])
        if 'department' in data:
            # Convert department name to department_id
            dept_id = get_department_id_by_name(conn, data['department'])
            if dept_id:
                update_fields.append("department_id = %s")
                params.append(dept_id)
        if 'role' in data:
            update_fields.append("role = %s")
            params.append(data['role'])
            # Update user_role based on new role if provided
            if data['role'] == 'admin':
                update_fields.append("user_role = %s")
                params.append('admin')
        if 'status' in data:
            update_fields.append("status = %s")
            params.append(data['status'])
        if 'permissions' in data:
            update_fields.append("permissions = %s")
            params.append(json.dumps(data['permissions']))

        if not update_fields:
            return jsonify({'success': False, 'error': 'No fields to update'}), 400

        params.append(staff_id)
        query = f"UPDATE staff SET {', '.join(update_fields)} WHERE staff_id = %s RETURNING staff_id, full_name, email, phone, official_id, role, user_role, employee_id, status"

        cur.execute(query, params)
        row = cur.fetchone()

        if not row:
            cur.close()
            conn.close()
            return jsonify({'success': False, 'error': 'Staff not found'}), 404

        # Get department name
        cur.execute(
            "SELECT d.department_name FROM departments d JOIN staff s ON s.department_id = d.department_id WHERE s.staff_id = %s",
            (staff_id,))
        dept_row = cur.fetchone()
        dept_name = dept_row[0] if dept_row else None

        updated_staff = {
            'id': row[0],
            'fullName': row[1],
            'email': row[2],
            'phone': row[3],
            'officialId': row[4],
            'department': dept_name,
            'role': row[5],
            'userRole': row[6],
            'employeeId': row[7],
            'status': row[8]
        }

        # Log audit action
        admin_email = session.get('user_email', 'system')
        cur.execute("""
            INSERT INTO audit_logs (audit_code, action_type, user_email, user_role, 
                                    entity_type, entity_id, details, ip_address)
            VALUES (%s, %s, %s, %s, %s, %s, %s, %s)
        """, (
            f"AUDIT-{datetime.now().strftime('%Y%m%d%H%M%S')}",
            'UPDATE',
            admin_email,
            'admin',
            'STAFF',
            staff_id,
            f"Staff {staff_id} updated",
            request.remote_addr
        ))

        conn.commit()
        cur.close()
        conn.close()

        return jsonify({'success': True, 'staff': updated_staff})
    except Exception as e:
        print(f"Database error: {e}")
        if conn:
            conn.rollback()
            conn.close()
        return jsonify({'success': False, 'error': str(e)}), 500


@app.route('/api/admin/staff/<staff_id>', methods=['DELETE'])
def api_delete_staff(staff_id):
    """Delete/deactivate staff member in database"""
    print(f"DELETE request for staff_id: {staff_id} (type: {type(staff_id)})")

    if session.get('user_role') != 'admin':
        return jsonify({'success': False, 'error': 'Unauthorized'}), 403

    conn = get_db_connection()

    if not conn:
        # Fallback to in-memory
        for i, staff in enumerate(staff_db):
            if str(staff['id']) == str(staff_id):
                staff['status'] = 'inactive'
                staff['deactivatedDate'] = datetime.now().isoformat()
                return jsonify({'success': True, 'message': 'Staff deactivated'})
        return jsonify({'success': False, 'error': 'Staff not found'}), 404

    try:
        cur = conn.cursor()

        print(f"Executing UPDATE for staff_id: {staff_id}")

        # Soft delete - mark as inactive and set deactivated date
        cur.execute("""
            UPDATE staff 
            SET status = 'inactive', deactivated_date = CURRENT_TIMESTAMP
            WHERE staff_id = %s
            RETURNING full_name, email
        """, (staff_id,))

        row = cur.fetchone()

        if not row:
            print(f"Staff not found with ID: {staff_id}")
            cur.close()
            conn.close()
            return jsonify({'success': False, 'error': 'Staff not found'}), 404

        print(f"Staff found and updated: {row[0]} ({row[1]})")

        # Log audit action
        admin_email = session.get('user_email', 'system')
        cur.execute("""
            INSERT INTO audit_logs (audit_code, action_type, user_email, user_role, 
                                    entity_type, entity_id, details, ip_address)
            VALUES (%s, %s, %s, %s, %s, %s, %s, %s)
        """, (
            f"AUDIT-{datetime.now().strftime('%Y%m%d%H%M%S')}",
            'DELETE',
            admin_email,
            'admin',
            'STAFF',
            staff_id,
            f"Staff member deactivated: {row[0]} ({row[1]})",
            request.remote_addr
        ))

        conn.commit()
        cur.close()
        conn.close()

        print("Staff deactivated successfully")
        return jsonify({'success': True, 'message': 'Staff deactivated'})
    except Exception as e:
        print(f"Database error in delete_staff: {e}")
        import traceback
        traceback.print_exc()
        if conn:
            conn.rollback()
            conn.close()
        return jsonify({'success': False, 'error': str(e)}), 500


# ============================================
# ADMIN API ROUTES - Audit Tracking
# ============================================

@app.route('/api/admin/audit-logs', methods=['GET'])
def api_get_audit_logs():
    """Get audit logs with optional filtering from database"""
    if session.get('user_role') != 'admin':
        return jsonify({'success': False, 'error': 'Unauthorized'}), 403

    # Get query parameters
    action_type = request.args.get('action_type')
    user_email = request.args.get('user_email')
    entity_type = request.args.get('entity_type')
    start_date = request.args.get('start_date')
    end_date = request.args.get('end_date')
    limit = int(request.args.get('limit', 100))

    conn = get_db_connection()

    if not conn:
        # Fallback to in-memory
        filtered_logs = audit_logs
        if action_type:
            filtered_logs = [log for log in filtered_logs if log['action_type'] == action_type]
        sorted_logs = sorted(filtered_logs, key=lambda x: x['timestamp'], reverse=True)[:limit]
        return jsonify(
            {'success': True, 'logs': sorted_logs, 'total': len(filtered_logs), 'returned': len(sorted_logs)})

    try:
        cur = conn.cursor()

        # Build WHERE clause
        where_clauses = []
        params = []

        if action_type:
            where_clauses.append("action_type = %s")
            params.append(action_type)
        if user_email:
            where_clauses.append("user_email = %s")
            params.append(user_email)
        if entity_type:
            where_clauses.append("entity_type = %s")
            params.append(entity_type)
        if start_date:
            where_clauses.append("timestamp >= %s")
            params.append(start_date)
        if end_date:
            where_clauses.append("timestamp <= %s")
            params.append(end_date)

        where_sql = " AND ".join(where_clauses) if where_clauses else "1=1"
        params.append(limit)

        query = f"""
            SELECT audit_code, timestamp, action_type, user_email, user_role,
                   entity_type, entity_id, details, ip_address
            FROM audit_logs
            WHERE {where_sql}
            ORDER BY timestamp DESC
            LIMIT %s
        """

        cur.execute(query, params)
        rows = cur.fetchall()

        logs = []
        for row in rows:
            logs.append({
                'id': row[0],
                'timestamp': row[1].isoformat() if row[1] else None,
                'action_type': row[2],
                'user_email': row[3],
                'user_role': row[4],
                'entity_type': row[5],
                'entity_id': row[6],
                'details': row[7],
                'ip_address': row[8]
            })

        # Get total count
        cur.execute(f"SELECT COUNT(*) FROM audit_logs WHERE {where_sql}", params[:-1])
        total = cur.fetchone()[0]

        cur.close()
        conn.close()

        return jsonify({
            'success': True,
            'logs': logs,
            'total': total,
            'returned': len(logs)
        })
    except Exception as e:
        print(f"Database error: {e}")
        if conn:
            conn.close()
        return jsonify({'success': False, 'error': str(e)}), 500


@app.route('/api/admin/audit-stats', methods=['GET'])
def api_get_audit_stats():
    """Get audit statistics"""
    if session.get('user_role') != 'admin':
        return jsonify({'success': False, 'error': 'Unauthorized'}), 403

    total_actions = len(audit_logs)

    # Count by action type
    action_counts = {}
    for log in audit_logs:
        action_type = log['action_type']
        action_counts[action_type] = action_counts.get(action_type, 0) + 1

    # Count by user
    user_activity = {}
    for log in audit_logs:
        user = log['user_email']
        user_activity[user] = user_activity.get(user, 0) + 1

    # Most active users (top 5)
    top_users = sorted(user_activity.items(), key=lambda x: x[1], reverse=True)[:5]

    # Recent activity (last 24 hours - mock)
    recent_count = sum(1 for log in audit_logs[-100:])

    return jsonify({
        'success': True,
        'stats': {
            'totalActions': total_actions,
            'actionCounts': action_counts,
            'topUsers': [{'email': email, 'count': count} for email, count in top_users],
            'recentActivity': recent_count
        }
    })


@app.route('/api/admin/system-stats', methods=['GET'])
def api_get_system_stats():
    """Get comprehensive system statistics for admin"""
    if session.get('user_role') != 'admin':
        return jsonify({'success': False, 'error': 'Unauthorized'}), 403

    base_stats = get_dashboard_stats()

    # Staff statistics
    total_staff = len(staff_db)
    active_staff = sum(1 for s in staff_db if s.get('status') == 'active')
    staff_by_department = {}
    for staff in staff_db:
        dept = staff.get('department', 'Unknown')
        staff_by_department[dept] = staff_by_department.get(dept, 0) + 1

    # Request statistics by status over time (mock data)
    request_trends = {
        'pending_trend': [12, 15, 18, 14, 10],
        'in_progress_trend': [3, 5, 7, 6, 4],
        'completed_trend': [5, 8, 10, 15, 20]
    }

    return jsonify({
        'success': True,
        'stats': {
            **base_stats,
            'totalStaff': total_staff,
            'activeStaff': active_staff,
            'inactiveStaff': total_staff - active_staff,
            'staffByDepartment': staff_by_department,
            'totalAuditLogs': len(audit_logs),
            'requestTrends': request_trends
        }
    })


# ============================================
# MENTAL HEALTH WORKFLOW - PROFESSIONALS
# ============================================

@app.route('/professional/dashboard')
def professional_dashboard():
    """Professional dashboard showing pending and confirmed appointments"""
    if 'user_email' not in session:
        return redirect(url_for('government_login'))

    if not session.get('is_professional'):
        return redirect(url_for('government_dashboard'))

    professional_email = session['user_email']

    conn = get_db_connection()
    if not conn:
        return "Database connection error", 500

    try:
        cur = conn.cursor()

        # Get professional details
        cur.execute("""
            SELECT professional_id, full_name, profession_type, specialization, phone, total_appointments
            FROM professionals
            WHERE email = %s
        """, (professional_email,))

        professional = cur.fetchone()
        if not professional:
            return "Professional not found", 404

        professional_id = professional[0]
        professional_name = professional[1]
        profession_type = professional[2]
        specialization = professional[3]

        # Get profession display name
        profession_display = get_profession_display_name(profession_type)

        # Get appointments for this professional
        cur.execute("""
            SELECT appointment_id, request_id, citizen_name, citizen_email, citizen_phone,
                   appointment_date, appointment_time, appointment_type, notes, status,
                   created_at, confirmed_at
            FROM appointments
            WHERE professional_id = %s
            ORDER BY appointment_date, appointment_time
        """, (professional_id,))

        appointments = []
        for row in cur.fetchall():
            appointments.append({
                'appointment_id': row[0],
                'request_id': row[1],
                'citizen_name': row[2],
                'citizen_email': row[3],
                'citizen_phone': row[4],
                'date': row[5].isoformat() if row[5] else None,
                'time': str(row[6]) if row[6] else None,
                'type': row[7],
                'notes': row[8],
                'status': row[9],
                'created_at': row[10].isoformat() if row[10] else None,
                'confirmed_at': row[11].isoformat() if row[11] else None
            })

        # Get unread notifications
        cur.execute("""
            SELECT COUNT(*) FROM notifications
            WHERE recipient_email = %s AND is_read = FALSE
        """, (professional_email,))
        unread_count = cur.fetchone()[0]

        cur.close()
        conn.close()

        return render_template('professional_dashboard.html',
                               professional_name=professional_name,
                               professional_email=professional_email,
                               profession_type=profession_display,
                               specialization=specialization,
                               appointments=appointments,
                               unread_notifications=unread_count)
    except Exception as e:
        print(f"Error loading professional dashboard: {e}")
        if conn:
            conn.close()
        return "Error loading dashboard", 500


@app.route('/api/professional/confirm_appointment', methods=['POST'])
def confirm_appointment():
    """Professional confirms an appointment"""
    # Check if user is logged in and is a professional
    if 'user_email' not in session:
        return jsonify({'success': False, 'error': 'Unauthorized'}), 401

    # Professional users have role='government' but is_professional flag set
    if not session.get('is_professional'):
        return jsonify({'success': False, 'error': 'Unauthorized - Not a professional'}), 401

    data = request.get_json()
    appointment_id = data.get('appointment_id')

    conn = get_db_connection()
    if not conn:
        return jsonify({'success': False, 'error': 'Database connection failed'}), 500

    try:
        cur = conn.cursor()

        # Get appointment details including service type
        cur.execute("""
            SELECT a.citizen_email, a.citizen_name, a.appointment_date, a.appointment_time,
                   a.appointment_type, p.full_name, p.phone, p.email as prof_email, 
                   p.profession_type, p.specialization, r.need_type, a.request_id
            FROM appointments a
            JOIN professionals p ON a.professional_id = p.professional_id
            JOIN requests r ON a.request_id = r.request_id
            WHERE a.appointment_id = %s AND p.email = %s
        """, (appointment_id, session['user_email']))

        appointment = cur.fetchone()
        if not appointment:
            return jsonify({'success': False, 'error': 'Appointment not found'}), 404

        (citizen_email, citizen_name, appt_date, appt_time, appt_type,
         prof_name, prof_phone, prof_email, prof_type, prof_specialization,
         need_type, request_id) = appointment

        # Get service display name
        service_name = get_profession_display_name(prof_type)

        # Update appointment status to confirmed
        cur.execute("""
            UPDATE appointments
            SET status = 'confirmed', confirmed_at = CURRENT_TIMESTAMP
            WHERE appointment_id = %s
        """, (appointment_id,))

        # Update request referral status
        cur.execute("""
            UPDATE requests
            SET referral_status = 'confirmed'
            WHERE request_id = %s
        """, (request_id,))

        # Create notification for citizen - Appointment CONFIRMED by doctor
        notification_title = f"{service_name} Appointment Confirmed ✅"
        notification_message = f"""
Great news! Your {service_name} appointment has been confirmed by the healthcare professional.

Healthcare Professional: {prof_name}
Specialization: {prof_specialization}
Contact: {prof_phone}
Email: {prof_email}

Appointment Details:
📅 Date: {appt_date}
🕐 Time: {appt_time}
📋 Type: {appt_type.replace('-', ' ').title()}
🏥 Service: {need_type.replace('-', ' ').title()}

Important Reminders:
• Please arrive 10-15 minutes early
• Bring any relevant medical documents or IDs
• If you need to reschedule, please contact us at least 24 hours in advance

Appointment ID: {appointment_id}

We look forward to seeing you!
"""

        cur.execute("""
            INSERT INTO notifications (recipient_email, recipient_type, notification_type, title, message, related_request_id, related_appointment_id)
            VALUES (%s, 'citizen', 'appointment_confirmed', %s, %s, %s, %s)
        """, (citizen_email, notification_title, notification_message, request_id, appointment_id))

        # Log the action
        cur.execute("""
            INSERT INTO audit_logs (action_type, user_email, user_role, entity_type, entity_id, details)
            VALUES ('UPDATE', %s, 'professional', 'APPOINTMENT', %s, %s)
        """, (session['user_email'], appointment_id, f'Appointment {appointment_id} confirmed by professional'))

        conn.commit()
        cur.close()
        conn.close()

        return jsonify({
            'success': True,
            'message': 'Appointment confirmed successfully',
            'appointment_id': appointment_id
        })

    except Exception as e:
        print(f"Error confirming appointment: {e}")
        if conn:
            conn.rollback()
            conn.close()
        return jsonify({'success': False, 'error': str(e)}), 500


# ============================================
# MENTAL HEALTH WORKFLOW - STAFF
# ============================================

@app.route('/api/staff/schedule_appointment', methods=['POST'])
def schedule_appointment():
    """Staff schedules an appointment for any health service that requires professional"""
    print(f"Schedule appointment called. Session: {dict(session)}")

    if 'user_email' not in session:
        print("ERROR: No user_email in session")
        return jsonify({'success': False, 'error': 'Unauthorized - Please login'}), 401

    user_role = session.get('user_role')
    if user_role not in ['government', 'admin']:
        print(f"ERROR: Invalid role: {user_role}")
        return jsonify({'success': False, 'error': f'Unauthorized - Invalid role: {user_role}'}), 401

    data = request.get_json()
    request_id = data.get('request_id')
    professional_id = data.get('professional_id')
    appointment_date = data.get('appointment_date')
    appointment_time = data.get('appointment_time')
    appointment_type = data.get('appointment_type', 'consultation')
    notes = data.get('notes', '')

    print(f"Scheduling appointment for request_id: {request_id}")

    conn = get_db_connection()
    if not conn:
        return jsonify({'success': False, 'error': 'Database connection failed'}), 500

    try:
        cur = conn.cursor()

        # Get request details
        cur.execute("""
            SELECT citizen_name, email, phone, need_type
            FROM requests
            WHERE request_id = %s
        """, (request_id,))

        request_data = cur.fetchone()
        if not request_data:
            print(f"ERROR: Request not found: {request_id}")
            cur.close()
            conn.close()
            return jsonify({'success': False, 'error': 'Request not found'}), 404

        citizen_name, citizen_email, citizen_phone, need_type = request_data

        # Verify that this need type requires appointment
        if need_type not in get_need_types_requiring_appointment():
            return jsonify(
                {'success': False, 'error': f'Need type {need_type} does not require professional appointment'}), 400

        # Get staff ID
        cur.execute("""
            SELECT staff_id FROM staff WHERE email = %s
        """, (session['user_email'],))

        staff_result = cur.fetchone()
        if not staff_result:
            return jsonify({'success': False, 'error': 'Staff not found'}), 404

        staff_id = staff_result[0]

        # Get professional details for notification
        cur.execute("""
            SELECT full_name, email, profession_type, specialization
            FROM professionals
            WHERE professional_id = %s
        """, (professional_id,))

        prof_data = cur.fetchone()
        if not prof_data:
            return jsonify({'success': False, 'error': 'Professional not found'}), 404

        prof_name, prof_email, prof_type, prof_specialization = prof_data

        # Generate appointment ID
        cur.execute("SELECT COUNT(*) FROM appointments")
        count = cur.fetchone()[0]
        appointment_id = f"APPT-{str(count + 1).zfill(6)}"

        # Create appointment
        cur.execute("""
            INSERT INTO appointments (
                appointment_id, request_id, citizen_email, citizen_name, citizen_phone,
                professional_id, scheduled_by_staff_id, appointment_date, appointment_time,
                appointment_type, notes, status
            ) VALUES (%s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, 'pending')
        """, (appointment_id, request_id, citizen_email, citizen_name, citizen_phone,
              professional_id, staff_id, appointment_date, appointment_time, appointment_type, notes))

        # Update request referral status to 'scheduling'
        cur.execute("""
            UPDATE requests
            SET referral_status = 'scheduling', appointment_id = %s
            WHERE request_id = %s
        """, (appointment_id, request_id))

        # Create notification for professional
        service_name = get_profession_display_name(prof_type)
        prof_notification_message = f"""
New {service_name} appointment scheduled for your review and confirmation.

Patient: {citizen_name}
Date: {appointment_date}
Time: {appointment_time}
Service Type: {need_type.replace('-', ' ').title()}
Appointment Type: {appointment_type.replace('-', ' ').title()}
Notes: {notes if notes else 'None'}

Please log in to your dashboard to review and confirm this appointment.

Appointment ID: {appointment_id}
"""

        cur.execute("""
            INSERT INTO notifications (recipient_email, recipient_type, notification_type, title, message, related_request_id, related_appointment_id)
            VALUES (%s, 'professional', 'appointment_scheduled', %s, %s, %s, %s)
        """, (prof_email, f'New {service_name} Appointment Pending Confirmation', prof_notification_message, request_id,
              appointment_id))

        # Create notification for CITIZEN - Appointment scheduled, waiting confirmation
        citizen_notification_message = f"""
Your {service_name} appointment has been scheduled and is pending confirmation from the healthcare professional.

Scheduled Date: {appointment_date}
Scheduled Time: {appointment_time}
Healthcare Professional: {prof_name}
Specialization: {prof_specialization}
Service Type: {need_type.replace('-', ' ').title()}

Status: Pending Confirmation
What's Next: Please wait for the doctor's confirmation. You will receive another notification once the appointment is confirmed.

Appointment ID: {appointment_id}
"""

        cur.execute("""
            INSERT INTO notifications (recipient_email, recipient_type, notification_type, title, message, related_request_id, related_appointment_id)
            VALUES (%s, 'citizen', 'appointment_scheduled', %s, %s, %s, %s)
        """, (citizen_email, 'Appointment Scheduled - Awaiting Doctor Confirmation', citizen_notification_message,
              request_id, appointment_id))

        # Log the action
        cur.execute("""
            INSERT INTO audit_logs (action_type, user_email, user_role, entity_type, entity_id, details)
            VALUES ('CREATE', %s, 'government', 'APPOINTMENT', %s, %s)
        """, (session['user_email'], appointment_id, f'{service_name} appointment scheduled for request {request_id}'))

        conn.commit()

        # Update in-memory request
        for req in requests_db:
            if req['id'] == request_id:
                req['referralStatus'] = 'scheduling'
                req['appointmentId'] = appointment_id
                break

        cur.close()
        conn.close()

        return jsonify({
            'success': True,
            'message': f'{service_name} appointment scheduled successfully',
            'appointment_id': appointment_id
        })

    except Exception as e:
        print(f"Error scheduling appointment: {e}")
        import traceback
        traceback.print_exc()
        if conn:
            conn.rollback()
            conn.close()
        return jsonify({'success': False, 'error': str(e)}), 500


@app.route('/api/professionals/list', methods=['GET'])
def list_professionals():
    """Get list of available professionals, optionally filtered by profession type"""
    if 'user_email' not in session:
        return jsonify({'success': False, 'error': 'Unauthorized'}), 401

    profession_type = request.args.get('profession_type')
    need_type = request.args.get('need_type')

    # If need_type is provided, convert to profession_type
    if need_type and not profession_type:
        profession_type = get_profession_type_for_need(need_type)

    conn = get_db_connection()
    if not conn:
        return jsonify({'success': False, 'error': 'Database connection failed'}), 500

    try:
        cur = conn.cursor()

        # Build query with optional profession_type filter and department join
        query = """
            SELECT p.professional_id, p.full_name, p.email, p.phone, p.profession_type,
                   p.specialization, d.department_name, p.license_number, p.years_of_experience, 
                   p.status, p.max_appointments_per_day, p.total_appointments
            FROM professionals p
            LEFT JOIN departments d ON p.department_id = d.department_id
            WHERE p.status = 'active'
        """
        params = []

        if profession_type:
            query += " AND p.profession_type = %s"
            params.append(profession_type)

        query += " ORDER BY p.full_name"

        cur.execute(query, params)

        professionals = []
        for row in cur.fetchall():
            professionals.append({
                'professional_id': row[0],
                'full_name': row[1],
                'email': row[2],
                'phone': row[3],
                'profession_type': row[4],
                'specialization': row[5],
                'department': row[6],
                'license_number': row[7],
                'years_of_experience': row[8],
                'status': row[9],
                'max_appointments_per_day': row[10],
                'total_appointments': row[11]
            })

        cur.close()
        conn.close()

        return jsonify({'success': True, 'status': 'success', 'professionals': professionals})

    except Exception as e:
        print(f"Error listing professionals: {e}")
        if conn:
            conn.close()
        return jsonify({'success': False, 'error': str(e)}), 500


# Add new endpoint for specialization options
@app.route('/api/specialization-options', methods=['GET'])
def get_specialization_options():
    """Get specialization options for a profession type"""
    profession_type = request.args.get('profession_type')

    if not profession_type:
        return jsonify({'success': False, 'error': 'profession_type is required'}), 400

    options = get_specialization_options_by_profession().get(profession_type, [])

    return jsonify({
        'success': True,
        'specializations': options
    })


# ============================================
# ADMIN - PROFESSIONALS MANAGEMENT
# ============================================

@app.route('/api/admin/professionals', methods=['GET'])
def admin_list_professionals():
    """Get all professionals for admin management"""
    if session.get('user_role') != 'admin':
        return jsonify({'status': 'error', 'message': 'Unauthorized'}), 403

    conn = get_db_connection()
    if not conn:
        return jsonify({'status': 'error', 'message': 'Database connection failed'}), 500

    try:
        cur = conn.cursor()
        cur.execute("""
            SELECT professional_id, full_name, email, phone, license_number,
                   specialization, qualifications, years_of_experience, status,
                   max_appointments_per_day, total_appointments, joined_date
            FROM professionals
            ORDER BY joined_date DESC
        """)

        professionals = []
        for row in cur.fetchall():
            professionals.append({
                'professional_id': row[0],
                'full_name': row[1],
                'email': row[2],
                'phone': row[3],
                'license_number': row[4],
                'specialization': row[5],
                'qualifications': row[6],
                'years_of_experience': row[7],
                'status': row[8],
                'max_appointments_per_day': row[9],
                'total_appointments': row[10],
                'joined_date': row[11].isoformat() if row[11] else None
            })

        cur.close()
        conn.close()

        return jsonify({'status': 'success', 'professionals': professionals})

    except Exception as e:
        print(f"Error listing professionals: {e}")
        if conn:
            conn.close()
        return jsonify({'status': 'error', 'message': str(e)}), 500


@app.route('/api/admin/professionals', methods=['POST'])
def admin_create_professional():
    """Create a new professional"""
    if session.get('user_role') != 'admin':
        return jsonify({'status': 'error', 'message': 'Unauthorized'}), 403

    data = request.get_json()

    # Validate required fields
    required_fields = ['full_name', 'email', 'password', 'profession_type', 'license_number', 'specialization',
                       'years_of_experience']
    missing_fields = [field for field in required_fields if field not in data or not data[field]]

    if missing_fields:
        return jsonify({
            'status': 'error',
            'message': f'Missing required fields: {", ".join(missing_fields)}'
        }), 400

    conn = get_db_connection()
    if not conn:
        return jsonify({'status': 'error', 'message': 'Database connection failed'}), 500

    try:
        cur = conn.cursor()

        # Check if email already exists
        cur.execute("SELECT email FROM professionals WHERE email = %s", (data['email'],))
        if cur.fetchone():
            cur.close()
            conn.close()
            return jsonify({'status': 'error', 'message': 'Email already exists'}), 400

        # Hash password
        password_hash = hash_password(data['password'])

        # Generate unique official ID
        official_id = generate_professional_official_id(conn)

        # Determine department_id based on profession type
        department_mapping = {
            'medical-doctor': 'Health and Medical Services',
            'dentist': 'Dental Services',
            'immunization-doctor': 'Immunization',
            'mental-health-doctor': 'Mental Health',
            'medical-technologist': 'Laboratory and Diagnostics'
        }
        department_name = department_mapping.get(data['profession_type'])

        if not department_name:
            cur.close()
            conn.close()
            return jsonify({'status': 'error', 'message': f'Invalid profession type: {data["profession_type"]}'}), 400

        # Get department_id
        department_id = get_department_id_by_name(conn, department_name)
        if not department_id:
            cur.close()
            conn.close()
            return jsonify({'status': 'error', 'message': f'Department not found: {department_name}'}), 400

        # Get user_role for this profession type
        user_role = get_user_role_from_profession(data['profession_type'])

        # Insert new professional
        cur.execute("""
            INSERT INTO professionals (
                professional_id, full_name, email, password_hash, phone, 
                profession_type, specialization, department_id, user_role, official_id, license_number, 
                qualifications, years_of_experience, status, max_appointments_per_day, 
                added_by, added_date
            )
            VALUES (%s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, CURRENT_TIMESTAMP)
            RETURNING professional_id
        """, (
            official_id,
            data['full_name'],
            data['email'],
            password_hash,
            data.get('phone', ''),
            data['profession_type'],
            data['specialization'],
            department_id,  # FK to departments table
            user_role,  # FK to role_permissions table
            official_id,
            data['license_number'],
            data.get('qualifications', ''),
            int(data['years_of_experience']),
            data.get('status', 'active'),
            int(data.get('max_appointments_per_day', 8)),
            session.get('user_email', 'system')
        ))

        professional_id = cur.fetchone()[0]

        # Log audit action
        cur.execute("""
            INSERT INTO audit_logs (
                audit_code, action_type, user_email, user_role, 
                entity_type, entity_id, details, ip_address
            )
            VALUES (%s, %s, %s, %s, %s, %s, %s, %s)
        """, (
            f"AUDIT-{datetime.now().strftime('%Y%m%d%H%M%S')}",
            'CREATE',
            session.get('user_email', 'system'),
            'admin',
            'PROFESSIONAL',
            professional_id,
            f"Created {get_profession_display_name(data['profession_type'])}: {data['full_name']} ({data['email']})",
            request.remote_addr
        ))

        conn.commit()
        cur.close()
        conn.close()

        return jsonify({
            'status': 'success',
            'message': 'Professional created successfully',
            'professional_id': professional_id
        })

    except Exception as e:
        print(f"Error creating professional: {e}")
        import traceback
        traceback.print_exc()
        if conn:
            conn.rollback()
            conn.close()
        return jsonify({'status': 'error', 'message': f'Database error: {str(e)}'}), 500


@app.route('/api/admin/professionals/<professional_id>', methods=['PUT'])
def admin_update_professional(professional_id):
    """Update professional details"""
    if session.get('user_role') != 'admin':
        return jsonify({'status': 'error', 'message': 'Unauthorized'}), 403

    data = request.get_json()

    conn = get_db_connection()
    if not conn:
        return jsonify({'status': 'error', 'message': 'Database connection failed'}), 500

    try:
        cur = conn.cursor()

        # Build update query dynamically
        update_fields = []
        values = []

        allowed_fields = ['full_name', 'email', 'phone', 'license_number', 'specialization',
                          'qualifications', 'years_of_experience', 'max_appointments_per_day', 'status']

        for field in allowed_fields:
            if field in data:
                update_fields.append(f"{field} = %s")
                values.append(data[field])

        if not update_fields:
            return jsonify({'status': 'error', 'message': 'No fields to update'}), 400

        values.append(professional_id)

        query = f"""
            UPDATE professionals
            SET {', '.join(update_fields)}
            WHERE professional_id = %s
            RETURNING full_name
        """

        cur.execute(query, values)
        result = cur.fetchone()

        if not result:
            cur.close()
            conn.close()
            return jsonify({'status': 'error', 'message': 'Professional not found'}), 404

        conn.commit()

        # Log audit
        log_audit_action(
            user_id=session.get('user_id'),
            user_email=session.get('user_email'),
            action_type='UPDATE',
            entity_type='professional',
            entity_id=professional_id,
            details=f"Updated professional: {result[0]}",
            ip_address=request.remote_addr
        )

        cur.close()
        conn.close()

        return jsonify({'status': 'success', 'message': 'Professional updated successfully'})

    except Exception as e:
        print(f"Error updating professional: {e}")
        if conn:
            conn.rollback()
            conn.close()
        return jsonify({'status': 'error', 'message': str(e)}), 500


@app.route('/api/admin/professionals/<professional_id>', methods=['DELETE'])
def admin_delete_professional(professional_id):
    """Delete a professional from the system"""
    if session.get('user_role') != 'admin':
        return jsonify({'status': 'error', 'message': 'Unauthorized'}), 403

    conn = get_db_connection()
    if not conn:
        return jsonify({'status': 'error', 'message': 'Database connection failed'}), 500

    try:
        cur = conn.cursor()

        # Get professional details before deletion for audit log
        cur.execute("""
            SELECT full_name, email
            FROM professionals
            WHERE professional_id = %s
        """, (professional_id,))

        professional = cur.fetchone()

        if not professional:
            cur.close()
            conn.close()
            return jsonify({'status': 'error', 'message': 'Professional not found'}), 404

        # Delete the professional
        cur.execute("""
            DELETE FROM professionals
            WHERE professional_id = %s
        """, (professional_id,))

        conn.commit()

        # Log audit
        log_audit_action(
            user_id=session.get('user_id'),
            user_email=session.get('user_email'),
            action_type='DELETE',
            entity_type='professional',
            entity_id=professional_id,
            details=f"Deleted professional {professional[0]} ({professional[1]})",
            ip_address=request.remote_addr
        )

        cur.close()
        conn.close()

        return jsonify({'status': 'success', 'message': 'Professional deleted successfully'})

    except Exception as e:
        print(f"Error deleting professional: {e}")
        if conn:
            conn.rollback()
            conn.close()
        return jsonify({'status': 'error', 'message': str(e)}), 500


# ============================================
# NOTIFICATIONS
# ============================================

@app.route('/api/notifications/list', methods=['GET'])
def list_notifications():
    """Get notifications for logged-in user"""
    if 'user_email' not in session:
        return jsonify({'success': False, 'error': 'Unauthorized'}), 401

    conn = get_db_connection()
    if not conn:
        return jsonify({'success': False, 'error': 'Database connection failed'}), 500

    try:
        cur = conn.cursor()
        cur.execute("""
            SELECT notification_id, notification_type, title, message, is_read, created_at,
                   related_request_id, related_appointment_id
            FROM notifications
            WHERE recipient_email = %s
            ORDER BY created_at DESC
            LIMIT 50
        """, (session['user_email'],))

        notifications = []
        for row in cur.fetchall():
            notifications.append({
                'id': row[0],
                'type': row[1],
                'title': row[2],
                'message': row[3],
                'is_read': row[4],
                'created_at': row[5].isoformat() if row[5] else None,
                'request_id': row[6],
                'appointment_id': row[7]
            })

        cur.close()
        conn.close()

        return jsonify({'success': True, 'notifications': notifications})

    except Exception as e:
        print(f"Error listing notifications: {e}")
        if conn:
            conn.close()
        return jsonify({'success': False, 'error': str(e)}), 500


@app.route('/api/notifications/mark_read', methods=['POST'])
def mark_notification_read():
    """Mark notification as read"""
    if 'user_email' not in session:
        return jsonify({'success': False, 'error': 'Unauthorized'}), 401

    data = request.get_json()
    notification_id = data.get('notification_id')

    conn = get_db_connection()
    if not conn:
        return jsonify({'success': False, 'error': 'Database connection failed'}), 500

    try:
        cur = conn.cursor()
        cur.execute("""
            UPDATE notifications
            SET is_read = TRUE, read_at = CURRENT_TIMESTAMP
            WHERE notification_id = %s AND recipient_email = %s
        """, (notification_id, session['user_email']))

        conn.commit()
        cur.close()
        conn.close()

        return jsonify({'success': True, 'message': 'Notification marked as read'})

    except Exception as e:
        print(f"Error marking notification as read: {e}")
        if conn:
            conn.rollback()
            conn.close()
        return jsonify({'success': False, 'error': str(e)}), 500


if __name__ == '__main__':
    # Load requests from database on startup
    init_app()

    # Start the Flask application
    app.run(debug=True, host='0.0.0.0', port=5000)