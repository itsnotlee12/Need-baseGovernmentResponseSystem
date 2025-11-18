# Testing Guide - Staff Creation Fix

## Issue Fixed
✅ **"Error saving staff member"** - The application was trying to insert a department name (string) into a `department_id` field (integer foreign key).

## How to Test Staff Creation

### 1. Login as Admin
1. Go to `/admin/login`
2. Use admin credentials from your database
3. Navigate to Admin Dashboard

### 2. Create a Staff Member - Sanitary Officer

**Form Fields:**
- Full Name: `Rafael Santos`
- Email: `rafael.santos@cityhealth.gov`
- Phone: `+63919850274`
- Password: `rafael123`
- Department: `Sanitary Inspection` ✅
- Role: `Officer`
- Permissions: Check "View Requests" and "Manage Requests"

**Expected Result:**
- ✅ Staff member created successfully
- Staff will have:
  - `department_id = 7` (Sanitary Inspection from departments table)
  - `user_role = 'officer_sanitary'` (automatically set)
  - Auto-generated `official_id` like `GOV-10002`

### 3. Create a Staff Member - Health Officer

**Form Fields:**
- Full Name: `Maria Cruz`
- Email: `maria.cruz2@cityhealth.gov`
- Phone: `+63912345678`
- Password: `maria123`
- Department: `Health and Medical Services` ✅
- Role: `Officer`
- Permissions: Check "View Requests" and "Manage Requests"

**Expected Result:**
- ✅ Staff member created successfully
- Staff will have:
  - `department_id = 2` (Health and Medical Services)
  - `user_role = 'officer_health'` (automatically set)
  - Can view medical, dental, immunization, laboratory, and mental-health requests

### 4. Create an Admin

**Form Fields:**
- Full Name: `Admin User`
- Email: `admin.user@cityhealth.gov`
- Phone: `+63911111111`
- Password: `admin123`
- Department: `Administration` ✅
- Role: `Admin`
- Permissions: (All auto-granted for admin)

**Expected Result:**
- ✅ Admin created successfully
- Admin will have:
  - `department_id = 1` (Administration)
  - `user_role = 'admin'` (automatically set)
  - Can view ALL requests (full access)

## How to Test Professional Creation

### 1. Create a Medical Doctor

**Form Fields:**
- Full Name: `Dr. Juan dela Cruz`
- Email: `juan.delacruz@cityhealth.gov`
- Phone: `+63917777777`
- Password: `doctor123`
- Profession Type: `Medical Doctor` ✅
- Specialization: `General Medicine`
- License Number: `LIC-MED-002`
- Years of Experience: `5`

**Expected Result:**
- ✅ Professional created successfully
- Professional will have:
  - `department_id = 2` (Health and Medical Services)
  - `user_role = 'medical_doctor'`
  - `profession_type = 'medical-doctor'`
  - Can view only MEDICAL requests

### 2. Create a Mental Health Doctor

**Form Fields:**
- Full Name: `Dr. Anna Santos`
- Email: `anna.santos@cityhealth.gov`
- Phone: `+63918888888`
- Password: `mental123`
- Profession Type: `Mental Health Doctor` ✅
- Specialization: `Psychiatry`
- License Number: `LIC-MENT-002`
- Years of Experience: `8`

**Expected Result:**
- ✅ Professional created successfully
- Professional will have:
  - `department_id = 3` (Mental Health)
  - `user_role = 'mental_health_doctor'`
  - Can view only MENTAL-HEALTH requests

## Verify Database RLS is Working

### Test 1: Officer Sanitary Access
1. Login as sanitary officer (`rafael.santos@cityhealth.gov`)
2. Go to Government Dashboard
3. **Expected**: Should ONLY see requests with `need_type = 'sanitary-inspection'`
4. **Should NOT see**: Medical, dental, mental health requests

### Test 2: Officer Health Access
1. Login as health officer (`maria.cruz2@cityhealth.gov`)
2. Go to Government Dashboard
3. **Expected**: Should see requests with:
   - `medical`
   - `dental-services`
   - `immunization`
   - `laboratory`
   - `mental-health`
4. **Should NOT see**: `sanitary-inspection` requests

### Test 3: Professional Access
1. Login as medical doctor (`juan.delacruz@cityhealth.gov`)
2. Go to Professional Dashboard
3. **Expected**: Should ONLY see appointments for `medical` requests
4. **Should NOT see**: Dental, mental health, or other appointments

### Test 4: Admin Full Access
1. Login as admin (`admin.user@cityhealth.gov`)
2. Go to Admin Dashboard
3. **Expected**: Should see ALL requests, ALL staff, ALL professionals

## Common Errors and Solutions

### Error: "Invalid department: [department name]"
**Cause**: Department name doesn't exist in `departments` table
**Solution**: Check that department dropdown options match database exactly:
- `Administration`
- `Health and Medical Services`
- `Mental Health`
- `Dental Services`
- `Immunization`
- `Laboratory and Diagnostics`
- `Sanitary Inspection`

### Error: "Database connection failed"
**Cause**: PostgreSQL not running or wrong credentials
**Solution**: 
1. Check PostgreSQL is running
2. Verify `DB_PASSWORD` in environment or app.py (default: '123')
3. Verify `DB_NAME` is `Need-baseGovernmentResponseSystem`

### Error: Staff created but no requests visible
**Cause**: RLS policies may not be set correctly or user_role is wrong
**Solution**:
1. Check `staff` table: `SELECT staff_id, email, user_role, department_id FROM staff;`
2. Verify `user_role` matches `role_permissions` table
3. Check RLS policies: `SELECT * FROM pg_policies WHERE tablename = 'requests';`

## SQL Queries to Verify Data

### Check Staff Creation
```sql
SELECT 
    s.staff_id, 
    s.full_name, 
    s.email, 
    s.user_role,
    d.department_name
FROM staff s
LEFT JOIN departments d ON s.department_id = d.department_id
ORDER BY s.added_date DESC;
```

### Check Professional Creation
```sql
SELECT 
    p.professional_id, 
    p.full_name, 
    p.email, 
    p.profession_type,
    p.user_role,
    d.department_name
FROM professionals p
LEFT JOIN departments d ON p.department_id = d.department_id
ORDER BY p.added_date DESC;
```

### Check Role Permissions
```sql
SELECT role_name, allowed_need_types 
FROM role_permissions 
WHERE role_name IN ('officer_sanitary', 'officer_health', 'medical_doctor');
```

### Check RLS Policies
```sql
SELECT 
    schemaname, 
    tablename, 
    policyname, 
    roles, 
    cmd
FROM pg_policies
WHERE tablename = 'requests'
ORDER BY policyname;
```

## Success Criteria

✅ Staff member can be created without errors
✅ Professional can be created without errors
✅ Staff member has correct `department_id` (not department name)
✅ Staff member has correct `user_role` based on department
✅ Professional has correct `department_id` based on profession_type
✅ Professional has correct `user_role` based on profession_type
✅ Different roles see different requests (RLS working)
✅ No application-level filtering errors
✅ Department names displayed correctly in frontend

## Troubleshooting Steps

1. **Check Flask Logs**: Look for database errors in terminal
2. **Check Browser Console**: Look for JavaScript errors
3. **Check PostgreSQL Logs**: Look for constraint violations
4. **Verify Foreign Keys**: Ensure `department_id` and `user_role` exist
5. **Test Database Directly**: Use psql to insert test data

---
**Last Updated**: November 18, 2025
