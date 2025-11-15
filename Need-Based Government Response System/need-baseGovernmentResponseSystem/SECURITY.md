# Security Documentation

## Password Security

### Hashing Method: **bcrypt ONLY**

This system uses **bcrypt** exclusively for all password hashing operations. 

#### Why bcrypt?
- ✅ Industry-standard password hashing algorithm
- ✅ Automatically generates and manages salts
- ✅ Computationally expensive (resistant to brute force attacks)
- ✅ Resistant to rainbow table attacks
- ✅ Constant-time comparison (prevents timing attacks)

#### Implementation Details

**Hash Generation:**
```python
def hash_password(password):
    salt = bcrypt.gensalt()  # Automatic salt generation
    hashed = bcrypt.hashpw(password.encode('utf-8'), salt)
    return hashed.decode('utf-8')
```

**Password Verification:**
```python
def verify_password(plain_password, hashed_password):
    return bcrypt.checkpw(plain_password.encode('utf-8'), 
                         hashed_password.encode('utf-8'))
```

### Database Storage

All passwords in the database are stored as bcrypt hashes:
- ✅ `professionals.password_hash` - bcrypt hash
- ✅ `staff.password_hash` - bcrypt hash
- ✅ In-memory `users_db` - bcrypt hash

**Never store plain text passwords!**

## Environment Variables

Sensitive configuration is managed through environment variables:

### Required Environment Variables

Create a `.env` file (see `.env.example`):

```bash
# Flask Configuration
FLASK_SECRET_KEY=your-secure-random-secret-key-here

# Database Configuration
DB_HOST=localhost
DB_NAME=Need-baseGovernmentResponseSystem
DB_USER=postgres
DB_PASSWORD=your-database-password-here
DB_PORT=5432
```

### Using Environment Variables

```python
import os

# Flask secret key
app.secret_key = os.environ.get('FLASK_SECRET_KEY', 'fallback-dev-key')

# Database connection
conn = psycopg2.connect(
    host=os.environ.get('DB_HOST', 'localhost'),
    database=os.environ.get('DB_NAME', 'database_name'),
    user=os.environ.get('DB_USER', 'postgres'),
    password=os.environ.get('DB_PASSWORD', 'password'),
    port=int(os.environ.get('DB_PORT', '5432'))
)
```

## Security Best Practices

### ✅ Implemented

1. **Password Hashing**: All passwords use bcrypt
2. **Environment Variables**: Sensitive data in `.env` file
3. **Session Management**: Flask sessions with secret key
4. **SQL Parameterization**: Prevents SQL injection
5. **Role-Based Access Control**: Different permissions for admin/staff/professionals
6. **Audit Logging**: All actions logged with timestamps

### 🔒 Production Recommendations

1. **HTTPS Only**: Use SSL/TLS in production
2. **Strong Secret Key**: Generate with `os.urandom(24)`
3. **Password Policy**: Minimum 8 characters, complexity requirements
4. **Rate Limiting**: Prevent brute force login attempts
5. **Session Timeout**: Automatic logout after inactivity
6. **Input Validation**: Sanitize all user inputs
7. **CORS Configuration**: Restrict allowed origins
8. **Database Backups**: Regular automated backups
9. **Security Headers**: Set CSP, X-Frame-Options, etc.
10. **Regular Updates**: Keep all dependencies updated

## Password Reset Workflow

For production, implement:
1. Email-based password reset
2. Temporary reset tokens (expire in 1 hour)
3. Token hashed in database
4. New password must be different from old
5. Email notification on password change

## Development vs Production

### Development (Current)
- Default database credentials in code (with env var fallback)
- Mock data with test passwords
- Debug mode enabled

### Production Checklist
- [ ] Set `FLASK_ENV=production`
- [ ] Set `FLASK_DEBUG=False`
- [ ] Use strong `FLASK_SECRET_KEY`
- [ ] Use environment variables for all secrets
- [ ] Remove mock data initialization
- [ ] Enable HTTPS
- [ ] Set up proper logging
- [ ] Configure firewall rules
- [ ] Use production-grade WSGI server (gunicorn, uwsgi)
- [ ] Regular security audits

## Contact

For security issues, contact: security@example.com

**Do not** disclose security vulnerabilities publicly.
